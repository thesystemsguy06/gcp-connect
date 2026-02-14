#!/bin/bash
# VectorPlane GCP Integration - One-Command Deploy
# Implements the "Phoning Home" pattern: user enters a pairing code from
# the VectorPlane dashboard, deploy.sh calls the backend to get Terraform variables.

set -e

echo ""
echo "🚀 VectorPlane GCP Integration"
echo "════════════════════════════════════════════════════════"
echo ""

# ── Step 1: Get pairing code from user ────────────────────────────────
# The VectorPlane dashboard displays a short pairing code (e.g., VP-A3X7)
# when the user initiates GCP onboarding.

read -p "Enter your VectorPlane pairing code: " PAIRING_CODE

# Normalize: uppercase, trim whitespace
PAIRING_CODE=$(echo "$PAIRING_CODE" | tr '[:lower:]' '[:upper:]' | xargs)

if [ -z "$PAIRING_CODE" ]; then
    echo "❌ No pairing code entered."
    echo "   Find the code in your VectorPlane dashboard under GCP onboarding."
    exit 1
fi

echo ""

# ── Step 2: Phone home for Terraform configuration ───────────────────
echo "Step 1/4: Retrieving configuration from VectorPlane..."

# API base URL - try environment variable first, fall back to production
API_BASE="${VP_API_BASE:-https://api.vectorplane.io}"

CONTEXT_URL="${API_BASE}/api/v1/onboarding/gcp/session-context?code=${PAIRING_CODE}"

HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" "$CONTEXT_URL")
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n1)
BODY=$(echo "$HTTP_RESPONSE" | head -n -1)

if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ Failed to retrieve configuration (HTTP $HTTP_CODE)"
    case $HTTP_CODE in
        400) echo "   Missing pairing code." ;;
        404) echo "   Invalid pairing code or session expired." ;;
        410) echo "   Session is no longer active." ;;
        *) echo "   Response: $BODY" ;;
    esac
    echo ""
    echo "   Please check the code in your VectorPlane dashboard."
    echo "   If the session expired, restart onboarding."
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
