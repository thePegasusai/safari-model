# Core AWS Configuration
aws_region = "us-west-2"
environment = "dev"

# EKS Cluster Configuration
eks_cluster_version = "1.27"
eks_node_instance_types = ["c5.2xlarge"]
eks_min_nodes = 2  # Reduced for dev environment while maintaining basic HA
eks_max_nodes = 5  # Limited scale for dev environment

# RDS Configuration
rds_instance_class = "db.t3.large"  # Smaller instance for dev environment
rds_allocated_storage = 50  # Reduced storage for dev environment
rds_backup_retention_days = 7  # Minimum retention for dev environment

# ElastiCache Configuration
elasticache_node_type = "cache.t3.medium"  # Development-appropriate cache size

# Network Configuration
vpc_cidr = "10.0.0.0/16"
enable_waf = true
enable_shield_advanced = false  # Disabled for dev environment to reduce costs
enable_encryption = true  # Maintain encryption even in dev for security

# Resource Tagging
tags = {
  Project     = "wildlife-safari"
  Environment = "development"
  ManagedBy   = "terraform"
  Team        = "platform"
  CostCenter  = "dev-ops"
}

# Monitoring Configuration
enable_detailed_monitoring = true
log_retention_days = 14

# Development-specific Features
enable_debug_logging = true
enable_dev_tools = true

# Backup Configuration
backup_retention_days = 7  # Minimum retention for development

# Security Configuration
enable_bastion_host = true  # Enable bastion host for secure development access
allow_dev_access_ips = ["10.0.0.0/8"]  # Internal development network