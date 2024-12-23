# Provider version: hashicorp/google ~> 4.0
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

# Main backup storage bucket with versioning and lifecycle policies
resource "google_storage_bucket" "backup_bucket" {
  name                        = var.backup_bucket_name
  location                    = "US"  # Multi-region deployment for redundancy
  storage_class              = "STANDARD"
  uniform_bucket_level_access = true  # Enable uniform bucket-level access for better security

  # Enable versioning for data protection
  versioning {
    enabled = true
  }

  # Lifecycle rule for automated cleanup after retention period
  lifecycle_rule {
    condition {
      age = var.backup_retention_days
      with_state = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  # Configure CORS for cross-origin access if needed
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  # Enable object retention policy
  retention_policy {
    retention_period = var.backup_retention_days * 86400  # Convert days to seconds
  }

  # Labels for resource organization and management
  labels = {
    environment = "production"
    purpose     = "cross-cloud-backup"
    managed-by  = "terraform"
    app         = "wildlife-detection-safari"
  }
}

# IAM binding for backup service account access
resource "google_storage_bucket_iam_binding" "backup_bucket_access" {
  bucket = google_storage_bucket.backup_bucket.name
  role   = "roles/storage.objectViewer"
  
  members = [
    "serviceAccount:${data.google_service_account.backup_service_account.email}"
  ]
}

# Additional IAM binding for backup write operations
resource "google_storage_bucket_iam_binding" "backup_bucket_writer" {
  bucket = google_storage_bucket.backup_bucket.name
  role   = "roles/storage.objectCreator"
  
  members = [
    "serviceAccount:${data.google_service_account.backup_service_account.email}"
  ]
}

# Bucket notification configuration for monitoring
resource "google_storage_notification" "backup_notification" {
  bucket         = google_storage_bucket.backup_bucket.name
  payload_format = "JSON_API_V1"
  topic         = "projects/${var.project_id}/topics/backup-notifications"
  
  event_types = [
    "OBJECT_FINALIZE",
    "OBJECT_DELETE"
  ]

  custom_attributes = {
    environment = "production"
    purpose     = "backup-monitoring"
  }
}

# Output the bucket details for use in other configurations
output "backup_bucket_url" {
  description = "The URL of the created backup bucket"
  value       = google_storage_bucket.backup_bucket.url
}

output "backup_bucket_name" {
  description = "The name of the created backup bucket"
  value       = google_storage_bucket.backup_bucket.name
}