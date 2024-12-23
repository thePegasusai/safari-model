# Core GCP Project Variables
variable "project_id" {
  type        = string
  description = "The GCP project ID where resources will be created"

  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty"
  }
}

variable "region" {
  type        = string
  description = "The GCP region where resources will be created"
  default     = "us-central1"
}

# Backup Storage Configuration
variable "backup_bucket_name" {
  type        = string
  description = "Name of the GCS bucket for cross-cloud backup storage"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.backup_bucket_name))
    error_message = "Bucket name must contain only lowercase letters, numbers, and hyphens"
  }
}

variable "backup_retention_days" {
  type        = number
  description = "Number of days to retain backup data in GCS"
  default     = 30
}

# Analytics Configuration
variable "analytics_dataset_id" {
  type        = string
  description = "ID of the BigQuery dataset for analytics data"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.analytics_dataset_id))
    error_message = "Dataset ID must contain only letters, numbers, and underscores"
  }
}

# Service Account Configuration
variable "backup_service_account_id" {
  type        = string
  description = "ID for the service account used in backup operations"

  validation {
    condition     = can(regex("^[a-z][-a-z0-9]*[a-z0-9]$", var.backup_service_account_id))
    error_message = "Service account ID must match GCP naming requirements"
  }
}

# Feature Flags
variable "enable_ml_apis" {
  type        = bool
  description = "Whether to enable ML-related GCP APIs"
  default     = true
}