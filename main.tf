# =============================================================================
# VectorPlane GCP Onboarding - Main Resources
# =============================================================================
# Establishes Workload Identity Federation for zero-trust vendor access.
# No long-lived secrets are exchanged or stored.
# =============================================================================

# Provider version constraints are in versions.tf

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# Auto-detect current project from Cloud Shell context
# This is used when gcp_scope_id is empty (PROJECT scope with auto-detect)
data "google_client_config" "current" {}

data "google_project" "current" {
  count      = var.onboarding_scope == "PROJECT" ? 1 : 0
  project_id = local.effective_project_id
}

data "google_organization" "current" {
  count        = var.onboarding_scope == "ORGANIZATION" ? 1 : 0
  organization = var.organization_id != "" ? var.organization_id : var.gcp_scope_id
}

locals {
  # Auto-detect project ID if not provided (for PROJECT scope)
  # CTO Decision: For PROJECT scope, allow empty gcp_scope_id and auto-detect from Cloud Shell
  effective_project_id = var.gcp_scope_id != "" ? var.gcp_scope_id : data.google_client_config.current.project

  # Determine the target project for resource creation
  target_project = var.onboarding_scope == "PROJECT" ? local.effective_project_id : null

  # Project number for WIF audience
  project_number = var.onboarding_scope == "PROJECT" ? data.google_project.current[0].number : null

  # Full WIF pool name for IAM bindings
  wif_pool_name = "projects/${local.project_number}/locations/global/workloadIdentityPools/${var.wif_pool_id}"

  # Full WIF provider name for token exchange
  wif_provider_name = "${local.wif_pool_name}/providers/${var.wif_provider_id}"

  # Provider for webhook: OIDC in dev, AWS in prod
  webhook_wif_provider_name = var.dev_oidc_issuer_url != "" ? (
    "${local.wif_pool_name}/providers/${google_iam_workload_identity_pool_provider.dev_oidc[0].workload_identity_pool_provider_id}"
  ) : local.wif_provider_name

  # Principal for WIF-based IAM bindings (specific to VectorPlane's AWS role)
  wif_principal = "principalSet://iam.googleapis.com/${local.wif_pool_name}/attribute.aws_role/${var.vectorplane_aws_role_name}"

  # Service account email (uses effective project ID)
  service_account_email = "${var.service_account_id}@${local.effective_project_id}.iam.gserviceaccount.com"
}

# -----------------------------------------------------------------------------
# 1. Workload Identity Pool
# -----------------------------------------------------------------------------
# The container for federated identities. One pool can have multiple providers.

resource "google_iam_workload_identity_pool" "vectorplane" {
  workload_identity_pool_id = var.wif_pool_id
  project                   = var.onboarding_scope == "PROJECT" ? local.effective_project_id : null

  display_name = "VectorPlane Security Triage"
  description  = "Enables VectorPlane to access Security Command Center without static credentials"

  # Pool is active immediately
  disabled = false
}

# -----------------------------------------------------------------------------
# 2. Workload Identity Pool Provider (AWS)
# -----------------------------------------------------------------------------
# Trusts VectorPlane's AWS IAM role as an identity source.

resource "google_iam_workload_identity_pool_provider" "aws" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.vectorplane.workload_identity_pool_id
  workload_identity_pool_provider_id = var.wif_provider_id
  project                            = var.onboarding_scope == "PROJECT" ? local.effective_project_id : null

  display_name = "VectorPlane AWS Backend"
  description  = "Trusts VectorPlane's AWS ECS task role for cross-cloud authentication"

  # AWS-specific configuration
  aws {
    account_id = var.vectorplane_aws_account_id
  }

  # Attribute mapping: Extract useful claims from AWS STS token
  attribute_mapping = {
    "google.subject"        = "assertion.arn"
    "attribute.aws_role"    = "assertion.arn.extract('assumed-role/{role}/')"
    "attribute.aws_account" = "assertion.account"
    "attribute.session"     = "assertion.arn.extract('assumed-role/{role}/{session}')"
  }

  # CRITICAL: Attribute condition restricts access to ONLY VectorPlane's role
  # This prevents any other AWS principal from using this federation
  attribute_condition = "attribute.aws_role == '${var.vectorplane_aws_role_name}'"
}

