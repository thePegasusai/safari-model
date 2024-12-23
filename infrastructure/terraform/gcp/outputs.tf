# Provider version: hashicorp/google ~> 4.0

# Backup Storage Outputs
output "backup_bucket_name" {
  description = "Name of the GCS bucket used for cross-cloud backup storage"
  value       = google_storage_bucket.backup_bucket.name
  sensitive   = false
}

output "backup_bucket_url" {
  description = "URL of the GCS bucket used for cross-cloud backup storage"
  value       = google_storage_bucket.backup_bucket.url
  sensitive   = false
}

# Analytics Outputs
output "analytics_dataset_id" {
  description = "ID of the BigQuery dataset used for analytics data warehousing"
  value       = google_bigquery_dataset.wildlife_analytics.dataset_id
  sensitive   = false
}

output "analytics_dataset_location" {
  description = "Geographic location of the BigQuery dataset"
  value       = google_bigquery_dataset.wildlife_analytics.location
  sensitive   = false
}

# Species Observations Table Output
output "species_observations_table_id" {
  description = "Full ID of the species observations BigQuery table"
  value       = "${google_bigquery_dataset.wildlife_analytics.dataset_id}.${google_bigquery_table.species_observations.table_id}"
  sensitive   = false
}

# Discovery Metrics Table Output
output "discovery_metrics_table_id" {
  description = "Full ID of the discovery metrics BigQuery table"
  value       = "${google_bigquery_dataset.wildlife_analytics.dataset_id}.${google_bigquery_table.discovery_metrics.table_id}"
  sensitive   = false
}

# Backup Storage IAM Outputs
output "backup_bucket_writer_role" {
  description = "IAM role assigned for backup write operations"
  value       = google_storage_bucket_iam_binding.backup_bucket_writer.role
  sensitive   = false
}

output "backup_bucket_reader_role" {
  description = "IAM role assigned for backup read operations"
  value       = google_storage_bucket_iam_binding.backup_bucket_access.role
  sensitive   = false
}

# Backup Configuration Outputs
output "backup_retention_period" {
  description = "Configured retention period for backup data in days"
  value       = var.backup_retention_days
  sensitive   = false
}

output "backup_notification_topic" {
  description = "Pub/Sub topic for backup operation notifications"
  value       = google_storage_notification.backup_notification.topic
  sensitive   = false
}

# Resource Labels Output
output "resource_labels" {
  description = "Common resource labels applied to GCP resources"
  value       = google_storage_bucket.backup_bucket.labels
  sensitive   = false
}