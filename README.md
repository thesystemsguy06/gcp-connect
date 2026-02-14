# VectorPlane GCP Onboarding Module

Zero-trust integration between VectorPlane and your GCP environment using Workload Identity Federation.

## Overview

This Terraform module establishes a trust relationship that allows VectorPlane to access your GCP Security Command Center **without exchanging long-lived credentials**. Instead, it uses short-lived tokens via Workload Identity Federation (WIF).

### How It Works

```
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│  VectorPlane        │     │  GCP Workload       │     │  Your GCP           │
│  (AWS ECS)          │────>│  Identity Pool      │────>│  Service Account    │
│                     │     │                     │     │                     │
│  AWS STS Token      │     │  Validates AWS      │     │  Access to SCC,     │
│  (short-lived)      │     │  identity           │     │  GCS, etc.          │
└─────────────────────┘     └─────────────────────┘     └─────────────────────┘
```

1. VectorPlane's AWS backend generates a short-lived STS token
2. Token is exchanged with GCP's Security Token Service via WIF
3. GCP validates the token and issues a federated access token
4. Federated token is used to impersonate your Service Account
5. VectorPlane accesses your resources using the impersonated identity

**No static JSON keys. No secrets to rotate. No exfiltration risk.**

## Quick Start (Via VectorPlane UI)

The easiest way to use this module is through the VectorPlane dashboard:

1. Navigate to **Integrations > Add Cloud Account > GCP**
2. Click **"Open in Cloud Shell"**
3. Review the Terraform plan in Cloud Shell
4. Run `terraform apply`
5. Done! VectorPlane will automatically detect the setup.

## Manual Usage

If you prefer to run Terraform locally:

```hcl
module "vectorplane" {
  source = "github.com/vectorplane/gcp-connect"

  # Required: Provided by VectorPlane UI
  external_id    = "sess_01HQ..."      # Your session ID
  webhook_secret = "..."                # HMAC secret for verification
  gcp_scope_id   = "your-project-id"   # Your GCP project ID

  # Optional: Scope configuration
  onboarding_scope = "PROJECT"          # or "ORGANIZATION"
  organization_id  = ""                 # Required for ORGANIZATION scope

  # Optional: Feature flags
  enable_folder_discovery  = true       # For org hierarchy enumeration
  enable_state_file_access = true       # For Terraform state verification
}
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `external_id` | VectorPlane session ID | `string` | - | yes |
| `webhook_secret` | HMAC secret for webhook auth | `string` | - | yes |
| `gcp_scope_id` | Project ID or Organization ID | `string` | - | yes |
| `onboarding_scope` | `PROJECT` or `ORGANIZATION` | `string` | `PROJECT` | no |
| `organization_id` | Org ID (if scope is ORGANIZATION) | `string` | `""` | no |
| `enable_folder_discovery` | Enable folder enumeration | `bool` | `true` | no |
| `enable_state_file_access` | Enable GCS state file access | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| `workload_identity_provider_name` | Full WIF provider resource name |
| `service_account_email` | Service account VectorPlane uses |
| `granted_roles` | List of IAM roles granted |

## IAM Roles Granted

### Project Scope

| Role | Purpose |
|------|---------|
| `roles/securitycenter.findingsEditor` | Read and update security findings |
| `roles/storage.objectViewer` | Read Terraform state files |

### Organization Scope (Additional)

| Role | Purpose |
|------|---------|
| `roles/resourcemanager.folderViewer` | Enumerate folder hierarchy |
| `roles/resourcemanager.organizationViewer` | Read organization metadata |

## Security Considerations

### Trust Boundary

The WIF provider includes an **attribute condition** that restricts access to only VectorPlane's specific AWS IAM role:

```hcl
attribute_condition = "attribute.aws_role == 'VectorPlaneWorker'"
```

This ensures no other AWS principal can use this federation, even if they know the pool name.

### Least Privilege

- **No Admin Access**: We use `findingsEditor`, not `securitycenter.admin`
- **Read-Only Storage**: `objectViewer` only reads files, cannot modify
- **Scoped Access**: Bindings are at project or org level, not global

### Revocation

To revoke VectorPlane's access at any time:

```bash
# Delete the WIF pool (immediate revocation)
gcloud iam workload-identity-pools delete vectorplane-security-pool \
  --location=global --project=YOUR_PROJECT

# Or delete just the provider
gcloud iam workload-identity-pools providers delete vectorplane-aws-provider \
  --workload-identity-pool=vectorplane-security-pool \
  --location=global --project=YOUR_PROJECT
```

## Troubleshooting

### Webhook Failed

If Terraform completes but VectorPlane doesn't show the connection:

1. Check the outputs: `terraform output`
2. Go to VectorPlane > Integrations > Manual Setup
3. Enter the `external_id` and `service_account_email`

### Permission Denied During Apply

Ensure your Cloud Shell has these roles:
- `roles/iam.workloadIdentityPoolAdmin`
- `roles/iam.serviceAccountAdmin`
- `roles/resourcemanager.projectIamAdmin`

### Token Exchange Fails

If VectorPlane reports authentication errors:

1. Verify the WIF pool is not disabled
2. Check the attribute condition matches VectorPlane's role ARN
3. Ensure `serviceAccountTokenCreator` binding exists

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0.0 |
| google | >= 4.50.0 |
| null | >= 3.0.0 |

## License

Copyright 2024 VectorPlane Inc. All rights reserved.
