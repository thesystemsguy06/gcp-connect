# VectorPlane GCP Onboarding Setup

Welcome to VectorPlane GCP integration! This setup will create secure access to your GCP project using Workload Identity Federation (WIF).

## 🔐 Security Overview

VectorPlane uses **Workload Identity Federation** for secure, keyless authentication:

- ✅ **No secrets exchanged** - VectorPlane never receives or stores GCP service account keys
- ✅ **Short-lived tokens** - Access tokens expire after 1 hour
- ✅ **Zero-trust authentication** - Cryptographic proof of VectorPlane's AWS identity
- ✅ **Customer-controlled** - You can revoke access instantly by deleting resources

## 🚀 Quick Start

### Step 1: Set up environment variables

```bash
# Load VectorPlane session variables
./setup_env.sh
```

### Step 2: Initialize Terraform

```bash
terraform init
```

### Step 3: Review what will be created

```bash
terraform plan
```

This will show you:
- Workload Identity Pool and Provider
- Service Account with appropriate permissions
- IAM bindings for secure access

### Step 4: Deploy resources

```bash
terraform apply
```

This will:
1. Create the GCP resources
2. Send a webhook to VectorPlane to complete onboarding
3. Display a success message when complete

## 🏗️ What This Creates

| Resource | Purpose |
|----------|---------|
| **Workload Identity Pool** | Trust boundary for external identity providers |
| **WIF Provider** | Trusts VectorPlane's AWS account (101460827772) |
| **Service Account** | Identity for VectorPlane to access your GCP resources |
| **IAM Bindings** | Permissions for Security Command Center and asset discovery |

## 🔍 Permissions Granted

The service account will have these permissions in your GCP project:

- `roles/securitycenter.findingsViewer` - Read security findings
- `roles/browser` - View project resources and structure
- `roles/storage.objectViewer` - Read Terraform state files (for state scanning)

For FOLDER or ORGANIZATION scope, additional permissions are granted at the appropriate level.

## 🛠️ Troubleshooting

### "No context found" Error

If you see this error, it means the Cloud Shell session wasn't opened via the VectorPlane link:

```bash
# Check if context is available
curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/cloudshell_context"
```

**Solution**: Return to VectorPlane and click "Open Cloud Shell" again.

### Terraform Validation Errors

If you see validation errors about missing variables:

```bash
# Verify environment variables are set
env | grep TF_VAR
```

**Solution**: Run `./setup_env.sh` again to load the variables.

### Webhook Failures

If the webhook fails after `terraform apply`:

1. **Check network connectivity**: Cloud Shell should be able to reach your VectorPlane instance
2. **Verify session hasn't expired**: Sessions expire after 15 minutes
3. **Check VectorPlane logs**: The webhook endpoint should receive and process the callback

## 🔄 Clean Up

To remove all created resources:

```bash
terraform destroy
```

This will delete the Workload Identity Pool, Service Account, and all IAM bindings.

## 📞 Support

If you encounter any issues:

1. Check the troubleshooting section above
2. Review the Terraform plan output for any obvious issues
3. Contact VectorPlane support with the session ID from the error messages

---

**Ready to proceed?** Run `./setup_env.sh` to get started!
