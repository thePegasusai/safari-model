# Redis Module Configuration for Wildlife Detection Safari Pokédex
# Terraform AWS Provider ~> 5.0
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Local variables for Redis configuration
locals {
  redis_family             = "redis7.0"
  redis_port              = 6379
  redis_maintenance_window = "sun:05:00-sun:09:00"
  redis_snapshot_retention = 7
  redis_maxmemory_policy  = "volatile-lru"
  redis_cluster_mode      = "enabled"
  
  # Tags for resource management
  common_tags = {
    Application = "WildlifeDetectionSafariPokedex"
    Component   = "Cache"
    ManagedBy   = "Terraform"
  }
}

# Redis Parameter Group
resource "aws_elasticache_parameter_group" "redis" {
  family      = local.redis_family
  name        = "${var.cluster_id}-params"
  description = "Redis parameter group for Wildlife Detection Safari Pokédex"

  # Performance optimization parameters
  parameter {
    name  = "maxmemory-policy"
    value = local.redis_maxmemory_policy
  }

  parameter {
    name  = "activedefrag"
    value = "yes"
  }

  parameter {
    name  = "lazyfree-lazy-eviction"
    value = "yes"
  }

  # Security parameters
  parameter {
    name  = "notify-keyspace-events"
    value = "Ex"
  }

  tags = local.common_tags
}

# Redis Subnet Group
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.cluster_id}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = local.common_tags
}

# Redis Security Group
resource "aws_security_group" "redis" {
  name_prefix = "${var.cluster_id}-sg"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    from_port       = local.redis_port
    to_port         = local.redis_port
    protocol        = "tcp"
    security_groups = var.security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# Redis Replication Group
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id          = var.cluster_id
  replication_group_description = "Redis cluster for Wildlife Detection Safari Pokédex"
  node_type                     = var.node_type
  port                         = local.redis_port
  parameter_group_name         = aws_elasticache_parameter_group.redis.name
  subnet_group_name            = aws_elasticache_subnet_group.redis.name
  security_group_ids           = [aws_security_group.redis.id]
  
  # High Availability Configuration
  automatic_failover_enabled    = true
  multi_az_enabled             = true
  num_cache_clusters           = var.num_cache_nodes
  
  # Security Configuration
  auth_token                   = var.auth_token
  transit_encryption_enabled   = true
  at_rest_encryption_enabled   = true
  
  # Backup Configuration
  snapshot_retention_limit     = local.redis_snapshot_retention
  snapshot_window             = "03:00-05:00"
  maintenance_window          = local.redis_maintenance_window
  
  # Performance Configuration
  engine               = "redis"
  engine_version      = "7.0"
  
  # Auto Minor Version Upgrade
  auto_minor_version_upgrade = true

  # Cluster Mode Configuration
  cluster_mode {
    replicas_per_node_group = 2
    num_node_groups         = 3
  }

  tags = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

# CloudWatch Alarms for Redis Monitoring
resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name          = "${var.cluster_id}-cpu-utilization"
  alarm_description   = "Redis cluster CPU utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "CPUUtilization"
  namespace          = "AWS/ElastiCache"
  period             = "300"
  statistic          = "Average"
  threshold          = "75"
  alarm_actions      = [var.notification_topic_arn]
  ok_actions         = [var.notification_topic_arn]

  dimensions = {
    CacheClusterId = aws_elasticache_replication_group.redis.id
  }

  tags = local.common_tags
}

# Outputs
output "redis_endpoint" {
  description = "Redis cluster endpoint"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  description = "Redis port number"
  value       = local.redis_port
}

output "redis_security_group_id" {
  description = "Security group ID for Redis cluster"
  value       = aws_security_group.redis.id
}

output "redis_parameter_group_id" {
  description = "Parameter group ID for Redis cluster"
  value       = aws_elasticache_parameter_group.redis.id
}

output "redis_auth_token_arn" {
  description = "ARN of the Redis auth token secret"
  value       = var.auth_token
  sensitive   = true
}