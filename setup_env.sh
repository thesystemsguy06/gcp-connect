#!/bin/bash
# VectorPlane GCP Onboarding - Complete Blueprint Implementation
# Pull-based configuration with project validation

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

# 1. Verify the token exists (Blueprint requirement)
if [ -z "$VP_TOKEN" ]; then
    echo "❌ Error: VP_TOKEN not found in environment."
    echo "Please restart onboarding from the VectorPlane dashboard."
    exit 1
fi

# 2. Pull configuration from Backend Context Endpoint (Blueprint specification)
echo "📡 Pulling configuration from VectorPlane API..."
API_URL="${VP_API_BASE}/api/v1/onboarding/gcp/context"

# Use curl to call Backend Context Endpoint
RESPONSE=$(curl -f -s -H "Authorization: Bearer $VP_TOKEN" \
     "$API_URL" \
     -o terraform.tfvars.json \
     && echo "success" || echo "failed")

# 3. Verify the download was successful
if [ "$RESPONSE" != "success" ] || [ ! -f "terraform.tfvars.json" ]; then
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

# 5. Project Validation (Blueprint requirement)
EXPECTED_PROJECT=$(python3 -c "import json; print(json.load(open('terraform.tfvars.json'))['project_id'])" 2>/dev/null || echo "")
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")

if [ -n "$EXPECTED_PROJECT" ]; then
    echo "📋 Expected Project: $EXPECTED_PROJECT"
    echo "🔍 Current Project: $CURRENT_PROJECT"

    if [ "$CURRENT_PROJECT" != "$EXPECTED_PROJECT" ]; then
        echo "🔄 Aligning shell context to selected project..."
        gcloud config set project "$EXPECTED_PROJECT"
        echo "✅ Project context aligned"
    else
        echo "✅ Project context already correct"
    fi
else
    echo "⚠️  No project validation available (project_id missing from API response)"
fi

echo "✅ Configuration synced successfully."

# 6. Enable required GCP APIs
echo "🔧 Enabling required GCP APIs..."
gcloud services enable \
    iam.googleapis.com \
    cloudresourcemanager.googleapis.com \
    sts.googleapis.com \
    iamcredentials.googleapis.com \
    securitycenter.googleapis.com \
    --quiet
echo "✅ GCP APIs enabled"

# 7. Show the configuration for verification (enterprise transparency)
echo ""
echo "📋 Terraform Variables Loaded:"
echo "----------------------------------------"
cat terraform.tfvars.json | python3 -m json.tool 2>/dev/null || cat terraform.tfvars.json
echo "----------------------------------------"
echo ""

echo "🚀 Next steps: terraform init && terraform apply"
echo ""
echo "✅ Zero Prompts: Terraform will proceed without asking for input"
