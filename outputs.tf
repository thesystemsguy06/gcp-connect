# =============================================================================
# VectorPlane GCP Onboarding - Outputs
# =============================================================================
# These outputs provide information about the created resources.
# Useful for manual verification if automatic webhook fails.
# =============================================================================

output "setup_status" {
  description = "Human-readable setup completion message"
  value       = "VectorPlane GCP integration configured successfully"
}

# -----------------------------------------------------------------------------
# Workload Identity Federation Details
# -----------------------------------------------------------------------------

output "workload_identity_pool_id" {
  description = "The Workload Identity Pool ID"
  value       = google_iam_workload_identity_pool.vectorplane.workload_identity_pool_id
}

output "workload_identity_pool_name" {
  description = "The full resource name of the Workload Identity Pool"
  value       = google_iam_workload_identity_pool.vectorplane.name
}

output "workload_identity_provider_id" {
  description = "The Workload Identity Pool Provider ID"
  value       = google_iam_workload_identity_pool_provider.aws.workload_identity_pool_provider_id
}

output "workload_identity_provider_name" {
  description = "The full resource name of the WIF Provider (used for token exchange)"
  value       = local.wif_provider_name
}

# -----------------------------------------------------------------------------
# Service Account Details
# -----------------------------------------------------------------------------

output "service_account_email" {
  description = "The Service Account email that VectorPlane will impersonate"
  value       = google_service_account.vectorplane.email
}

output "service_account_unique_id" {
  description = "The unique ID of the Service Account"
  value       = google_service_account.vectorplane.unique_id
}

# -----------------------------------------------------------------------------
# Project/Organization Details
# -----------------------------------------------------------------------------

output "project_id" {
  description = "The GCP Project ID where resources were created (auto-detected if not provided)"
  value       = local.effective_project_id
}

output "project_number" {
  description = "The GCP Project Number"
  value       = local.project_number
}

output "onboarding_scope" {
  description = "The scope of the integration (PROJECT or ORGANIZATION)"
  value       = var.onboarding_scope
}

output "organization_id" {
  description = "The GCP Organization ID (if ORGANIZATION scope)"
  value       = var.onboarding_scope == "ORGANIZATION" ? (var.organization_id != "" ? var.organization_id : var.gcp_scope_id) : null
}

output "folder_id" {
  description = "The GCP Folder ID (if FOLDER scope)"
  value       = var.onboarding_scope == "FOLDER" ? var.gcp_scope_id : null
}

# -----------------------------------------------------------------------------
# IAM Roles Granted
# -----------------------------------------------------------------------------

output "granted_roles" {
  description = "List of IAM roles granted to the VectorPlane Service Account"
  value = compact([
    "roles/securitycenter.findingsEditor",
    var.enable_state_file_access ? "roles/storage.objectViewer" : null,
    # Organization scope roles
    var.onboarding_scope == "ORGANIZATION" && var.enable_folder_discovery ? "roles/resourcemanager.folderViewer" : null,
    var.onboarding_scope == "ORGANIZATION" && var.enable_folder_discovery ? "roles/resourcemanager.organizationViewer" : null,
    var.onboarding_scope == "ORGANIZATION" ? "roles/browser" : null,
    # Folder scope roles
    var.onboarding_scope == "FOLDER" && var.enable_folder_discovery ? "roles/resourcemanager.folderViewer" : null,
    var.onboarding_scope == "FOLDER" ? "roles/browser" : null,
  ])
}

# -----------------------------------------------------------------------------
# Manual Verification Commands
# -----------------------------------------------------------------------------

output "verification_command" {
  description = "Command to manually verify the WIF setup works"
  value       = <<-EOT
    # From an AWS environment with VectorPlane credentials, run:
    gcloud auth print-access-token \
      --impersonate-service-account=${google_service_account.vectorplane.email}
  EOT
}

output "external_id" {
  description = "The VectorPlane session ID for this onboarding"
  value       = var.external_id
  sensitive   = false
}
