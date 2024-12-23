# Core RDS Instance Configuration
variable "identifier" {
  type        = string
  description = "Unique identifier for the RDS instance"
}

variable "engine_version" {
  type        = string
  description = "PostgreSQL engine version to use"
  default     = "15.0" # Latest stable PostgreSQL version as per technical spec
}

variable "instance_class" {
  type        = string
  description = "The instance type for the RDS instance"
  default     = "db.r6g.xlarge" # Optimized for production database workloads
}

variable "allocated_storage" {
  type        = number
  description = "Initial storage allocation in GB for the RDS instance"
  default     = 100 # Base storage allocation
}

variable "max_allocated_storage" {
  type        = number
  description = "Maximum auto-scaling storage limit in GB"
  default     = 1000 # Maximum storage limit for auto-scaling
}

# Network Configuration
variable "vpc_id" {
  type        = string
  description = "ID of the VPC where RDS will be deployed"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the RDS subnet group (should be in different AZs for HA)"
}

# High Availability Configuration
variable "multi_az" {
  type        = bool
  description = "Enable Multi-AZ deployment for high availability"
  default     = true # Enabled by default for production environments
}

# Backup Configuration
variable "backup_retention_period" {
  type        = number
  description = "Number of days to retain automated backups"
  default     = 30 # 30-day retention for production databases
}

variable "backup_window" {
  type        = string
  description = "Daily time range during which automated backups are created (UTC)"
  default     = "03:00-04:00" # Early morning UTC backup window
}

variable "maintenance_window" {
  type        = string
  description = "Weekly time range during which system maintenance can occur (UTC)"
  default     = "Mon:04:00-Mon:05:00" # Maintenance window after backup window
}

# Security Configuration
variable "deletion_protection" {
  type        = bool
  description = "Enable deletion protection for the RDS instance"
  default     = true # Enabled by default for production safety
}

variable "storage_encrypted" {
  type        = bool
  description = "Enable storage encryption using AES-256"
  default     = true # Enabled by default for data security
}

# Monitoring Configuration
variable "performance_insights_enabled" {
  type        = bool
  description = "Enable Performance Insights for enhanced monitoring"
  default     = true # Enabled by default for production monitoring
}

# Resource Tagging
variable "tags" {
  type        = map(string)
  description = "Tags to assign to the RDS instance and related resources"
  default = {
    Environment = "production"
    Service     = "wildlife-detection-db"
    Managed_by  = "terraform"
  }
}