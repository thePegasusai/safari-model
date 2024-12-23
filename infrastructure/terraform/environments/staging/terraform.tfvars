# Core Configuration
aws_region  = "us-west-2"
environment = "staging"

# Network Configuration
vpc_cidr = "10.1.0.0/16"
availability_zones = [
  "us-west-2a",
  "us-west-2b"
]

# EKS Configuration
eks_cluster_version = "1.27"
eks_node_instance_types = ["c5.xlarge"]  # Cost-optimized for staging
eks_min_nodes = 3  # Minimum for HA in staging
eks_max_nodes = 10  # Capped for cost control

# RDS Configuration
rds_instance_class = "db.t3.large"  # Right-sized for staging workloads
rds_allocated_storage = 50  # Reduced storage for staging
rds_backup_retention_days = 7  # Weekly backup retention for staging

# ElastiCache Configuration
elasticache_node_type = "cache.t3.medium"  # Cost-effective for staging
elasticache_num_cache_nodes = 2  # Minimum HA configuration

# Security Configuration
enable_waf = true
enable_shield_advanced = false  # Cost optimization for staging
enable_encryption = true  # Maintain security standards

# Monitoring Configuration
enable_enhanced_monitoring = true
monitoring_interval = 60  # 1-minute intervals

# Backup Configuration
backup_retention_days = 30  # Standard retention for staging

# Resource Tags
tags = {
  Environment     = "staging"
  Project         = "wildlife-safari"
  ManagedBy       = "terraform"
  BackupSchedule  = "daily"
  RetentionPeriod = "30days"
  CostCenter     = "staging-ops"
  SecurityZone   = "restricted"
  DataClass      = "confidential"
}

# Auto-scaling Configuration
eks_cluster_scaling_config = {
  desired_size = 3
  max_size     = 10
  min_size     = 3
}

# Storage Configuration
storage_config = {
  ebs_volume_type = "gp3"
  ebs_volume_size = 50
  ebs_iops        = 3000
}

# Performance Configuration
performance_config = {
  rds_performance_insights_enabled = true
  rds_performance_insights_retention_period = 7
  elasticache_automatic_failover_enabled = true
  elasticache_multi_az_enabled = true
}

# Maintenance Configuration
maintenance_config = {
  preferred_maintenance_window = "sun:05:00-sun:09:00"
  auto_minor_version_upgrade  = true
}