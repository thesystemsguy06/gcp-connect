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

  # Remote state backend is configured dynamically by deploy.sh
  # (generates backend.tf with project-specific GCS bucket)
}