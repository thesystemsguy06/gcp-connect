#!/bin/bash
# VectorPlane GCP Onboarding - Final CTO Implementation
# Implements the exact "Context-Sync" pattern with CTO's final specifications

set -e # Exit immediately if a command fails

# Ensure workspace is fully ready before proceeding
if [ ! -f "main.tf" ] || [ ! -f "variables.tf" ]; then
    echo "⏳ Waiting for workspace to be fully ready..."
    while [ ! -f "main.tf" ] || [ ! -f "variables.tf" ]; do
        sleep 1
    done
    echo "✅ Workspace ready"
fi

echo "🛰️  Syncing VectorPlane configuration..."

# 1. Verify the token exists (CTO specification)
if [ -z "$VP_TOKEN" ]; then
    echo "❌ Error: VP_TOKEN not found in environment."
    echo "Please restart onboarding from the VectorPlane dashboard."
    exit 1
fi

# 2. Pull the context from the Backend (CTO's exact pattern)
# Note: We use -f to fail on 4xx/5xx errors, -s for silent mode
curl -f -s -H "Authorization: Bearer $VP_TOKEN" \
     "${VP_API_BASE}/api/v1/onboarding/gcp/context" \
     -o terraform.tfvars.json

# 3. Verify the download was successful
if [ ! -f "terraform.tfvars.json" ]; then
    echo "❌ Failed to retrieve configuration from VectorPlane API"
    echo "Please restart onboarding from the VectorPlane dashboard."
    exit 1
fi

# 4. Validate JSON format
if ! python3 -m json.tool terraform.tfvars.json > /dev/null 2>&1; then
    echo "❌ Invalid JSON received from API"
    echo "File contents:"
    cat terraform.tfvars.json
    exit 1
fi

echo "✅ Configuration synced successfully."

# 5. Show the configuration for verification (enterprise transparency)
echo ""
echo "📋 Terraform Variables Loaded:"
echo "----------------------------------------"
cat terraform.tfvars.json | python3 -m json.tool 2>/dev/null || cat terraform.tfvars.json
echo "----------------------------------------"
echo ""

echo "🚀 Next steps: terraform init && terraform apply"
echo ""
echo "✅ Zero Prompts: Terraform will proceed without asking for input"
