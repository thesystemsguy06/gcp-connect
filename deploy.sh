#!/bin/bash
# VectorPlane GCP Integration - One-Command Deploy
# Implements the "Phoning Home" pattern: extracts session context from
# the git remote URL and calls the backend to get Terraform variables.

set -e

echo ""
echo "🚀 VectorPlane GCP Integration"
echo "════════════════════════════════════════════════════════"
echo ""

# ── Step 1: Extract session context from git remote URL ──────────────
# The backend encodes sid, sig, and api as query params on the git repo URL.
# Cloud Shell clones the repo normally (GitHub ignores query params),
# but the full URL is preserved in .git/config.

REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")

if [ -z "$REMOTE_URL" ]; then
    echo "❌ Not a git repository. Please restart from VectorPlane."
    exit 1
fi

# Parse query parameters from the remote URL
SESSION_ID=$(echo "$REMOTE_URL" | sed -n 's/.*[?&]sid=\([^&]*\).*/\1/p')
SIGNATURE=$(echo "$REMOTE_URL" | sed -n 's/.*[?&]sig=\([^&]*\).*/\1/p')
API_BASE=$(echo "$REMOTE_URL" | sed -n 's/.*[?&]api=\([^&]*\).*/\1/p')

# URL-decode the API base (handles %3A for : and %2F for /)
API_BASE=$(python3 -c "import urllib.parse,sys; print(urllib.parse.unquote(sys.argv[1]))" "$API_BASE" 2>/dev/null || echo "$API_BASE")

if [ -z "$SESSION_ID" ] || [ -z "$SIGNATURE" ] || [ -z "$API_BASE" ]; then
    echo "❌ Session context not found in repository URL."
    echo "   Please restart onboarding from the VectorPlane dashboard."
    exit 1
fi

echo "✅ Session context found"
echo "   Session: ${SESSION_ID:0:20}..."
echo "   API: $API_BASE"
echo ""

# ── Step 2: Phone home for Terraform configuration ───────────────────
echo "Step 1/4: Retrieving configuration from VectorPlane..."

CONTEXT_URL="${API_BASE}/api/v1/onboarding/gcp/session-context?sid=${SESSION_ID}&sig=${SIGNATURE}"

HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" "$CONTEXT_URL")
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n1)
BODY=$(echo "$HTTP_RESPONSE" | head -n -1)

if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ Failed to retrieve configuration (HTTP $HTTP_CODE)"
    case $HTTP_CODE in
        403) echo "   Invalid signature. Session may have been tampered with." ;;
        404) echo "   Session not found or expired." ;;
        410) echo "   Session is no longer active." ;;
        *) echo "   Response: $BODY" ;;
    esac
    echo ""
    echo "   Please restart onboarding from the VectorPlane dashboard."
    exit 1
fi

# Write terraform.tfvars.json
echo "$BODY" > terraform.tfvars.json

# Validate JSON
if ! python3 -m json.tool terraform.tfvars.json > /dev/null 2>&1; then
    echo "❌ Invalid configuration received"
    exit 1
fi

echo "✅ Configuration retrieved"

# ── Step 3: Align GCP project context ────────────────────────────────
EXPECTED_PROJECT=$(python3 -c "import json; print(json.load(open('terraform.tfvars.json'))['project_id'])" 2>/dev/null || echo "")

if [ -n "$EXPECTED_PROJECT" ]; then
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    if [ "$CURRENT_PROJECT" != "$EXPECTED_PROJECT" ]; then
        echo "🔄 Aligning project context to $EXPECTED_PROJECT..."
        gcloud config set project "$EXPECTED_PROJECT" --quiet
    fi
    echo "✅ Project: $EXPECTED_PROJECT"
fi

# ── Step 4: Enable required GCP APIs ─────────────────────────────────
echo ""
echo "Step 2/4: Enabling required GCP APIs..."
gcloud services enable \
    iam.googleapis.com \
    cloudresourcemanager.googleapis.com \
    sts.googleapis.com \
    iamcredentials.googleapis.com \
    securitycenter.googleapis.com \
    --quiet
echo "✅ GCP APIs enabled"

# ── Step 5: Terraform init ───────────────────────────────────────────
echo ""
echo "Step 3/4: Initializing Terraform..."
if terraform init -input=false; then
    echo "✅ Terraform initialized"
else
    echo "❌ Terraform init failed"
    exit 1
fi

# ── Step 6: Terraform apply ──────────────────────────────────────────
echo ""
echo "Step 4/4: Deploying integration..."
if terraform apply -auto-approve -input=false; then
    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "✅ VectorPlane GCP integration deployed successfully!"
    echo ""
    echo "   • Workload Identity Federation active"
    echo "   • Zero service account keys exchanged"
    echo "   • Check your VectorPlane dashboard for findings"
    echo ""
    echo "   To remove: terraform destroy"
    echo "════════════════════════════════════════════════════════"
else
    echo "❌ Deployment failed. Check errors above."
    exit 1
fi
