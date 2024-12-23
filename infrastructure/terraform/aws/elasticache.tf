# AWS Provider configuration
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
  redis_cluster_name           = "wildlife-safari-${var.environment}-redis"
  redis_parameter_group_name   = "wildlife-safari-${var.environment}-params"
  redis_node_type             = "cache.r6g.2xlarge"  # Optimized for high performance
  redis_num_nodes             = 3                    # For high availability
  redis_maintenance_window    = "sun:05:00-sun:09:00"
  redis_snapshot_window      = "00:00-04:00"
  redis_tags = merge(
    {
      Project     = "wildlife-safari"
      Service     = "cache"
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# Redis subnet group
resource "aws_elasticache_subnet_group" "redis" {
  name        = "${local.redis_cluster_name}-subnet-group"
  description = "Subnet group for Wildlife Safari Redis cluster"
  subnet_ids  = module.vpc.private_subnets
  tags        = local.redis_tags
}

# Redis parameter group
resource "aws_elasticache_parameter_group" "redis" {
  family      = "redis7.0"
  name        = local.redis_parameter_group_name
  description = "Custom parameter group for Wildlife Safari Redis cluster"

  # Performance optimization parameters
  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }

  parameter {
    name  = "activedefrag"
    value = "yes"
  }

  parameter {
    name  = "maxmemory-samples"
    value = "10"
  }

  parameter {
    name  = "timeout"
    value = "300"
  }

  tags = local.redis_tags
}

# Redis replication group
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id          = local.redis_cluster_name
  replication_group_description = "Redis cluster for Wildlife Safari application"
  node_type                    = local.redis_node_type
  number_cache_clusters        = local.redis_num_nodes
  port                         = 6379
  parameter_group_name         = aws_elasticache_parameter_group.redis.name
  subnet_group_name            = aws_elasticache_subnet_group.redis.name
  security_group_ids           = [aws_security_group.redis.id]

  # High availability settings
  automatic_failover_enabled    = true
  multi_az_enabled             = true
  auto_minor_version_upgrade   = true

  # Backup settings
  snapshot_retention_limit     = 7
  snapshot_window             = local.redis_snapshot_window
  maintenance_window          = local.redis_maintenance_window

  # Security settings
  at_rest_encryption_enabled  = true
  transit_encryption_enabled  = true
  auth_token                 = random_password.redis_auth_token.result

  tags = local.redis_tags
}

# Generate secure auth token for Redis
resource "random_password" "redis_auth_token" {
  length  = 32
  special = false
}

# Security group for Redis
resource "aws_security_group" "redis" {
  name        = "${local.redis_cluster_name}-sg"
  description = "Security group for Wildlife Safari Redis cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [module.eks.cluster_security_group_id]
    description     = "Allow Redis access from EKS cluster"
  }

  tags = local.redis_tags
}

# CloudWatch alarms for Redis monitoring
resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name          = "${local.redis_cluster_name}-cpu-utilization"
  alarm_description   = "Redis cluster CPU utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "CPUUtilization"
  namespace          = "AWS/ElastiCache"
  period             = "300"
  statistic          = "Average"
  threshold          = "75"
  alarm_actions      = [var.sns_alert_topic_arn]
  ok_actions         = [var.sns_alert_topic_arn]

  dimensions = {
    CacheClusterId = aws_elasticache_replication_group.redis.id
  }

  tags = local.redis_tags
}

# Outputs
output "redis_endpoint" {
  description = "Redis cluster endpoint"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  description = "Redis cluster port"
  value       = aws_elasticache_replication_group.redis.port
}

output "redis_auth_token" {
  description = "Redis authentication token"
  value       = random_password.redis_auth_token.result
  sensitive   = true
}