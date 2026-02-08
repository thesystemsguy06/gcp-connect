# VectorPlane GCP Onboarding

Welcome to VectorPlane GCP integration! This setup creates secure access to your GCP project using Workload Identity Federation (WIF).

## 🔐 Security Overview

VectorPlane uses **Workload Identity Federation** for secure, keyless authentication:

- ✅ **No secrets exchanged** - VectorPlane never receives or stores GCP service account keys
- ✅ **Short-lived tokens** - Access tokens expire after 1 hour, setup sessions expire after 15 minutes
- ✅ **Zero-trust authentication** - Cryptographic proof of VectorPlane's AWS identity
- ✅ **Customer-controlled** - You can revoke access instantly by deleting resources
- ✅ **Enterprise-grade sync** - Secure bearer token authentication with API-based configuration pull

## 🚀 Quick Start

### Step 1: Sync configuration

```bash
# Sync Terraform variables from VectorPlane API
./setup_env.sh
```

This script automatically:
- Authenticates with VectorPlane using your bearer token
- Pulls configuration via secure API endpoint
- Generates `terraform.tfvars.json` for Terraform auto-loading
- Validates session and provides enterprise-grade error messages

### Step 2: Initialize Terraform

```bash
terraform init
```

### Step 3: Review deployment plan

```bash
terraform plan
```

This shows you:
- Workload Identity Pool and Provider
- Service Account with appropriate permissions
- IAM bindings for secure access

### Step 4: Deploy resources

```bash
terraform apply
```

This will:
1. Create the GCP resources
2. Send a secure webhook to VectorPlane
3. Complete the integration automatically

## 🏗️ What This Creates

| Resource | Purpose |
|----------|---------|
| **Workload Identity Pool** | Trust boundary for external identity providers |
| **WIF Provider** | Trusts VectorPlane's AWS account (101460827772) |
| **Service Account** | Identity for VectorPlane to access your GCP resources |
| **IAM Bindings** | Permissions for Security Command Center and asset discovery |

## 🔍 Permissions Granted

The service account will have these permissions:

### PROJECT Scope
- `roles/securitycenter.findingsViewer` - Read security findings
- `roles/browser` - View project resources and structure
- `roles/storage.objectViewer` - Read Terraform state files

### FOLDER Scope
- Same as PROJECT scope, applied at folder level
- Includes all projects within the folder

### ORGANIZATION Scope
- Same as PROJECT scope, applied at organization level
- Includes all projects and folders in your organization

## 🛠️ Troubleshooting

### Setup Script Issues

**"VP_TOKEN not found in environment"**
- **Cause**: Cloud Shell wasn't opened via VectorPlane link
- **Solution**: Return to VectorPlane and click "Open Cloud Shell" again

**"Failed to retrieve configuration"**
- **Cause**: Setup session expired (15-minute limit) or API unreachable
- **Solution**: Return to VectorPlane and start a new onboarding session

**Curl fails with 4xx/5xx errors**
- **Cause**: Invalid bearer token or session expired
- **Solution**: Restart onboarding from VectorPlane dashboard

### Terraform Deployment Issues

**Variable prompts during terraform apply**
- **Cause**: `terraform.tfvars.json` not created or corrupted
- **Solution**: Run `./setup_env.sh` again to regenerate variables

**Webhook timeout during apply**
- **Cause**: VectorPlane API unreachable or session expired
- **Solutions**:
  1. Verify VectorPlane instance is running
  2. Check session hasn't expired (15-minute limit)
  3. Restart onboarding if needed

## 🔄 Clean Up

To remove all created resources:

```bash
terraform destroy
```

This deletes the Workload Identity Pool, Service Account, and all IAM bindings.

## 📞 Support

If you encounter issues:

1. Check error messages from `./setup_env.sh` - they provide specific guidance
2. Verify session hasn't expired (15-minute limit from VectorPlane)
3. Review Terraform plan output for permission issues
4. Contact VectorPlane support with the session ID from error messages

## 🔧 Advanced Usage

### Manual Variable Inspection

```bash
# View generated Terraform variables
cat terraform.tfvars.json

# Re-run sync if needed
./setup_env.sh
```

### Verify Configuration Before Apply

The setup script shows the synced configuration:

```
📋 Terraform Variables Loaded:
----------------------------------------
{
  "external_id": "sess_abc123...",
  "webhook_secret": "secret...",
  "vectorplane_callback_url": "https://...",
  "vectorplane_account_id": "101460827772",
  "onboarding_scope": "PROJECT"
}
----------------------------------------
```

---

**Ready to proceed?** Run `./setup_env.sh` to get started!
