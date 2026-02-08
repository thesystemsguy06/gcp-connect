# VectorPlane GCP Onboarding

Welcome to VectorPlane GCP integration! This setup creates secure access to your GCP project using Workload Identity Federation (WIF).

## 🔐 Security Overview

VectorPlane uses **Workload Identity Federation** for secure, keyless authentication:

- ✅ **No secrets exchanged** - VectorPlane never receives or stores GCP service account keys
- ✅ **Short-lived tokens** - Access tokens expire after 1 hour, setup tokens expire after 15 minutes
- ✅ **Zero-trust authentication** - Cryptographic proof of VectorPlane's AWS identity
- ✅ **Customer-controlled** - You can revoke access instantly by deleting resources
- ✅ **API-based configuration** - Secure variable retrieval without manual copy-paste

## 🚀 Quick Start

### Step 1: Set up environment

```bash
# Configure Terraform variables from VectorPlane API
./setup_env.sh
```

This script:
- Authenticates with VectorPlane using your session token
- Retrieves Terraform variables via secure API
- Generates `terraform.tfvars.json` automatically
- Validates session and provides clear error messages

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

### Setup Script Errors

**"No VectorPlane context found"**
- **Cause**: Cloud Shell wasn't opened via VectorPlane link
- **Solution**: Return to VectorPlane and click "Open Cloud Shell" again

**"Authentication failed" or "Session expired"**
- **Cause**: Setup session expired (15-minute limit)
- **Solution**: Return to VectorPlane and start a new onboarding session

**"Invalid token format"**
- **Cause**: Corrupted session data or browser issue
- **Solution**: Clear browser cache and restart from VectorPlane

### API Connection Issues

**"API call failed" with network errors**
- **Cause**: Cloud Shell cannot reach VectorPlane API
- **Solution**: Check if VectorPlane instance is running and accessible

**HTTP 403 "Access denied"**
- **Cause**: Token doesn't match session or session corrupted
- **Solution**: Start fresh onboarding session from VectorPlane

### Terraform Deployment Issues

**Variable validation errors**
- **Cause**: `terraform.tfvars.json` missing or corrupted
- **Solution**: Run `./setup.sh` again to regenerate variables

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

1. Check error messages from `./setup.sh` - they provide specific guidance
2. Verify session hasn't expired (15-minute limit from VectorPlane)
3. Review Terraform plan output for permission issues
4. Contact VectorPlane support with the session ID from error messages

## 🔧 Advanced Usage

### Manual Variable Inspection

```bash
# View generated Terraform variables
cat terraform.tfvars.json

# Check session expiration
./setup_env.sh  # Shows expiration time in output
```

### Testing Connectivity

```bash
# Test API connectivity (requires valid token)
curl -H "Authorization: Bearer <your-token>" \
  "https://your-vectorplane-instance/api/v1/onboarding/gcp/context/<session-id>"
```

---

**Ready to proceed?** Run `./setup_env.sh` to get started!
