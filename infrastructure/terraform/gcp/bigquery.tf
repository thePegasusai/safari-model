# Provider configuration for Google Cloud
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

# BigQuery Dataset for Wildlife Analytics
resource "google_bigquery_dataset" "wildlife_analytics" {
  dataset_id                  = var.analytics_dataset_id
  friendly_name              = "Wildlife Detection Analytics"
  description               = "Dataset for storing and analyzing wildlife detection and discovery data with comprehensive analytics capabilities"
  location                  = var.region
  default_table_expiration_ms = null  # Data retained indefinitely
  delete_contents_on_destroy = false  # Protect against accidental deletion

  # Access control configuration
  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }

  access {
    role          = "READER"
    special_group = "projectReaders"
  }

  access {
    role          = "WRITER"
    special_group = "projectWriters"
  }

  # Resource labels for organization and cost tracking
  labels = {
    environment          = "production"
    application         = "wildlife-safari"
    managed-by          = "terraform"
    data-classification = "sensitive"
    cost-center         = "analytics"
  }
}

# Table for storing species observations
resource "google_bigquery_table" "species_observations" {
  dataset_id          = google_bigquery_dataset.wildlife_analytics.dataset_id
  table_id            = "species_observations"
  deletion_protection = true  # Prevent accidental table deletion
  description         = "Table storing detailed species observation data including ML identification confidence and geospatial information"

  schema = jsonencode({
    fields = [
      {
        name        = "observation_id"
        type        = "STRING"
        mode        = "REQUIRED"
        description = "Unique identifier for each observation"
      },
      {
        name        = "species_name"
        type        = "STRING"
        mode        = "REQUIRED"
        description = "Scientific name of the detected species"
      },
      {
        name        = "confidence_score"
        type        = "FLOAT"
        mode        = "REQUIRED"
        description = "ML model confidence score for species identification"
      },
      {
        name        = "location"
        type        = "GEOGRAPHY"
        mode        = "REQUIRED"
        description = "Geospatial coordinates of the observation"
      },
      {
        name        = "timestamp"
        type        = "TIMESTAMP"
        mode        = "REQUIRED"
        description = "Timestamp of the observation"
      },
      {
        name        = "user_id"
        type        = "STRING"
        mode        = "REQUIRED"
        description = "Identifier of the user who made the observation"
      },
      {
        name = "device_info"
        type = "RECORD"
        mode = "REQUIRED"
        fields = [
          {
            name = "device_type"
            type = "STRING"
            mode = "REQUIRED"
          },
          {
            name = "os_version"
            type = "STRING"
            mode = "REQUIRED"
          }
        ]
      }
    ]
  })
}

# Table for storing analytics metrics
resource "google_bigquery_table" "discovery_metrics" {
  dataset_id          = google_bigquery_dataset.wildlife_analytics.dataset_id
  table_id            = "discovery_metrics"
  deletion_protection = true  # Prevent accidental table deletion
  description         = "Table storing aggregated discovery metrics and analytics data for performance monitoring"

  schema = jsonencode({
    fields = [
      {
        name        = "metric_id"
        type        = "STRING"
        mode        = "REQUIRED"
        description = "Unique identifier for each metric record"
      },
      {
        name        = "metric_name"
        type        = "STRING"
        mode        = "REQUIRED"
        description = "Name of the measured metric"
      },
      {
        name        = "metric_value"
        type        = "FLOAT"
        mode        = "REQUIRED"
        description = "Numerical value of the metric"
      },
      {
        name        = "aggregation_period"
        type        = "STRING"
        mode        = "REQUIRED"
        description = "Time period for metric aggregation"
      },
      {
        name        = "timestamp"
        type        = "TIMESTAMP"
        mode        = "REQUIRED"
        description = "Timestamp of metric recording"
      },
      {
        name = "dimensions"
        type = "RECORD"
        mode = "REPEATED"
        fields = [
          {
            name = "dimension_name"
            type = "STRING"
            mode = "REQUIRED"
          },
          {
            name = "dimension_value"
            type = "STRING"
            mode = "REQUIRED"
          }
        ]
      }
    ]
  })
}