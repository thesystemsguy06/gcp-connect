# 🚀 VectorPlane GCP Setup Guide

Welcome to the VectorPlane GCP onboarding process! This guide will walk you through connecting your GCP environment to VectorPlane for automated security scanning.

## 📋 Overview

You're about to create the following resources in your GCP environment:

- **Workload Identity Pool** - Secure authentication boundary
- **AWS Provider** - Validates VectorPlane's identity
- **Service Account** - Identity for VectorPlane to access your resources
- **IAM Permissions** - Security Command Center access

**🔐 Security Note**: This process uses Workload Identity Federation - no long-lived keys or secrets are exchanged!

## ⚡ Quick Start (2 minutes)

### Step 1: Review Configuration *(30 seconds)*

The environment variables have been pre-configured for you:

```bash
echo "Session ID: $TF_VAR_external_id"
echo "Scope: $TF_VAR_onboarding_scope"
echo "Project: $(gcloud config get-value project)"
```

### Step 2: Initialize Terraform *(30 seconds)*

```bash
terraform init
```

### Step 3: Review What Will Be Created *(30 seconds)*

```bash
terraform plan
```

### Step 4: Deploy *(30 seconds)*

```bash
terraform apply -auto-approve
```

**That's it!** 🎉 VectorPlane will automatically start scanning your GCP environment.

---

## 🔍 Detailed Steps

### Step 1: Verify Prerequisites

Check that required APIs are enabled:

```bash
# List currently enabled APIs
gcloud services list --enabled --filter="name:( \
  iamcredentials.googleapis.com OR \
  iam.googleapis.com OR \
  cloudresourcemanager.googleapis.com OR \
  securitycenter.googleapis.com \
)"
```

If any APIs are missing, enable them:

```bash
gcloud services enable \
  iamcredentials.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  securitycenter.googleapis.com
```

### Step 2: Check Your Permissions

Verify you have the required roles:

```bash
# Check your current IAM roles
gcloud projects get-iam-policy $(gcloud config get-value project) \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:$(gcloud config get-value account)"
```

**Required roles:**
- `roles/iam.workloadIdentityPoolAdmin`
- `roles/iam.serviceAccountAdmin`
- `roles/security.admin`

### Step 3: Review Configuration Variables

Check the auto-configured variables:

```bash
echo "=== VectorPlane Configuration ==="
echo "Session ID: $TF_VAR_external_id"
echo "Onboarding Scope: $TF_VAR_onboarding_scope"
echo "Project ID: $(gcloud config get-value project 2>/dev/null || echo 'Default project')"
echo "VectorPlane AWS Account: $TF_VAR_vectorplane_aws_account_id"
echo "Callback URL: $TF_VAR_vectorplane_callback_url"
echo "================================="
```

### Step 4: Initialize and Plan

```bash
# Initialize Terraform
terraform init

# Create execution plan
terraform plan
```

**Review the plan carefully!** It should show:
- 1 Workload Identity Pool
- 1 AWS Provider
- 1 Service Account
- Multiple IAM bindings (varies by scope)

### Step 5: Apply Configuration

```bash
# Apply with confirmation
terraform apply

# Or apply without confirmation
terraform apply -auto-approve
```

### Step 6: Verify Success

After successful deployment, check the outputs:

```bash
terraform output
```

You should see confirmation that the webhook was sent to VectorPlane.

---

## 🔧 Scope-Specific Instructions

### PROJECT Scope (Most Common)

**Use Case**: Connect a single GCP project

**What you get**:
- Security findings from this project only
- Simple setup and management
- Ideal for development or isolated workloads

**No additional configuration needed** - just follow the quick start steps above.

---

### FOLDER Scope

**Use Case**: Connect all projects within a GCP folder

**What you get**:
- Security findings from all projects in the folder (including subfolders)
- Automatic discovery of new projects added to the folder
- Ideal for team-based or environment-based organization

**Additional Requirements**:

