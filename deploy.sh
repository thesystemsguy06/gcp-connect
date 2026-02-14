#!/bin/bash
# VectorPlane GCP Integration — Device Flow Onboarding (RFC 8628)
# Exchanges a pairing code for the full Terraform configuration,
# then deploys Workload Identity Federation via Terraform.
#
# Idempotent: safe to re-run after partial failures.
#   - Terraform state is stored in a GCS bucket (survives Cloud Shell restarts)
#   - Pre-flight recovery handles soft-deleted and orphaned GCP resources
#   - Every failure reports clean error details to the VectorPlane dashboard

set -e

# Production default; override with VP_API_BASE for dev/testing
API_BASE="${VP_API_BASE:-https://api.vectorplane.io}"
EXCHANGE_URL="${API_BASE}/api/v1/onboarding/gcp/pairing-exchange"
ERROR_URL="${API_BASE}/api/v1/onboarding/gcp/report-error"

# Session ID — set after successful pairing exchange
SESSION_ID=""

# ── Helpers ───────────────────────────────────────────────────────────

# Strip ANSI escape codes and Terraform box-drawing characters.
# Terraform wraps errors in ANSI color codes and Unicode box chars
# that are unreadable in a web dashboard.
clean_tf_output() {
    sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r│' | sed 's/^[[:space:]]*//'
}

# Send error telemetry to VectorPlane dashboard.
# Uses jq for safe JSON encoding (handles quotes, newlines, special chars).
report_error() {
    local error_type="${1:-unexpected}"
    local detail="${2:-}"
    if [ -n "$SESSION_ID" ]; then
        local payload
        payload=$(jq -n \
            --arg sid "$SESSION_ID" \
            --arg etype "$error_type" \
            --arg det "$detail" \
            '{session_id: $sid, error_type: $etype, detail: $det}')
        curl -s -X POST "$ERROR_URL" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            > /dev/null 2>&1 || true
    fi
}

echo ""
echo "------------------------------------------------"
echo "  VectorPlane GCP Onboarding"
echo "------------------------------------------------"
echo ""

# ── Step 1: Pairing Code (with retry) ────────────────────────────────
MAX_CODE_ATTEMPTS=3
ATTEMPT=0
BODY=""

while [ $ATTEMPT -lt $MAX_CODE_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))

    read -p "Enter pairing code from dashboard (e.g. VP-XXXX): " USER_CODE
    USER_CODE=$(echo "$USER_CODE" | tr '[:lower:]' '[:upper:]' | xargs)

    if [ -z "$USER_CODE" ]; then
        echo "No code entered."
        if [ $ATTEMPT -lt $MAX_CODE_ATTEMPTS ]; then
            echo ""
            continue
        fi
        echo "Max attempts reached. Get a fresh code from your VectorPlane dashboard."
        exit 1
    fi

    echo ""
    echo "[1/5] Authenticating with VectorPlane..."

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$EXCHANGE_URL" \
        -H "Content-Type: application/json" \
        -d "{\"pairing_code\": \"$USER_CODE\"}")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ]; then
        break
    fi

    ERROR_MSG=$(echo "$BODY" | jq -r '.detail // "Unknown error"' 2>/dev/null || echo "$BODY")
    echo "Error: $ERROR_MSG"

    if [ "$HTTP_CODE" = "410" ]; then
        echo ""
        echo "A newer code was generated. Check your VectorPlane dashboard."
        echo ""
    elif [ $ATTEMPT -lt $MAX_CODE_ATTEMPTS ]; then
        echo ""
        echo "Try again, or get a new code from your VectorPlane dashboard."
        echo ""
    else
        echo ""
        echo "Max attempts reached. Please regenerate a code in the dashboard."
        exit 1
    fi
done

# Write the full payload as terraform.tfvars.json
echo "$BODY" > terraform.tfvars.json

# Validate JSON
if ! jq empty terraform.tfvars.json 2>/dev/null; then
    echo "Error: Invalid configuration received."
    exit 1
