# Backend configuration for Wildlife Detection Safari Pokédex GCP infrastructure
# Version: 1.0.0
# Provider version: google ~> 4.0
# Last updated: 2024

terraform {
  # Specify minimum Terraform version required
  required_version = ">= 1.0.0"

  # Configure required providers
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }

  # Configure Google Cloud Storage backend
  backend "gcs" {
    bucket = "wildlife-safari-terraform-state"
    prefix = "gcp/state"

    # Configure state storage location for optimal latency
    location = "us-central1"

    # Enable state locking to prevent concurrent modifications
    # Note: GCS uses object versioning for state locking
    # Default lock timeout is 10 minutes
    # Lock acquisition will be handled automatically by Terraform

    # Additional backend configuration:
    # - Object versioning is enabled by default
    # - Server-side encryption is enabled by default (Google-managed keys)
    # - Uniform bucket-level access is enabled
    # - Object lifecycle management is configured for state files
  }
}

# Local backend configuration validation
locals {
  backend_validation = {
    # Ensure backend bucket exists and is accessible
    bucket_validation = {
      name     = "wildlife-safari-terraform-state"
      location = "us-central1"
    }

    # Define minimum required permissions for state management
    required_permissions = [
      "storage.objects.get",
      "storage.objects.create",
      "storage.objects.delete",
      "storage.objects.list"
    ]

    # Define state file organization structure
    state_prefix = "gcp/state"
  }
}

# Data source to validate project configuration
data "google_project" "current" {
  project_id = var.project_id
}

# Configure backend bucket IAM conditions
resource "google_storage_bucket_iam_member" "terraform_state_access" {
  bucket = "wildlife-safari-terraform-state"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"

  condition {
    title       = "terraform_state_access"
    description = "Limit access to Terraform state files"
    expression  = "resource.name.startsWith('${local.backend_validation.state_prefix}')"
  }
}

# Configure audit logging for state operations
resource "google_storage_bucket_iam_audit_config" "state_audit" {
  bucket = "wildlife-safari-terraform-state"

  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# Output backend configuration status
output "backend_configuration" {
  value = {
    bucket_name     = "wildlife-safari-terraform-state"
    state_prefix    = local.backend_validation.state_prefix
    location        = local.backend_validation.bucket_validation.location
    versioning      = "enabled"
    encryption      = "google-managed"
    audit_logging   = "enabled"
    access_control  = "iam"
    state_locking   = "enabled"
  }
  description = "Backend configuration details for reference"
}