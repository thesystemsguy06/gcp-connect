#!/bin/bash
# VectorPlane GCP Integration — Device Flow Onboarding (RFC 8628)
# Exchanges a pairing code for the full Terraform configuration,
# then deploys Workload Identity Federation via Terraform.

set -e

# Production default; override with VP_API_BASE for dev/testing
API_BASE="${VP_API_BASE:-https://api.vectorplane.io}"
EXCHANGE_URL="${API_BASE}/api/v1/onboarding/gcp/pairing-exchange"
ERROR_URL="${API_BASE}/api/v1/onboarding/gcp/report-error"

# Session ID — set after successful pairing exchange
SESSION_ID=""

# ── Error reporting (sends telemetry to dashboard on failure) ─────────
report_error() {
    local error_type="${1:-unexpected}"
    local detail="${2:-}"
    if [ -n "$SESSION_ID" ]; then
        curl -s -X POST "$ERROR_URL" \
            -H "Content-Type: application/json" \
            -d "{\"session_id\": \"$SESSION_ID\", \"error_type\": \"$error_type\", \"detail\": \"$detail\"}" \
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
    echo "[1/4] Authenticating with VectorPlane..."

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

    if [ $ATTEMPT -lt $MAX_CODE_ATTEMPTS ]; then
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
# trap ensures the dashboard knows what went wrong if any step fails

# ── Step 2: Align GCP project + enable APIs ───────────────────────────
echo ""
echo "[2/4] Preparing GCP project..."

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
    --quiet 2>&1; then
    report_error "api_enable" "Failed to enable required GCP APIs. Check project permissions."
    echo "Error: Failed to enable GCP APIs. You may need the Owner or Editor role."
    exit 1
fi
echo "GCP APIs enabled."

# ── Step 3: Terraform init ────────────────────────────────────────────
echo ""
echo "[3/4] Initializing Terraform..."
if ! terraform init -input=false 2>&1; then
    report_error "terraform_init" "terraform init failed"
    echo "Error: Terraform initialization failed."
    exit 1
fi

# ── Step 4: Terraform apply ───────────────────────────────────────────
echo ""
echo "[4/4] Deploying integration..."
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
    # Extract last meaningful error line
    LAST_ERROR=$(echo "$TF_OUTPUT" | grep -i "error" | tail -1 | head -c 500)
    report_error "terraform_apply" "$LAST_ERROR"
    echo ""
    echo "Error: Deployment failed. Your VectorPlane dashboard will show details."
    exit 1
fi
