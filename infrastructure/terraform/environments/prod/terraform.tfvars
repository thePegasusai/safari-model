# AWS Region Configuration
aws_region = "us-west-2"

# Environment Identifier
environment = "prod"

# EKS Cluster Configuration
eks_cluster_version = "1.27"
eks_node_instance_types = ["c5.2xlarge"]
eks_min_nodes = 5
eks_max_nodes = 50

# RDS Configuration
rds_instance_class = "db.r6g.2xlarge"
rds_allocated_storage = 100

# ElastiCache Configuration
elasticache_node_type = "cache.r6g.xlarge"

# Network Configuration
vpc_cidr = "10.0.0.0/16"

# Security Configuration
enable_waf = true
enable_shield_advanced = true
enable_encryption = true

# Backup Configuration
backup_retention_days = 30

# High Availability Configuration
multi_az = true

# Resource Tags
tags = {
  Project          = "wildlife-safari"
  Environment      = "prod"
  ManagedBy        = "terraform"
  Owner            = "wildlife-safari-team"
  CostCenter       = "prod-wildlife-safari"
  SecurityLevel    = "high"
  BackupPolicy     = "daily"
  ComplianceLevel  = "high"
  Application      = "wildlife-detection"
  DataClassification = "sensitive"
}

# Additional Production-specific Settings
enable_cross_region_replication = true
enable_performance_insights = true
enable_enhanced_monitoring = true

# Auto-scaling Configuration
eks_cluster_scaling_config = {
  desired_size = 10
  max_size     = 50
  min_size     = 5
}

# Database Configuration
rds_config = {
  multi_az               = true
  backup_window         = "03:00-04:00"
  maintenance_window    = "Mon:04:00-Mon:05:00"
  deletion_protection   = true
  storage_encrypted     = true
  monitoring_interval   = 60
}

# Cache Configuration
elasticache_config = {
  num_cache_nodes      = 3
  port                = 6379
  maintenance_window  = "sun:05:00-sun:06:00"
  snapshot_retention  = 7
}

# Networking Configuration
vpc_config = {
  enable_dns_hostnames = true
  enable_dns_support   = true
  enable_nat_gateway   = true
  single_nat_gateway   = false
}

# Security Group Configuration
security_config = {
  enable_security_hub     = true
  enable_guard_duty      = true
  enable_config          = true
  enable_cloudtrail      = true
  enable_flow_logs       = true
}

# Monitoring Configuration
monitoring_config = {
  enable_detailed_monitoring = true
  retention_in_days         = 90
  enable_alarm_actions      = true
}

# Backup Configuration
backup_config = {
  enable_cross_region_backup = true
  backup_retention_period    = 30
  preferred_backup_window    = "02:00-03:00"
  enable_point_in_time      = true
}