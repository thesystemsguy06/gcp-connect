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
2. Click **"Open in Cloud Shell"** and note the **pairing code** shown on the
   dashboard — it is valid for 20 minutes
3. In Cloud Shell, run `./deploy.sh --check` to confirm your prerequisites.
   This changes nothing and does not consume the code
4. Run `./deploy.sh` and paste the pairing code when prompted
5. Watch progress on the dashboard; it updates as each step completes

`deploy.sh` handles configuration, API enablement, and `terraform apply` itself.
You do not run Terraform directly, and you do not copy anything back to the
dashboard by hand.

## Manual Usage

If you prefer to run Terraform locally:

```hcl
module "vectorplane" {
  source = "github.com/thesystemsguy06/gcp-connect"

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
| `gcp_scope_id` | Project, folder, or organization ID | `string` | `""` | in practice |
| `project_id` | Project the resources are created in | `string` | `""` | in practice |
| `onboarding_scope` | `PROJECT`, `FOLDER`, or `ORGANIZATION` | `string` | `PROJECT` | no |
| `organization_id` | Org ID (if scope is ORGANIZATION) | `string` | `""` | no |
| `vectorplane_aws_account_id` | AWS account the WIF provider trusts | `string` | `101460827772` | no |
| `vectorplane_aws_role_name` | AWS role name in the attribute condition | `string` | `VectorPlaneWorker` | no |
| `vectorplane_callback_url` | Where the module reports completion | `string` | `https://api.vectorplane.io/...` | no |
| `wif_pool_id` | Workload Identity Pool ID | `string` | `vectorplane-security-pool` | no |
| `wif_provider_id` | Workload Identity Provider ID | `string` | `vectorplane-aws-provider` | no |
| `service_account_id` | Service account ID to create | `string` | `vectorplane-security` | no |
| `enable_folder_discovery` | Enable folder enumeration | `bool` | `true` | no |
| `enable_state_file_access` | Enable GCS state file access | `bool` | `true` | no |
| `dev_oidc_issuer_url` | Development override for the OIDC issuer | `string` | `""` | no |

Only `external_id` and `webhook_secret` have no default, so only those two are
required by Terraform. `gcp_scope_id` and `project_id` default to `""`, which
applies cleanly and then fails at the IAM binding — supply them.

When you onboard through the dashboard, `deploy.sh` writes all of these into
`terraform.tfvars.json` for you. This table matters only for manual use.

## Outputs

| Name | Description |
|------|-------------|
| `workload_identity_provider_name` | Full WIF provider resource name |
| `service_account_email` | Service account VectorPlane uses |
| `granted_roles` | List of IAM roles granted |

## IAM Roles Granted

This is the complete list. `terraform output granted_roles` prints the same set
for your own scope after apply, so you can verify it rather than trust this table.

### Project Scope

| Role | Purpose |
|------|---------|
| `roles/securitycenter.findingsEditor` | Read and update security findings |
| `roles/storage.objectViewer` | Read Terraform state files (omitted if `enable_state_file_access = false`) |
| `roles/compute.viewer` | Read live resource configuration when generating import HCL |

### Organization Scope (Additional)

| Role | Purpose |
|------|---------|
| `roles/resourcemanager.folderViewer` | Enumerate folder hierarchy (omitted if `enable_folder_discovery = false`) |
| `roles/resourcemanager.organizationViewer` | Read organization metadata |
| `roles/browser` | Resolve project names across the hierarchy |

### Folder Scope (Additional)

| Role | Purpose |
|------|---------|
| `roles/resourcemanager.folderViewer` | Enumerate folder hierarchy (omitted if `enable_folder_discovery = false`) |
| `roles/browser` | Resolve project names within the folder |

All three are read-only apart from `findingsEditor`, which VectorPlane uses to
update the workflow status of findings it has remediated. None of them grant the
ability to create, modify, or delete infrastructure.

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

### Start here

```bash
./deploy.sh --check
```

Reports every prerequisite problem at once — missing tools, wrong directory,
unreachable API, wrong account — and names the command that fixes each. It
changes nothing and does not consume a pairing code, so it is safe to re-run as
often as you like.

### Permission Denied During Apply

`./deploy.sh --check` asks GCP which of the required permissions you actually
hold, using `gcloud projects test-iam-permissions`, and names the ones you are
missing. You do not have to guess at role names.

The permissions needed are covered by `roles/iam.workloadIdentityPoolAdmin`,
`roles/iam.serviceAccountAdmin`, and `roles/resourcemanager.projectIamAdmin`, or
by `roles/owner`. For ORGANIZATION scope you additionally need organization-level
IAM admin — project Owner does not confer it, which is the most common surprise.

### Webhook Failed

If Terraform completes but VectorPlane doesn't show the connection:

1. Check the outputs: `terraform output`
2. Go to VectorPlane > Integrations > Manual Setup
3. Enter the `external_id` and `service_account_email`

### "Invalid pairing code"

Two causes, in order of likelihood. The code expired — they last 20 minutes;
start a new connection from the dashboard for a fresh one. Or you are in the
wrong directory: `cloudshell_open` clones into a subdirectory, and re-logging in
under a different Google account lands you in a different home. `./deploy.sh
--check` verifies the working directory for exactly this reason.

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
