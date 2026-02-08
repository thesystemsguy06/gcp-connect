# VectorPlane GCP Onboarding Terraform Configuration
# This creates the necessary GCP resources for VectorPlane security scanning

# Use the current project by default
data "google_client_config" "current" {}

data "google_project" "current" {
  project_id = var.project_id != "" ? var.project_id : data.google_client_config.current.project
}

# Get organization and folder information if applicable
data "google_organization" "current" {
  count = var.onboarding_scope == "ORGANIZATION" ? 1 : 0
  domain = var.organization_domain
}

data "google_folder" "current" {
  count  = var.onboarding_scope == "FOLDER" ? 1 : 0
  folder = var.gcp_scope_id
}

# Local values for consistent referencing
locals {
  project_id     = data.google_project.current.project_id
  project_number = data.google_project.current.number

  # Organization ID (for ORGANIZATION scope)
  organization_id = var.onboarding_scope == "ORGANIZATION" && length(data.google_organization.current) > 0 ? data.google_organization.current[0].org_id : null

  # Folder ID (for FOLDER scope)
  folder_id = var.onboarding_scope == "FOLDER" && length(data.google_folder.current) > 0 ? data.google_folder.current[0].name : null

  # Service account name and email
  service_account_id    = "vectorplane-security"
  service_account_email = "${local.service_account_id}@${local.project_id}.iam.gserviceaccount.com"

  # Workload Identity Pool and Provider names
  wif_pool_id     = "vectorplane-security-pool"
  wif_provider_id = "vectorplane-aws-provider"
}

# 1. Workload Identity Pool
resource "google_iam_workload_identity_pool" "vectorplane" {
  workload_identity_pool_id = local.wif_pool_id
  display_name              = "VectorPlane Security Integration"
  description               = "Workload Identity Federation pool for VectorPlane security scanning"
  disabled                  = false
}

# 2. Workload Identity Pool Provider (trusts VectorPlane's AWS account)
resource "google_iam_workload_identity_pool_provider" "aws" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.vectorplane.workload_identity_pool_id
  workload_identity_pool_provider_id = local.wif_provider_id
  display_name                       = "VectorPlane AWS Provider"
  description                        = "Trusts VectorPlane's AWS account for credential exchange"

  aws {
    account_id = var.vectorplane_aws_account_id
  }

  attribute_mapping = {
    "google.subject"        = "assertion.arn"
    "attribute.aws_role"    = "assertion.arn.extract('assumed-role/{role}/')"
    "attribute.aws_account" = "assertion.account"
  }

  # Security: Only accept tokens from VectorPlane's specific AWS account
  attribute_condition = "attribute.aws_account == '${var.vectorplane_aws_account_id}'"
}

# 3. Service Account for VectorPlane
resource "google_service_account" "vectorplane" {
  account_id   = local.service_account_id
  display_name = "VectorPlane Security Scanner"
  description  = "Service account for VectorPlane to access GCP Security Command Center and resources"
}

# 4. Allow Workload Identity Federation to impersonate the Service Account
resource "google_service_account_iam_binding" "wif_impersonation" {
  service_account_id = google_service_account.vectorplane.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.vectorplane.name}/*"
  ]
}

# 5. Grant Security Command Center permissions
resource "google_project_iam_member" "scc_findings_viewer" {
  project = local.project_id
  role    = "roles/securitycenter.findingsViewer"
  member  = "serviceAccount:${google_service_account.vectorplane.email}"
}

# 6. Grant asset inventory permissions
resource "google_project_iam_member" "browser" {
  project = local.project_id
  role    = "roles/browser"
  member  = "serviceAccount:${google_service_account.vectorplane.email}"
}

# 7. Grant folder-level permissions for FOLDER scope
resource "google_folder_iam_member" "folder_scc_viewer" {
  count  = var.onboarding_scope == "FOLDER" ? 1 : 0
  folder = local.folder_id
  role   = "roles/securitycenter.findingsViewer"
  member = "serviceAccount:${google_service_account.vectorplane.email}"
}

resource "google_folder_iam_member" "folder_viewer" {
  count  = var.onboarding_scope == "FOLDER" ? 1 : 0
  folder = local.folder_id
  role   = "roles/resourcemanager.folderViewer"
  member = "serviceAccount:${google_service_account.vectorplane.email}"
}

# 8. Grant organization-level permissions for ORGANIZATION scope
resource "google_organization_iam_member" "org_scc_viewer" {
  count  = var.onboarding_scope == "ORGANIZATION" ? 1 : 0
  org_id = local.organization_id
  role   = "roles/securitycenter.findingsViewer"
  member = "serviceAccount:${google_service_account.vectorplane.email}"
}

resource "google_organization_iam_member" "org_viewer" {
  count  = var.onboarding_scope == "ORGANIZATION" ? 1 : 0
  org_id = local.organization_id
  role   = "roles/resourcemanager.organizationViewer"
  member = "serviceAccount:${google_service_account.vectorplane.email}"
}

# 9. Grant Terraform state access (for state file scanning)
resource "google_project_iam_member" "storage_object_viewer" {
  project = local.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.vectorplane.email}"
}

# 10. Webhook notification after successful deployment
resource "null_resource" "webhook_notification" {
  depends_on = [
    google_iam_workload_identity_pool.vectorplane,
    google_iam_workload_identity_pool_provider.aws,
    google_service_account.vectorplane,
    google_service_account_iam_binding.wif_impersonation,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e

      # Compute timestamp
      TIMESTAMP=$$(date -u +"%Y-%m-%dT%H:%M:%SZ")

      # Build the payload
      PAYLOAD=$$(cat <<EOF
{
  "external_id": "${var.external_id}",
  "project_number": "${local.project_number}",
  "project_id": "${local.project_id}",
  "organization_id": "${local.organization_id}",
  "folder_id": "${local.folder_id}",
  "workload_identity_pool_provider": "projects/${local.project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.vectorplane.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.aws.workload_identity_pool_provider_id}",
  "service_account_email": "${google_service_account.vectorplane.email}",
  "onboarding_scope": "${var.onboarding_scope}"
}
EOF
      )

      # Compute HMAC signature: TIMESTAMP.PAYLOAD
      SIGNATURE_INPUT="$${TIMESTAMP}.$${PAYLOAD}"
      SIGNATURE=$$(echo -n "$${SIGNATURE_INPUT}" | openssl dgst -sha256 -hmac "${var.webhook_secret}" -binary | base64)

      # Send the webhook
      echo "Sending webhook notification to VectorPlane..."
      HTTP_CODE=$$(curl -s -o /dev/null -w "%%{http_code}" \
        -X POST "${var.vectorplane_callback_url}" \
        -H "Content-Type: application/json" \
        -H "X-VectorPlane-Signature: sha256=$${SIGNATURE}" \
        -H "X-VectorPlane-Timestamp: $${TIMESTAMP}" \
        -H "X-VectorPlane-External-ID: ${var.external_id}" \
        -d "$${PAYLOAD}")

      if [ "$$HTTP_CODE" -eq 200 ]; then
        echo "✅ Webhook sent successfully!"
        echo "🎉 GCP onboarding completed. You can close this Cloud Shell tab."
      else
        echo "❌ Webhook failed with HTTP $$HTTP_CODE"
        echo "Please contact VectorPlane support with this error."
        exit 1
      fi
    EOT
  }
}