fi

# Extract session ID for error reporting
SESSION_ID=$(jq -r '.external_id' terraform.tfvars.json)
PROJECT_ID=$(jq -r '.project_id' terraform.tfvars.json)
echo "Identity verified. Project: $PROJECT_ID"

# ── From here on, errors are reported to the dashboard ────────────────

# ── Step 2: Align GCP project + enable APIs ───────────────────────────
echo ""
echo "[2/5] Preparing GCP project..."

CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
    gcloud config set project "$PROJECT_ID" --quiet
fi

if ! gcloud services enable \
    iam.googleapis.com \
    cloudresourcemanager.googleapis.com \
    sts.googleapis.com \
    iamcredentials.googleapis.com \
    securitycenter.googleapis.com \
    storage.googleapis.com \
    --quiet 2>&1; then
    report_error "api_enable" "Failed to enable required GCP APIs. Check project permissions."
    echo "Error: Failed to enable GCP APIs. You may need the Owner or Editor role."
    exit 1
fi
echo "GCP APIs enabled."

# ── Step 3: Set up remote state backend (GCS) ────────────────────────
# Terraform state is stored in GCS so retries after partial failures
# "just work" — Cloud Shell sessions are ephemeral but GCS persists.
echo ""
echo "[3/5] Configuring state backend..."

STATE_BUCKET="${PROJECT_ID}-vectorplane-tf-state"

# Create bucket if it doesn't exist (idempotent)
if ! gcloud storage buckets describe "gs://${STATE_BUCKET}" --project="$PROJECT_ID" > /dev/null 2>&1; then
    if ! gcloud storage buckets create "gs://${STATE_BUCKET}" \
        --project="$PROJECT_ID" \
        --location=us \
        --uniform-bucket-level-access \
        --quiet 2>&1; then
        report_error "state_bucket" "Failed to create Terraform state bucket"
        echo "Error: Could not create state bucket. You may need Storage Admin permissions."
        exit 1
    fi
    echo "  Created state bucket: ${STATE_BUCKET}"
else
    echo "  Using existing state bucket: ${STATE_BUCKET}"
fi

# Generate backend config for Terraform
cat > backend.tf <<BACKEND_EOF
terraform {
  backend "gcs" {
    bucket = "${STATE_BUCKET}"
    prefix = "vectorplane/gcp-onboarding"
  }
}
BACKEND_EOF

# ── Step 4: Terraform init + pre-flight recovery ─────────────────────
echo ""
echo "[4/5] Initializing Terraform..."
if ! terraform init -input=false -reconfigure 2>&1; then
    report_error "terraform_init" "terraform init failed"
    echo "Error: Terraform initialization failed."
    exit 1
fi

# --- Pre-flight resource recovery ---
# Handles two edge cases that would otherwise cause 409 conflicts:
#   (a) Resources exist in GCP but not in Terraform state (orphaned from
#       a previous session that used a different state backend)
#   (b) Resources were soft-deleted (GCP retains for 30 days) — must be
#       undeleted before Terraform can manage them again
#
# If state already has resources (normal retry), this block is skipped entirely.

