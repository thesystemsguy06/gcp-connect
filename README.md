# VectorPlane GCP Onboarding

This Terraform configuration sets up the necessary Google Cloud Platform (GCP) resources to enable VectorPlane security scanning of your GCP environment.

## 🔐 Security Overview

VectorPlane uses **Workload Identity Federation (WIF)** for secure, keyless authentication:

- ✅ **No secrets exchanged** - VectorPlane never receives or stores GCP service account keys
- ✅ **Short-lived tokens** - Access tokens expire after 1 hour
- ✅ **Zero-trust authentication** - Cryptographic proof of VectorPlane's AWS identity
- ✅ **Customer-controlled** - You can revoke access instantly by deleting resources

## 🏗️ What This Creates

### Core Resources

| Resource | Purpose |
|----------|---------|
| **Workload Identity Pool** | Trust boundary for external identity providers |
| **AWS Provider** | Validates VectorPlane's AWS identity and role |
| **Service Account** | Identity that VectorPlane impersonates for API calls |
| **IAM Bindings** | Permissions for Security Command Center access |

### Permissions Granted

The service account receives these permissions based on your selected scope:

#### PROJECT Scope
- `roles/securitycenter.findingsViewer` (project-level)
- `roles/storage.objectViewer` (for Terraform state access)

#### FOLDER Scope
- `roles/securitycenter.findingsViewer` (folder-level, inherited by all projects)
- `roles/resourcemanager.folderViewer` (to discover projects in folder)
- `roles/browser` (for project listing)
- `roles/storage.objectViewer`

#### ORGANIZATION Scope
- `roles/securitycenter.findingsViewer` (org-level, inherited by all projects)
- `roles/resourcemanager.organizationViewer` (to discover org structure)
- `roles/resourcemanager.folderViewer` (to list all folders)
- `roles/browser` (for project listing)
- `roles/storage.objectViewer`

## 🚀 Getting Started

### Prerequisites

1. **Enable Required APIs**
   ```bash
   gcloud services enable iamcredentials.googleapis.com
   gcloud services enable iam.googleapis.com
   gcloud services enable cloudresourcemanager.googleapis.com
   gcloud services enable securitycenter.googleapis.com
   ```

2. **Required Permissions**

   You need these IAM roles to run this Terraform:

   #### For PROJECT scope:
   - `roles/iam.workloadIdentityPoolAdmin`
   - `roles/iam.serviceAccountAdmin`
   - `roles/security.admin` (for Security Center permissions)
   - `roles/storage.admin` (for Terraform state bucket permissions)

   #### For FOLDER scope (additional):
   - `roles/resourcemanager.folderIamAdmin` (on target folder)

   #### For ORGANIZATION scope (additional):
   - `roles/resourcemanager.organizationAdmin` (on organization)

### 📋 Step-by-Step Instructions

1. **Review the Configuration**

   Examine the `main.tf` file to understand what resources will be created.

2. **Initialize Terraform**
   ```bash
   terraform init
   ```

3. **Review the Plan**
   ```bash
   terraform plan
   ```

4. **Apply the Configuration**
   ```bash
   terraform apply
   ```

5. **Confirm Completion**

   After successful deployment, you'll see:
   - ✅ Resource creation summary
   - 🎉 "VectorPlane GCP onboarding completed" message
   - 📊 VectorPlane automatically starts scanning your environment

## 🔧 Configuration Variables

Most variables are automatically set by VectorPlane's Cloud Shell deep link. You can override them if needed:

### Required (Auto-configured)
- `external_id` - Session ID from VectorPlane (e.g., `sess_abc123xyz`)
- `webhook_secret` - HMAC secret for secure webhook verification
- `vectorplane_callback_url` - VectorPlane's webhook endpoint

### Optional Customization
- `service_account_id` - Custom service account name (default: `vectorplane-security`)
- `wif_pool_id` - Custom WIF pool name (default: `vectorplane-security-pool`)
- `project_id` - Target project (defaults to current project)