# -----------------------------------------------------------------------------
# 2b. Workload Identity Pool Provider (Dev OIDC - Local Testing Only)
# -----------------------------------------------------------------------------
# Trusts VectorPlane's local Mock OIDC Provider for dev-mode WIF testing.
# Only created when dev_oidc_issuer_url is set (i.e., development environment).

resource "google_iam_workload_identity_pool_provider" "dev_oidc" {
  count = var.dev_oidc_issuer_url != "" ? 1 : 0

  workload_identity_pool_id          = google_iam_workload_identity_pool.vectorplane.workload_identity_pool_id
  workload_identity_pool_provider_id = "vectorplane-dev-oidc"
  project                            = var.onboarding_scope == "PROJECT" ? local.effective_project_id : null

  display_name = "VectorPlane Dev OIDC (Local Testing)"
  description  = "Trusts VectorPlane's local Mock OIDC Provider for development testing"

  oidc {
    issuer_uri        = var.dev_oidc_issuer_url
    allowed_audiences = ["vectorplane-dev"]
  }

  attribute_mapping = {
    "google.subject" = "assertion.sub"
  }
}

# -----------------------------------------------------------------------------
# 3. Service Account for VectorPlane
# -----------------------------------------------------------------------------
# This is the identity VectorPlane will impersonate to access GCP APIs.

resource "google_service_account" "vectorplane" {
  account_id   = var.service_account_id
  project      = var.onboarding_scope == "PROJECT" ? local.effective_project_id : null
  display_name = "VectorPlane Security Triage"
  description  = "Service account impersonated by VectorPlane via Workload Identity Federation"
}

# -----------------------------------------------------------------------------
# 4. WIF -> Service Account Impersonation Permission
# -----------------------------------------------------------------------------
# CRITICAL: Without this, the token exchange will fail with 403.
# Grants the WIF principal permission to generate tokens for this SA.

resource "google_service_account_iam_member" "wif_token_creator" {
  service_account_id = google_service_account.vectorplane.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.wif_principal
}

# Also allow workloadIdentityUser for the impersonation flow
resource "google_service_account_iam_member" "wif_identity_user" {
  service_account_id = google_service_account.vectorplane.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.wif_principal
}

# Dev OIDC: Grant SA impersonation to any identity in the WIF pool.
# Required because the OIDC identity lacks the attribute.aws_role claim
# that the production wif_principal is scoped to.
resource "google_service_account_iam_member" "dev_oidc_token_creator" {
  count              = var.dev_oidc_issuer_url != "" ? 1 : 0
  service_account_id = google_service_account.vectorplane.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "principalSet://iam.googleapis.com/${local.wif_pool_name}/*"
}

