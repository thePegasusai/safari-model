# Provider configuration with version constraint
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

# Project-level IAM role bindings
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.backup_service_account.email}"

  depends_on = [google_service_account.backup_service_account]
}

resource "google_project_iam_member" "bigquery_data_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.backup_service_account.email}"

  depends_on = [google_service_account.backup_service_account]
}

# Conditional ML API permissions based on feature flag
resource "google_project_iam_member" "ml_model_user" {
  count   = var.enable_ml_apis ? 1 : 0
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.backup_service_account.email}"

  depends_on = [google_service_account.backup_service_account]
}

# Additional ML-specific roles when ML APIs are enabled
resource "google_project_iam_member" "cloud_vision_user" {
  count   = var.enable_ml_apis ? 1 : 0
  project = var.project_id
  role    = "roles/cloudvision.serviceAgent"
  member  = "serviceAccount:${google_service_account.backup_service_account.email}"

  depends_on = [google_service_account.backup_service_account]
}

# Bucket-level IAM permissions for backup operations
resource "google_storage_bucket_iam_member" "backup_bucket_admin" {
  bucket = google_storage_bucket.backup_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.backup_service_account.email}"

  depends_on = [
    google_service_account.backup_service_account,
    google_storage_bucket.backup_bucket
  ]
}

# Dataset-level IAM permissions for analytics
resource "google_bigquery_dataset_iam_member" "analytics_dataset_user" {
  dataset_id = google_bigquery_dataset.analytics_dataset.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.backup_service_account.email}"

  depends_on = [
    google_service_account.backup_service_account,
    google_bigquery_dataset.analytics_dataset
  ]
}

# Additional backup-specific roles for cross-cloud redundancy
resource "google_project_iam_member" "backup_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.backup_service_account.email}"

  depends_on = [google_service_account.backup_service_account]
}

resource "google_project_iam_member" "backup_creator" {
  project = var.project_id
  role    = "roles/storage.objectCreator"
  member  = "serviceAccount:${google_service_account.backup_service_account.email}"

  depends_on = [google_service_account.backup_service_account]
}

# Audit logging permissions for security compliance
resource "google_project_iam_member" "audit_log_viewer" {
  project = var.project_id
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${google_service_account.backup_service_account.email}"

  depends_on = [google_service_account.backup_service_account]
}

# Monitoring permissions for operational visibility
resource "google_project_iam_member" "monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.backup_service_account.email}"

  depends_on = [google_service_account.backup_service_account]
}