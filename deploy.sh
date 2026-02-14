#!/bin/bash
# VectorPlane GCP Integration - One-Command Deploy
# Usage: ./deploy.sh

set -e

echo ""
echo "🚀 VectorPlane GCP Integration"
echo "════════════════════════════════════════════════════════"
echo ""

# Step 1: Sync configuration from VectorPlane API
echo "Step 1/3: Syncing configuration..."
if ./setup_env.sh; then
    echo "✅ Configuration synced"
else
    echo "❌ Configuration sync failed. Please restart from VectorPlane."
    exit 1
fi

echo ""

# Step 2: Initialize Terraform
echo "Step 2/3: Initializing Terraform..."
if terraform init -input=false; then
    echo "✅ Terraform initialized"
else
    echo "❌ Terraform init failed"
    exit 1
fi

echo ""

# Step 3: Deploy
echo "Step 3/3: Deploying integration..."
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