resource "google_service_account_iam_member" "dev_oidc_identity_user" {
  count              = var.dev_oidc_issuer_url != "" ? 1 : 0
  service_account_id = google_service_account.vectorplane.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${local.wif_pool_name}/*"
}

# -----------------------------------------------------------------------------
# 5. IAM Role Bindings - Project Level
# -----------------------------------------------------------------------------
# These bindings grant the Service Account access to GCP resources.

# Security Command Center - Findings Editor (read + update findings)
resource "google_project_iam_member" "scc_findings_editor" {
  count   = var.onboarding_scope == "PROJECT" ? 1 : 0
  project = local.effective_project_id
  role    = "roles/securitycenter.findingsEditor"
  member  = "serviceAccount:${google_service_account.vectorplane.email}"
}

# GCS Object Viewer - For Terraform state file access (Handshake Validator)
resource "google_project_iam_member" "storage_viewer" {
  count   = var.onboarding_scope == "PROJECT" && var.enable_state_file_access ? 1 : 0
  project = local.effective_project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.vectorplane.email}"
}

# -----------------------------------------------------------------------------
# 6. IAM Role Bindings - Organization Level
# -----------------------------------------------------------------------------
# These bindings apply when onboarding_scope is ORGANIZATION.

# Security Command Center - Findings Editor at Org Level
resource "google_organization_iam_member" "scc_findings_editor" {
  count  = var.onboarding_scope == "ORGANIZATION" ? 1 : 0
  org_id = var.organization_id != "" ? var.organization_id : var.gcp_scope_id
  role   = "roles/securitycenter.findingsEditor"
  member = "serviceAccount:${google_service_account.vectorplane.email}"
}

# GCS Object Viewer at Org Level
resource "google_organization_iam_member" "storage_viewer" {
  count  = var.onboarding_scope == "ORGANIZATION" && var.enable_state_file_access ? 1 : 0
  org_id = var.organization_id != "" ? var.organization_id : var.gcp_scope_id
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.vectorplane.email}"
}

# Resource Manager - Folder Viewer (for hierarchy discovery)
resource "google_organization_iam_member" "folder_viewer" {
  count  = var.onboarding_scope == "ORGANIZATION" && var.enable_folder_discovery ? 1 : 0
  org_id = var.organization_id != "" ? var.organization_id : var.gcp_scope_id
  role   = "roles/resourcemanager.folderViewer"
  member = "serviceAccount:${google_service_account.vectorplane.email}"
}

# Resource Manager - Organization Viewer (for org metadata)
resource "google_organization_iam_member" "org_viewer" {
  count  = var.onboarding_scope == "ORGANIZATION" && var.enable_folder_discovery ? 1 : 0
  org_id = var.organization_id != "" ? var.organization_id : var.gcp_scope_id
  role   = "roles/resourcemanager.organizationViewer"
  member = "serviceAccount:${google_service_account.vectorplane.email}"
}

# Browser - Hierarchy visibility for Ancestry Check + Project Discovery
# Required for: projects.getAncestry (Handshake Validator) and projects.list (Hierarchy Discovery)
# This is the standard least-privilege role for "see structure without accessing data"
resource "google_organization_iam_member" "browser" {
  count  = var.onboarding_scope == "ORGANIZATION" ? 1 : 0
  org_id = var.organization_id != "" ? var.organization_id : var.gcp_scope_id
  role   = "roles/browser"
  member = "serviceAccount:${google_service_account.vectorplane.email}"
}

# -----------------------------------------------------------------------------
# 7. IAM Role Bindings - Folder Level
# -----------------------------------------------------------------------------
# These bindings apply when onboarding_scope is FOLDER.
# Note: gcp_scope_id is expected in "folders/123456" format (normalized by backend).

# Security Command Center - Findings Editor at Folder Level
resource "google_folder_iam_member" "scc_findings_editor" {
  count  = var.onboarding_scope == "FOLDER" ? 1 : 0
  folder = var.gcp_scope_id
  role   = "roles/securitycenter.findingsEditor"
  member = "serviceAccount:${google_service_account.vectorplane.email}"
}

# GCS Object Viewer at Folder Level (for Terraform state file access)
resource "google_folder_iam_member" "storage_viewer" {
  count  = var.onboarding_scope == "FOLDER" && var.enable_state_file_access ? 1 : 0
  folder = var.gcp_scope_id
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.vectorplane.email}"
}

# Resource Manager - Folder Viewer (for hierarchy discovery within folder subtree)
resource "google_folder_iam_member" "folder_viewer" {
  count  = var.onboarding_scope == "FOLDER" && var.enable_folder_discovery ? 1 : 0
  folder = var.gcp_scope_id
  role   = "roles/resourcemanager.folderViewer"
  member = "serviceAccount:${google_service_account.vectorplane.email}"
}

# Browser - Hierarchy visibility for Ancestry Check + Project Discovery
# Required for: projects.getAncestry (Handshake Validator) and projects.list (Hierarchy Discovery)
# This is the standard least-privilege role for "see structure without accessing data"
resource "google_folder_iam_member" "browser" {
  count  = var.onboarding_scope == "FOLDER" ? 1 : 0
  folder = var.gcp_scope_id
  role   = "roles/browser"
  member = "serviceAccount:${google_service_account.vectorplane.email}"
}
