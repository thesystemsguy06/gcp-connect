# Terraform and Provider Version Constraints
# Ensures compatibility and reproducible deployments

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # Optional: Configure remote state backend
  # Uncomment and customize if you want to store state remotely
  #
  # backend "gcs" {
  #   bucket  = "your-terraform-state-bucket"
  #   prefix  = "vectorplane/gcp-onboarding"
  # }
}