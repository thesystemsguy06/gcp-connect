# VectorPlane GCP Onboarding - Outputs
# These outputs provide key resource identifiers after successful deployment

# Project information
output "project_id" {
  description = "GCP Project ID where resources were created"
  value       = local.project_id
}

output "project_number" {
  description = "GCP Project Number"
  value       = local.project_number
}

output "organization_id" {
  description = "GCP Organization ID (if applicable)"
  value       = local.organization_id
}

output "folder_id" {
  description = "GCP Folder ID (for FOLDER scope)"
  value       = local.folder_id
}

# Workload Identity Federation resources
output "workload_identity_pool_id" {
  description = "Workload Identity Pool ID"
  value       = google_iam_workload_identity_pool.vectorplane.workload_identity_pool_id
}

output "workload_identity_pool_name" {
  description = "Full resource name of the Workload Identity Pool"
  value       = google_iam_workload_identity_pool.vectorplane.name
}

output "workload_identity_pool_provider_id" {
  description = "Workload Identity Pool Provider ID"
  value       = google_iam_workload_identity_pool_provider.aws.workload_identity_pool_provider_id
}

output "workload_identity_pool_provider_name" {
  description = "Full resource name of the Workload Identity Pool Provider"
  value       = google_iam_workload_identity_pool_provider.aws.name
}

# Service Account
output "service_account_id" {
  description = "Service Account ID"
  value       = google_service_account.vectorplane.account_id
}

output "service_account_email" {
  description = "Service Account email address"
  value       = google_service_account.vectorplane.email
}

output "service_account_unique_id" {
  description = "Service Account unique ID"
  value       = google_service_account.vectorplane.unique_id
}

# Configuration summary
output "onboarding_scope" {
  description = "Onboarding scope level (PROJECT, FOLDER, or ORGANIZATION)"
  value       = var.onboarding_scope
}

output "external_id" {
  description = "VectorPlane session external ID"
  value       = var.external_id
}

# VectorPlane connection details
output "vectorplane_connection_info" {
  description = "Key information for VectorPlane integration"
  value = {
    project_id                        = local.project_id
    project_number                   = local.project_number
    organization_id                  = local.organization_id
    folder_id                        = local.folder_id
    workload_identity_pool_provider  = google_iam_workload_identity_pool_provider.aws.name
    service_account_email           = google_service_account.vectorplane.email
    onboarding_scope               = var.onboarding_scope
    external_id                    = var.external_id
  }
  sensitive = false
}

# Verification commands
output "verification_commands" {
  description = "Commands to verify the setup"
  value = {
    test_wif_pool = "gcloud iam workload-identity-pools describe ${google_iam_workload_identity_pool.vectorplane.workload_identity_pool_id} --location=global --project=${local.project_id}"
    test_service_account = "gcloud iam service-accounts describe ${google_service_account.vectorplane.email} --project=${local.project_id}"
    list_iam_bindings = "gcloud projects get-iam-policy ${local.project_id} --flatten='bindings[].members' --filter='bindings.members:serviceAccount:${google_service_account.vectorplane.email}'"
  }
}

# Security note
output "security_note" {
  description = "Important security information"
  value = <<-EOT
    ✅ VectorPlane GCP onboarding completed successfully!

    Security Summary:
    - No long-lived credentials were created or exchanged
    - VectorPlane uses Workload Identity Federation for secure, temporary access
    - Access tokens expire after 1 hour and must be re-requested
    - You can revoke access at any time by deleting the Workload Identity Pool

    To revoke access:
    gcloud iam workload-identity-pools delete ${google_iam_workload_identity_pool.vectorplane.workload_identity_pool_id} --location=global --project=${local.project_id}

    VectorPlane will now begin scanning your GCP environment for security findings.
  EOT
}