#!/bin/bash
# VectorPlane GCP Integration — Device Flow Onboarding (RFC 8628)
# Exchanges a pairing code for the full Terraform configuration,
# then deploys Workload Identity Federation via Terraform.

set -e

# Production default; override with VP_API_BASE for dev/testing
API_BASE="${VP_API_BASE:-https://api.vectorplane.io}"
EXCHANGE_URL="${API_BASE}/api/v1/onboarding/gcp/pairing-exchange"

echo ""
echo "------------------------------------------------"
echo "  VectorPlane GCP Onboarding"
echo "------------------------------------------------"
echo ""

# ── Step 1: Pairing Code ─────────────────────────────────────────────
read -p "Enter pairing code from dashboard (e.g. VP-XXXX): " USER_CODE
USER_CODE=$(echo "$USER_CODE" | tr '[:lower:]' '[:upper:]' | xargs)

if [ -z "$USER_CODE" ]; then
    echo "Error: No pairing code entered."
    echo "Find the code in your VectorPlane dashboard."
    exit 1
fi

# ── Step 2: Exchange code for Terraform configuration ─────────────────
echo ""
echo "[1/4] Authenticating with VectorPlane..."

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$EXCHANGE_URL" \
    -H "Content-Type: application/json" \
    -d "{\"pairing_code\": \"$USER_CODE\"}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
    ERROR_MSG=$(echo "$BODY" | jq -r '.detail // "Unknown error"' 2>/dev/null || echo "$BODY")
    echo "Error: $ERROR_MSG"
    echo ""
    echo "Check the code in your VectorPlane dashboard."
    echo "If the session expired, restart onboarding."
    exit 1
fi

# Write the full payload as terraform.tfvars.json
echo "$BODY" > terraform.tfvars.json

# Validate JSON
if ! jq empty terraform.tfvars.json 2>/dev/null; then
    echo "Error: Invalid configuration received."
    exit 1
fi

PROJECT_ID=$(jq -r '.project_id' terraform.tfvars.json)
echo "Identity verified. Project: $PROJECT_ID"

# ── Step 3: Align GCP project + enable APIs ───────────────────────────
echo ""
echo "[2/4] Preparing GCP project..."

CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
    gcloud config set project "$PROJECT_ID" --quiet
fi

gcloud services enable \
    iam.googleapis.com \
    cloudresourcemanager.googleapis.com \
    sts.googleapis.com \
    iamcredentials.googleapis.com \
    securitycenter.googleapis.com \
    --quiet
echo "GCP APIs enabled."

# ── Step 4: Terraform init ────────────────────────────────────────────
echo ""
echo "[3/4] Initializing Terraform..."
if ! terraform init -input=false; then
    echo "Error: Terraform init failed."
    exit 1
fi

# ── Step 5: Terraform apply ───────────────────────────────────────────
echo ""
echo "[4/4] Deploying integration..."
if terraform apply -auto-approve -input=false; then
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
    echo "Error: Deployment failed. Check errors above."
    exit 1
fi
