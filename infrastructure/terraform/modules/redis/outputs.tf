# Redis Cluster Connection Details
output "cluster_endpoint" {
  description = "Primary endpoint for Redis cluster connection used for high-performance caching and session management"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
  sensitive   = false
}

output "cluster_port" {
  description = "Port number for Redis cluster connection (default: 6379)"
  value       = local.redis_port
  sensitive   = false
}

output "security_group_id" {
  description = "Security group ID controlling access to Redis cluster"
  value       = aws_security_group.redis.id
  sensitive   = false
}

# Redis Configuration Details
output "parameter_group_id" {
  description = "ID of the Redis parameter group containing optimized settings for sub-100ms performance"
  value       = aws_elasticache_parameter_group.redis.id
  sensitive   = false
}

output "subnet_group_name" {
  description = "Name of the subnet group where Redis nodes are deployed for high availability"
  value       = aws_elasticache_subnet_group.redis.name
  sensitive   = false
}

# Redis Cluster Status and Configuration
output "cluster_id" {
  description = "Identifier of the Redis replication group"
  value       = aws_elasticache_replication_group.redis.id
  sensitive   = false
}

output "cluster_status" {
  description = "Current status of the Redis cluster"
  value       = aws_elasticache_replication_group.redis.status
  sensitive   = false
}

output "number_cache_clusters" {
  description = "Number of cache clusters in the replication group for 99.9% availability"
  value       = aws_elasticache_replication_group.redis.number_cache_clusters
  sensitive   = false
}

# Redis Monitoring Information
output "cloudwatch_alarm_arn" {
  description = "ARN of the CloudWatch alarm monitoring Redis CPU utilization"
  value       = aws_cloudwatch_metric_alarm.redis_cpu.arn
  sensitive   = false
}

# Redis Configuration Details
output "engine_version" {
  description = "Redis engine version deployed in the cluster"
  value       = aws_elasticache_replication_group.redis.engine_version
  sensitive   = false
}

output "maintenance_window" {
  description = "Maintenance window for the Redis cluster"
  value       = aws_elasticache_replication_group.redis.maintenance_window
  sensitive   = false
}

# Redis Reader Endpoints
output "reader_endpoint" {
  description = "Reader endpoint for Redis cluster used for read scaling"
  value       = aws_elasticache_replication_group.redis.reader_endpoint_address
  sensitive   = false
}

# Redis Authentication
output "auth_token_version" {
  description = "Current version of the Redis authentication token"
  value       = aws_elasticache_replication_group.redis.auth_token_update_strategy
  sensitive   = false
}

# Redis Tags
output "resource_tags" {
  description = "Tags applied to the Redis cluster resources"
  value       = aws_elasticache_replication_group.redis.tags_all
  sensitive   = false
}