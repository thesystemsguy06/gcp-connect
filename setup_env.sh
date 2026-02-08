#!/bin/bash
# VectorPlane GCP Onboarding - CTO Specification Implementation
# This script implements the exact "Context-Sync" pattern specified by the CTO

set -e

echo "🔧 VectorPlane GCP Onboarding Setup"
echo "==================================="
echo ""

# Check for required environment variables (CTO specification)
if [ -z "$VP_TOKEN" ] || [ -z "$SESSION_ID" ] || [ -z "$VP_API_BASE" ]; then
    echo "❌ Missing VectorPlane session information"
    echo ""
    echo "This script must be run from Google Cloud Shell opened via VectorPlane."
    echo "Required environment variables:"
    echo "  VP_TOKEN     - VectorPlane bearer token"
    echo "  SESSION_ID   - VectorPlane session identifier"
    echo "  VP_API_BASE  - VectorPlane API base URL"
    echo ""
    echo "Please return to VectorPlane and click 'Open Cloud Shell' to continue."
    exit 1
fi

echo "📋 Session ID: $SESSION_ID"
echo "🌐 API Base: $VP_API_BASE"
echo ""

# The "Magic" Pull (CTO specification)
echo "📡 Pulling configuration from VectorPlane API..."
API_URL="${VP_API_BASE}/api/v1/onboarding/gcp/context/${SESSION_ID}"

# Exact curl pattern from CTO specification
curl -H "Authorization: Bearer $VP_TOKEN" \
     "$API_URL" \
     -o terraform.tfvars.json

# Check if the pull was successful
if [ $? -ne 0 ] || [ ! -f "terraform.tfvars.json" ]; then
    echo "❌ Failed to retrieve configuration from VectorPlane API"
    echo ""
    echo "Possible causes:"
    echo "- Session expired (15-minute limit)"
    echo "- VectorPlane API unreachable"
    echo "- Invalid bearer token"
    echo ""
    echo "🔗 Return to VectorPlane to restart the onboarding process."
    exit 1
fi

# Validate JSON format
if ! python3 -m json.tool terraform.tfvars.json > /dev/null 2>&1; then
    echo "❌ Invalid JSON received from API"
    echo "File contents:"
    cat terraform.tfvars.json
    exit 1
fi

echo "✅ Configuration retrieved successfully"
echo ""

# Show the configuration for verification (CTO DoD requirement)
echo "📋 Terraform Variables:"
echo "----------------------------------------"
cat terraform.tfvars.json | python3 -m json.tool 2>/dev/null || cat terraform.tfvars.json
echo "----------------------------------------"
echo ""

echo "🎉 Setup complete! Variables configured successfully."
echo ""
echo "Next steps:"
echo "  terraform init"
echo "  terraform plan"
echo "  terraform apply"
echo ""
echo "✅ Zero Prompts: terraform apply will proceed without asking for input"
