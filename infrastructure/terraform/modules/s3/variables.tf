# Core Terraform configuration
terraform {
  required_version = "~> 1.0"
}

# Bucket name variable with validation
variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket to be created for storing Wildlife Detection Safari Pokédex application data"

  validation {
    condition     = length(var.bucket_name) >= 3 && length(var.bucket_name) <= 63 && can(regex("^[a-z0-9][a-z0-9-.]*[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name must be between 3 and 63 characters, contain only lowercase letters, numbers, hyphens, and periods, and start/end with a letter or number"
  }
}

# Environment variable with validation
variable "environment" {
  type        = string
  description = "Deployment environment for the S3 bucket (dev, staging, prod)"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

# Data classification variable with validation
variable "data_classification" {
  type        = string
  description = "Classification level of data to be stored (public, internal, sensitive, critical)"

  validation {
    condition     = contains(["public", "internal", "sensitive", "critical"], var.data_classification)
    error_message = "Data classification must be one of: public, internal, sensitive, critical"
  }
}

# Versioning configuration
variable "enable_versioning" {
  type        = bool
  description = "Enable versioning for the S3 bucket to maintain multiple variants of objects"
  default     = true
}

# Encryption configuration
variable "enable_encryption" {
  type        = bool
  description = "Enable server-side encryption for the S3 bucket"
  default     = true
}

variable "encryption_algorithm" {
  type        = string
  description = "Server-side encryption algorithm (AES256 for standard, aws:kms for KMS)"
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.encryption_algorithm)
    error_message = "Encryption algorithm must be either AES256 or aws:kms"
  }
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of KMS key for encryption when using aws:kms algorithm"
  default     = null
}

# Replication configuration
variable "enable_replication" {
  type        = bool
  description = "Enable cross-region replication for disaster recovery"
  default     = false
}

variable "replication_configuration" {
  type = object({
    region      = string
    bucket_arn  = string
    kms_key_arn = string
  })
  description = "Configuration for cross-region replication"
  default     = null
}

# Lifecycle rules configuration
variable "lifecycle_rules" {
  type = list(object({
    name                               = string
    enabled                           = bool
    prefix                            = string
    transitions                       = list(object({
      days          = number
      storage_class = string
    }))
    expiration_days                    = number
    noncurrent_version_expiration_days = number
  }))
  description = "Lifecycle rules for object management and cost optimization"
  default     = []
}

# CORS rules configuration
variable "cors_rules" {
  type = list(object({
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = list(string)
    max_age_seconds = number
  }))
  description = "CORS rules for mobile and web access"
  default     = []
}

# Logging configuration
variable "logging_configuration" {
  type = object({
    target_bucket = string
    target_prefix = string
  })
  description = "Configuration for bucket access logging"
  default     = null
}

# Resource tagging
variable "tags" {
  type        = map(string)
  description = "Tags to be applied to the S3 bucket for resource management"
  default     = {}
}