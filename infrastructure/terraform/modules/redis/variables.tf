# Core Redis Configuration Variables
variable "cluster_id" {
  type        = string
  description = "Identifier for the Redis cluster used in the Wildlife Detection Safari Pokédex application"
}

variable "node_type" {
  type        = string
  description = "The compute and memory capacity of the nodes (e.g., cache.t3.medium, cache.r6g.large)"
  default     = "cache.r6g.large"  # Optimized for sub-100ms processing time requirement
}

variable "num_cache_nodes" {
  type        = number
  description = "Number of cache nodes in the Redis cluster for high availability"
  default     = 3  # Minimum for 99.9% availability across AZs
}

# High Availability Configuration
variable "multi_az_enabled" {
  type        = bool
  description = "Enable Multi-AZ deployment for enhanced availability"
  default     = true
}

variable "automatic_failover_enabled" {
  type        = bool
  description = "Enable automatic failover for Multi-AZ deployments"
  default     = true
}

variable "maintenance_window" {
  type        = string
  description = "Preferred maintenance window for the Redis cluster"
  default     = "sun:05:00-sun:07:00"  # Low-traffic window for maintenance
}

# Performance Configuration
variable "parameter_group_family" {
  type        = string
  description = "Redis parameter group family version"
  default     = "redis7.0"  # Latest stable Redis version
}

variable "port" {
  type        = number
  description = "Port number for Redis connections"
  default     = 6379
}

# Security Configuration
variable "auth_token" {
  type        = string
  description = "Authentication token for Redis cluster access"
  sensitive   = true
}

variable "transit_encryption_enabled" {
  type        = bool
  description = "Enable encryption in transit for Redis communications"
  default     = true
}

variable "at_rest_encryption_enabled" {
  type        = bool
  description = "Enable encryption at rest for Redis data"
  default     = true
}

# Network Configuration
variable "subnet_ids" {
  type        = list(string)
  description = "List of VPC subnet IDs for Redis cluster deployment"
}

variable "security_group_ids" {
  type        = list(string)
  description = "List of security group IDs for Redis cluster"
}

# Backup Configuration
variable "snapshot_retention_limit" {
  type        = number
  description = "Number of days to retain automatic snapshot backups"
  default     = 7
}

variable "snapshot_window" {
  type        = string
  description = "Daily time range during which automated backups are created"
  default     = "03:00-05:00"  # Early morning window for backups
}

# Monitoring and Alerting
variable "apply_immediately" {
  type        = bool
  description = "Specifies whether modifications are applied immediately or during maintenance window"
  default     = false
}

variable "notification_topic_arn" {
  type        = string
  description = "ARN of SNS topic for Redis cluster notifications"
  default     = ""
}

# Resource Tagging
variable "tags" {
  type        = map(string)
  description = "Tags to be applied to all Redis cluster resources"
  default     = {
    Application = "WildlifeDetectionSafariPokedex"
    Component   = "Cache"
    ManagedBy   = "Terraform"
  }
}

# Performance Tuning
variable "maxmemory_policy" {
  type        = string
  description = "Redis maxmemory policy for memory management"
  default     = "volatile-lru"  # Optimized for session management
}

variable "reserved_memory_percent" {
  type        = number
  description = "Percentage of memory reserved for Redis system use"
  default     = 25  # Recommended for production workloads
}

# Session Management Configuration
variable "session_timeout" {
  type        = number
  description = "Session timeout in seconds for Redis-based sessions"
  default     = 3600  # 1 hour default session timeout
}

variable "key_prefix" {
  type        = string
  description = "Prefix for Redis keys to prevent naming conflicts"
  default     = "wildlife-safari"
}