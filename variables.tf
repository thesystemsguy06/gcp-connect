# VectorPlane GCP Onboarding - Variables
# These variables are automatically set by the VectorPlane Cloud Shell deep link

# Required: Session ID from VectorPlane onboarding flow
variable "external_id" {
  type        = string
  description = "Session identifier from VectorPlane onboarding flow (e.g., sess_abc123xyz)"

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

# Required: Onboarding scope level
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

# Optional: GCP Scope ID (required for FOLDER and ORGANIZATION scopes)
variable "gcp_scope_id" {
  type        = string
  description = "GCP resource identifier: folder ID for FOLDER scope, domain for ORGANIZATION scope"
  default     = ""

  validation {
    condition = var.onboarding_scope == "PROJECT" || (
      var.onboarding_scope == "FOLDER" && var.gcp_scope_id != "" && can(regex("^folders/[0-9]+$", var.gcp_scope_id)) ||
      var.onboarding_scope == "ORGANIZATION" && var.gcp_scope_id != ""
    )
    error_message = "FOLDER scope requires gcp_scope_id in format 'folders/123456789'. ORGANIZATION scope requires organization domain."
  }
}

# Optional: Organization domain (for ORGANIZATION scope)
variable "organization_domain" {
  type        = string
  description = "Organization domain name (e.g., 'example.com') for ORGANIZATION scope"
  default     = ""
}

# Optional: Custom service account ID
variable "service_account_id" {
  type        = string
  description = "Custom service account ID (defaults to 'vectorplane-security')"
  default     = "vectorplane-security"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_account_id))
    error_message = "Service account ID must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

# Optional: Custom WIF pool ID
variable "wif_pool_id" {
  type        = string
  description = "Custom Workload Identity Pool ID (defaults to 'vectorplane-security-pool')"
  default     = "vectorplane-security-pool"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,30}[a-z0-9]$", var.wif_pool_id))
    error_message = "WIF pool ID must be 4-32 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

# Optional: Custom WIF provider ID
variable "wif_provider_id" {
  type        = string
  description = "Custom Workload Identity Pool Provider ID (defaults to 'vectorplane-aws-provider')"
  default     = "vectorplane-aws-provider"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,30}[a-z0-9]$", var.wif_provider_id))
    error_message = "WIF provider ID must be 4-32 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}