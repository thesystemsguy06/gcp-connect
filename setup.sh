#!/bin/bash
# VectorPlane GCP Onboarding - Enterprise Setup
# This script pulls variables from VectorPlane API and generates terraform.tfvars.json

set -e

echo "🔧 VectorPlane GCP Onboarding Setup"
echo "==================================="

# Extract token and API base from URL fragment
# URL format: #vp_token=<token>&vp_api_base=<base_url>
if [ -n "$1" ]; then
    # Token passed as argument (for testing)
    VectorPlane_TOKEN="$1"
    VectorPlane_API_BASE="$2"
else
    # Try to get from cloudshell metadata
    FRAGMENT=$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/cloudshell_url_fragment" 2>/dev/null || echo "")

    if [ -z "$FRAGMENT" ]; then
        echo "❌ No VectorPlane context found"
        echo ""
        echo "This script must be run from Google Cloud Shell opened via VectorPlane."
        echo "Please return to VectorPlane and click 'Open Cloud Shell' to continue."
        exit 1
    fi

    # Parse fragment: vp_token=<token>&vp_api_base=<base_url>
    VectorPlane_TOKEN=$(echo "$FRAGMENT" | sed -n 's/.*vp_token=\([^&]*\).*/\1/p')
    VectorPlane_API_BASE=$(echo "$FRAGMENT" | sed -n 's/.*vp_api_base=\([^&]*\).*/\1/p')
fi

if [ -z "$VectorPlane_TOKEN" ] || [ -z "$VectorPlane_API_BASE" ]; then
    echo "❌ Invalid VectorPlane context"
    echo "Missing token or API base URL. Please restart from VectorPlane."
    exit 1
fi

# Extract session ID from token for API call
echo "🔍 Extracting session information..."
SESSION_ID=$(echo "$VectorPlane_TOKEN" | base64 -d 2>/dev/null | cut -d: -f1 || echo "")

if [ -z "$SESSION_ID" ]; then
    echo "❌ Invalid token format"
    echo "Unable to extract session ID from token."
    exit 1
fi

echo "📋 Session ID: $SESSION_ID"
echo "🌐 API Base: $VectorPlane_API_BASE"
echo ""

# Call VectorPlane API to get Terraform variables
echo "📡 Retrieving configuration from VectorPlane..."
API_URL="${VectorPlane_API_BASE}/api/v1/onboarding/gcp/context/${SESSION_ID}"

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $VectorPlane_TOKEN" \
    -H "Accept: application/json" \
    "$API_URL")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ API call failed (HTTP $HTTP_CODE)"
    echo ""
    case $HTTP_CODE in
        401)
            echo "Authentication failed. Your session token may have expired."
            echo "Please return to VectorPlane and start a new onboarding session."
            ;;
        403)
            echo "Access denied. Token may not match the session."
            ;;
        404)
            echo "Session not found. It may have expired."
            echo "Please return to VectorPlane and start a new onboarding session."
            ;;
        410)
            echo "Session is no longer pending or has expired."
            echo "Please return to VectorPlane and start a new onboarding session."
            ;;
        *)
            echo "Unexpected error occurred."
            echo "Response: $BODY"
            ;;
    esac
    echo ""
    echo "🔗 Return to VectorPlane to restart the onboarding process."
    exit 1
fi

# Parse JSON response and generate terraform.tfvars.json
echo "✅ Configuration retrieved successfully"
echo "📝 Generating terraform.tfvars.json..."

python3 << 'EOF'
import json
import sys
import os

try:
    # Parse the API response
    response_text = sys.stdin.read()
    response = json.loads(response_text)

    terraform_vars = response.get('terraform_vars', {})
    session_expires_at = response.get('session_expires_at', '')

    if not terraform_vars:
        print("❌ No Terraform variables received from API")
        sys.exit(1)

    # Generate terraform.tfvars.json
    with open('terraform.tfvars.json', 'w') as f:
        json.dump(terraform_vars, f, indent=2)

    print("✅ terraform.tfvars.json created successfully")
    print("")
    print("📋 Configuration Summary:")
    print(f"   Session ID: {terraform_vars.get('external_id', 'N/A')}")
    print(f"   Scope: {terraform_vars.get('onboarding_scope', 'N/A')}")
    print(f"   AWS Account: {terraform_vars.get('vectorplane_aws_account_id', 'N/A')}")
    print(f"   Session Expires: {session_expires_at}")

    # Show scope-specific information
    scope = terraform_vars.get('onboarding_scope', 'PROJECT')
    if scope == 'ORGANIZATION':
        org_id = terraform_vars.get('gcp_scope_id', 'N/A')
        print(f"   Organization ID: {org_id}")
    elif scope == 'FOLDER':
        folder_id = terraform_vars.get('gcp_scope_id', 'N/A')
        print(f"   Folder ID: {folder_id}")
    else:
        print("   Project: Auto-detected from Cloud Shell")

except json.JSONDecodeError as e:
    print(f"❌ Invalid JSON response from API: {e}")
    print(f"Response: {response_text[:200]}...")
    sys.exit(1)
except Exception as e:
    print(f"❌ Error processing API response: {e}")
    sys.exit(1)
EOF << END_INPUT
$BODY
END_INPUT

if [ $? -ne 0 ]; then
    echo "❌ Failed to process API response"
    exit 1
fi

echo ""
echo "🎉 Setup complete! Ready for Terraform deployment."
echo ""
echo "Next steps:"
echo "  terraform init"
echo "  terraform plan"
echo "  terraform apply"
echo ""
echo "Note: Your session expires at $(echo "$BODY" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('session_expires_at', 'unknown'))" 2>/dev/null || echo "unknown")"