1. **Verify folder ID format**:
   ```bash
   echo "Folder ID: $TF_VAR_gcp_scope_id"
   # Should be in format: folders/123456789
   ```

2. **Check folder permissions**:
   ```bash
   gcloud resource-manager folders get-iam-policy $TF_VAR_gcp_scope_id
   ```

   You need `roles/resourcemanager.folderIamAdmin` on the target folder.

---

### ORGANIZATION Scope

**Use Case**: Connect entire GCP organization

**What you get**:
- Security findings from all projects across the organization
- Complete visibility into organizational security posture
- Ideal for centralized security teams

**Additional Requirements**:

1. **Verify organization access**:
   ```bash
   gcloud organizations describe $(gcloud organizations list --filter="displayName:$TF_VAR_organization_domain" --format="value(name)")
   ```

2. **Check organization permissions**:
   You need `roles/resourcemanager.organizationAdmin` on the organization.

---

## 🛡️ Security Information

### What VectorPlane Can Access

Based on your selected scope:

| Scope | Resources | Permissions |
|-------|-----------|-------------|
| **PROJECT** | Single project | Security findings, asset inventory |
| **FOLDER** | All projects in folder | Security findings, project discovery |
| **ORGANIZATION** | All projects in org | Security findings, complete discovery |

### What VectorPlane Cannot Access

VectorPlane has **read-only** access and cannot:

- ❌ Create, modify, or delete GCP resources
- ❌ Access compute instances or data
- ❌ Read application logs or user data
- ❌ Modify IAM policies or permissions

### Token Security

- 🔒 Access tokens expire after **1 hour**
- 🔒 Tokens must be **re-requested** for each API call
- 🔒 VectorPlane's AWS identity is **cryptographically verified**

---

## 🚨 Troubleshooting

### Permission Errors

**Error**: `Permission denied to create workload identity pool`

**Solution**:
```bash
# Check your current project
gcloud config get-value project

# Verify you have the required role
gcloud projects get-iam-policy $(gcloud config get-value project) \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:$(gcloud config get-value account)" \
  --filter="bindings.role:roles/iam.workloadIdentityPoolAdmin"
```

### API Not Enabled

**Error**: `API [service] is not enabled for project [project]`

**Solution**:
```bash
gcloud services enable [service-name]

# Or enable all required services:
gcloud services enable \
  iamcredentials.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  securitycenter.googleapis.com
```

### Webhook Timeout

**Error**: Terraform completes but webhook notification fails

**Root Cause**: Network connectivity or VectorPlane service issue

**Solution**:
1. Check the Terraform outputs for connection details
2. The integration should still work - VectorPlane will detect the resources
3. Contact VectorPlane support if the integration doesn't appear in your dashboard

### Security Center Not Available

**Warning**: `Security Command Center API not enabled`

**Solution**:
```bash
# Enable Security Command Center
gcloud services enable securitycenter.googleapis.com

# For organizations, ensure you have SCC enabled at the org level
```

---

## ✅ Next Steps

After successful deployment:

1. **🎉 Close this Cloud Shell tab** - The setup is complete!

2. **📊 Return to VectorPlane** - Your GCP environment will appear in the Integrations dashboard

3. **⏱️ Wait for initial scan** - VectorPlane will begin discovering and analyzing your resources (typically 5-10 minutes)

4. **🔍 Review findings** - Security findings will appear in the VectorPlane dashboard

5. **📋 Configure policies** - Set up custom security policies and compliance rules

---

## 📞 Support

**Need help?**

- **VectorPlane Support**: Contact through the VectorPlane dashboard
- **Documentation**: [VectorPlane GCP Integration Guide](https://docs.vectorplane.io/integrations/gcp)
- **Community**: [VectorPlane Community Forum](https://community.vectorplane.io)

---

**🔐 Security Reminder**: You can revoke VectorPlane access at any time by deleting the Workload Identity Pool:

```bash
gcloud iam workload-identity-pools delete vectorplane-security-pool \
  --location=global --project=$(gcloud config get-value project)
```