RESOURCES=$(terraform state list 2>/dev/null || echo "")
if [ -z "$RESOURCES" ]; then
    echo "  Reconciling with existing GCP resources..."

    # Read resource IDs from tfvars
    WIF_POOL_ID=$(jq -r '.wif_pool_id' terraform.tfvars.json)
    WIF_PROVIDER_ID=$(jq -r '.wif_provider_id' terraform.tfvars.json)
    DEV_OIDC_URL=$(jq -r '.dev_oidc_issuer_url // ""' terraform.tfvars.json)
    SA_ID="vectorplane-security"
    SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
    POOL_PATH="projects/${PROJECT_ID}/locations/global/workloadIdentityPools/${WIF_POOL_ID}"

    # Phase 1: Undelete soft-deleted resources (idempotent — fails silently
    # if the resource is already active or was never created)
    if gcloud iam workload-identity-pools undelete "$WIF_POOL_ID" \
        --location=global --project="$PROJECT_ID" --quiet > /dev/null 2>&1; then
        echo "    Restored soft-deleted WIF pool"
        sleep 3  # Wait for pool restoration to propagate
    fi

    if gcloud iam workload-identity-pools providers undelete "$WIF_PROVIDER_ID" \
        --workload-identity-pool="$WIF_POOL_ID" \
        --location=global --project="$PROJECT_ID" --quiet > /dev/null 2>&1; then
        echo "    Restored soft-deleted AWS provider"
    fi

    if [ -n "$DEV_OIDC_URL" ]; then
        if gcloud iam workload-identity-pools providers undelete "vectorplane-dev-oidc" \
            --workload-identity-pool="$WIF_POOL_ID" \
            --location=global --project="$PROJECT_ID" --quiet > /dev/null 2>&1; then
            echo "    Restored soft-deleted OIDC provider"
        fi
    fi

    # Phase 2: Import existing resources into Terraform state.
    # Each import succeeds if the resource exists in GCP, fails silently if not.
    # This lets terraform apply update/no-op existing resources instead of
    # trying to create them (which would 409).
    IMPORTED=0

    if terraform import -input=false \
        "google_iam_workload_identity_pool.vectorplane" \
        "$POOL_PATH" > /dev/null 2>&1; then
        echo "    Imported WIF pool"
        IMPORTED=$((IMPORTED + 1))
    fi

    if terraform import -input=false \
        "google_iam_workload_identity_pool_provider.aws" \
        "${POOL_PATH}/providers/${WIF_PROVIDER_ID}" > /dev/null 2>&1; then
        echo "    Imported AWS provider"
        IMPORTED=$((IMPORTED + 1))
    fi

    if [ -n "$DEV_OIDC_URL" ]; then
        if terraform import -input=false \
            'google_iam_workload_identity_pool_provider.dev_oidc[0]' \
            "${POOL_PATH}/providers/vectorplane-dev-oidc" > /dev/null 2>&1; then
            echo "    Imported OIDC provider"
            IMPORTED=$((IMPORTED + 1))
        fi
    fi

    if terraform import -input=false \
        "google_service_account.vectorplane" \
        "projects/${PROJECT_ID}/serviceAccounts/${SA_EMAIL}" > /dev/null 2>&1; then
        echo "    Imported service account"
        IMPORTED=$((IMPORTED + 1))
    fi

    if [ $IMPORTED -gt 0 ]; then
        echo "  Recovered $IMPORTED existing resource(s) into state."
    else
        echo "  No existing resources found. Fresh deployment."
    fi
else
    echo "  State loaded ($(echo "$RESOURCES" | wc -l | tr -d ' ') resources). Resuming."
fi

# ── Step 5: Terraform apply ───────────────────────────────────────────
echo ""
echo "[5/5] Deploying integration..."
TF_OUTPUT=""
if TF_OUTPUT=$(terraform apply -auto-approve -input=false 2>&1); then
    echo "$TF_OUTPUT"
    echo ""
    echo "================================================"
    echo "  VectorPlane GCP integration deployed!"
    echo ""
    echo "  - Workload Identity Federation active"
    echo "  - Zero service account keys exchanged"
    echo "  - Check your VectorPlane dashboard for findings"
    echo ""
    echo "  To remove: terraform destroy"
    echo "================================================"
else
    echo "$TF_OUTPUT"
    # Extract clean error lines for dashboard (strip ANSI codes + box chars)
    LAST_ERROR=$(echo "$TF_OUTPUT" | clean_tf_output | grep -i "error" | tail -3 | head -c 500)
    report_error "terraform_apply" "$LAST_ERROR"
    echo ""
    echo "Error: Deployment failed. Your VectorPlane dashboard will show details."
    exit 1
fi
