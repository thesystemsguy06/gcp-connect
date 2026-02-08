# VectorPlane GCP Onboarding - Input Variables
# Configuration parameters for the Terraform module

# Required: External ID for secure session correlation
variable "external_id" {
  type        = string
  description = "Unique session identifier from VectorPlane (used for webhook correlation and IAM trust)"

  validation {
    condition     = can(regex("^sess_[a-zA-Z0-9_-]+$", var.external_id))
    error_message = "External ID must start with 'sess_' followed by alphanumeric characters."
  }
}

# Required: HMAC secret for webhook verification
variable "webhook_secret" {
  type        = string
  description = "HMAC secret for webhook authentication with VectorPlane"
  sensitive   = true

  validation {
    condition     = length(var.webhook_secret) >= 32
    error_message = "Webhook secret must be at least 32 characters long."
  }
}

# Required: VectorPlane webhook callback URL
variable "vectorplane_callback_url" {
  type        = string
  description = "VectorPlane webhook endpoint URL for onboarding completion notification"

  validation {
    condition     = can(regex("^https://.*", var.vectorplane_callback_url))
    error_message = "Callback URL must be HTTPS."
  }
}

# Required: VectorPlane AWS Account ID
variable "vectorplane_aws_account_id" {
  type        = string
  description = "VectorPlane's AWS Account ID for Workload Identity Federation trust"
  default     = "101460827772"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.vectorplane_aws_account_id))
    error_message = "AWS Account ID must be exactly 12 digits."
  }
}

# Required: Onboarding scope
variable "onboarding_scope" {
  type        = string
  description = "Scope of the GCP onboarding: PROJECT, FOLDER, or ORGANIZATION"
  default     = "PROJECT"

  validation {
    condition     = contains(["PROJECT", "FOLDER", "ORGANIZATION"], var.onboarding_scope)
    error_message = "Onboarding scope must be one of: PROJECT, FOLDER, ORGANIZATION."
  }
}

# Optional: Project ID (defaults to current project)
variable "project_id" {
  type        = string
  description = "GCP Project ID where resources will be created (defaults to current project)"
  default     = ""
}

# Optional: GCP scope identifier (folder ID or organization domain)
variable "gcp_scope_id" {
  type        = string
  description = "GCP resource identifier: folder ID for FOLDER scope, domain for ORGANIZATION scope"
  default     = ""
}

# Optional: Organization domain (for ORGANIZATION scope)
variable "organization_domain" {
  type        = string
  description = "GCP Organization domain name (required for ORGANIZATION scope)"
  default     = ""
}