### Scope Configuration
- `onboarding_scope` - Set to `PROJECT`, `FOLDER`, or `ORGANIZATION`
- `gcp_scope_id` - Required for FOLDER scope (format: `folders/123456789`)
- `organization_domain` - Required for ORGANIZATION scope (e.g., `example.com`)

## 🔍 Verification

After deployment, verify the setup:

```bash
# Check Workload Identity Pool
gcloud iam workload-identity-pools describe vectorplane-security-pool \
  --location=global --project=$PROJECT_ID

# Check Service Account
gcloud iam service-accounts describe \
  vectorplane-security@$PROJECT_ID.iam.gserviceaccount.com

# Check IAM bindings
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten='bindings[].members' \
  --filter='bindings.members:serviceAccount:vectorplane-security@$PROJECT_ID.iam.gserviceaccount.com'
```

## 🛡️ Security Best Practices

### Regular Security Review

1. **Monitor Access Logs**
   ```bash
   gcloud logging read 'protoPayload.authenticationInfo.principalEmail:"vectorplane-security@*.iam.gserviceaccount.com"' --limit=50 --format=json
   ```

2. **Review IAM Bindings Periodically**
   ```bash
   gcloud projects get-iam-policy $PROJECT_ID --flatten='bindings[].members' | grep vectorplane
   ```

### Incident Response

If you need to **immediately revoke VectorPlane access**:

```bash
# Option 1: Delete the entire WIF pool (recommended)
gcloud iam workload-identity-pools delete vectorplane-security-pool \
  --location=global --project=$PROJECT_ID

# Option 2: Delete just the service account
gcloud iam service-accounts delete \
  vectorplane-security@$PROJECT_ID.iam.gserviceaccount.com --project=$PROJECT_ID
```

## 🗂️ Scope Details

### PROJECT Scope
- **Use Case**: Single GCP project
- **Access**: Security findings and assets within the project
- **Resource Discovery**: Limited to the connected project

### FOLDER Scope
- **Use Case**: All projects within a GCP folder (including subfolders)
- **Access**: Security findings across all projects in the folder hierarchy
- **Resource Discovery**: VectorPlane discovers new projects added to the folder
- **Scaling**: Uses "fan-out" pattern for large folder hierarchies

### ORGANIZATION Scope
- **Use Case**: Entire GCP organization
- **Access**: Security findings across all projects, folders, and organizational units
- **Resource Discovery**: VectorPlane discovers all projects organization-wide
- **Scaling**: Uses hierarchical "fan-out" pattern optimized for enterprise scale

## 🆘 Troubleshooting

### Common Issues

1. **"Permission denied" during terraform apply**

   **Cause**: Insufficient IAM permissions

   **Solution**: Ensure you have the required roles listed in Prerequisites

2. **"API not enabled" errors**

   **Cause**: Required GCP APIs are disabled

   **Solution**: Enable APIs using the commands in Prerequisites

3. **Webhook notification fails**

   **Cause**: Network connectivity or incorrect callback URL

   **Solution**: Check Cloud Shell network access and VectorPlane status

4. **Security Command Center access denied**

   **Cause**: SCC API not enabled or insufficient permissions

   **Solution**:
   ```bash
   gcloud services enable securitycenter.googleapis.com
   ```

### Getting Help

- **VectorPlane Support**: Contact support through the VectorPlane dashboard
- **GCP Documentation**: [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- **Terraform Provider**: [Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## 📚 Additional Resources

- [VectorPlane GCP Integration Documentation](https://docs.vectorplane.io/integrations/gcp)
- [GCP Security Command Center](https://cloud.google.com/security-command-center)
- [Workload Identity Federation Best Practices](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)
- [GCP IAM Troubleshooting](https://cloud.google.com/iam/docs/troubleshooting-access)