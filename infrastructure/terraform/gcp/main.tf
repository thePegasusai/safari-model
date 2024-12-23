# Provider and Terraform Configuration
# Provider version: google ~> 4.0
# Provider version: google-beta ~> 4.0
terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 4.0"
    }
  }

  backend "gcs" {
    bucket = "wildlife-safari-terraform-state"
    prefix = "gcp"
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Enable required GCP APIs
resource "google_project_service" "storage_api" {
  service              = "storage.googleapis.com"
  disable_on_destroy   = false
}

resource "google_project_service" "bigquery_api" {
  service              = "bigquery.googleapis.com"
  disable_on_destroy   = false
}

resource "google_project_service" "vision_api" {
  count                = var.enable_ml_apis ? 1 : 0
  service              = "vision.googleapis.com"
  disable_on_destroy   = false
}

# Create service account for backup operations
resource "google_service_account" "backup_service_account" {
  account_id   = var.backup_service_account_id
  display_name = "Wildlife Safari Backup Service Account"
  description  = "Service account for managing cross-cloud backup operations"
  
  depends_on = [
    google_project_service.storage_api,
    google_project_service.bigquery_api
  ]
}

# IAM binding for backup service account
resource "google_storage_bucket_iam_member" "backup_storage_admin" {
  bucket = module.storage.backup_bucket.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.backup_service_account.email}"
  
  depends_on = [
    google_service_account.backup_service_account
  ]
}

# IAM binding for BigQuery access
resource "google_bigquery_dataset_iam_member" "backup_bigquery_admin" {
  dataset_id = module.bigquery.analytics_dataset.dataset_id
  role       = "roles/bigquery.dataOwner"
  member     = "serviceAccount:${google_service_account.backup_service_account.email}"
  
  depends_on = [
    google_service_account.backup_service_account
  ]
}

# Create a custom IAM role for backup operations
resource "google_project_iam_custom_role" "backup_operator" {
  role_id     = "backupOperator"
  title       = "Backup Operator"
  description = "Custom role for backup operations in Wildlife Safari application"
  permissions = [
    "storage.buckets.get",
    "storage.objects.create",
    "storage.objects.delete",
    "storage.objects.get",
    "storage.objects.list",
    "bigquery.datasets.get",
    "bigquery.tables.get",
    "bigquery.tables.getData",
    "bigquery.tables.export"
  ]
}

# Assign custom role to backup service account
resource "google_project_iam_member" "backup_operator_binding" {
  project = var.project_id
  role    = google_project_iam_custom_role.backup_operator.id
  member  = "serviceAccount:${google_service_account.backup_service_account.email}"
}

# Create a VPC network for secure access
resource "google_compute_network" "backup_network" {
  name                    = "wildlife-safari-backup-network"
  auto_create_subnetworks = false
  description            = "VPC network for secure backup operations"
}

# Create a subnet for the backup network
resource "google_compute_subnetwork" "backup_subnet" {
  name          = "wildlife-safari-backup-subnet"
  ip_cidr_range = "10.0.0.0/24"
  network       = google_compute_network.backup_network.id
  region        = var.region
  
  # Enable private Google access for accessing GCP services
  private_ip_google_access = true
}

# Configure VPC Service Controls
resource "google_access_context_manager_service_perimeter" "backup_perimeter" {
  provider = google-beta
  parent   = "accessPolicies/${google_access_context_manager_access_policy.default.name}"
  name     = "accessPolicies/${google_access_context_manager_access_policy.default.name}/servicePerimeters/backup"
  title    = "backup_perimeter"
  status {
    restricted_services = [
      "storage.googleapis.com",
      "bigquery.googleapis.com",
      "vision.googleapis.com"
    ]
    resources = ["projects/${var.project_id}"]
    access_levels = [google_access_context_manager_access_level.backup_access.name]
  }
  
  depends_on = [
    google_project_service.storage_api,
    google_project_service.bigquery_api,
    google_project_service.vision_api
  ]
}

# Output important resource information
output "backup_service_account_email" {
  value       = google_service_account.backup_service_account.email
  description = "Email address of the backup service account"
}

output "backup_network_id" {
  value       = google_compute_network.backup_network.id
  description = "ID of the backup VPC network"
}

output "enabled_apis" {
  value = {
    storage   = google_project_service.storage_api.service
    bigquery  = google_project_service.bigquery_api.service
    vision    = var.enable_ml_apis ? google_project_service.vision_api[0].service : "disabled"
  }
  description = "List of enabled GCP APIs"
}