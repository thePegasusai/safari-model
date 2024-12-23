# Output definitions for the RDS module
# AWS Provider version: ~> 5.0

# Primary database instance identifier
output "db_instance_id" {
  description = "The unique identifier of the RDS instance for the Wildlife Detection Safari Pokédex database"
  value       = aws_db_instance.wildlife_safari_db.id
  sensitive   = false
}

# Database connection endpoint
output "db_instance_endpoint" {
  description = "The connection endpoint URL for the RDS instance, used for application database connections"
  value       = aws_db_instance.wildlife_safari_db.endpoint
  sensitive   = false
}

# Database port number
output "db_instance_port" {
  description = "The port number on which the database instance accepts connections"
  value       = aws_db_instance.wildlife_safari_db.port
  sensitive   = false
}

# Database instance ARN
output "db_instance_arn" {
  description = "The Amazon Resource Name (ARN) of the RDS instance for IAM and monitoring integration"
  value       = aws_db_instance.wildlife_safari_db.arn
  sensitive   = false
}

# Database subnet group name
output "db_subnet_group_name" {
  description = "The name of the database subnet group for network configuration reference"
  value       = aws_db_instance.wildlife_safari_db.db_subnet_group_name
  sensitive   = false
}

# Database instance status
output "db_instance_status" {
  description = "The current status of the RDS instance"
  value       = aws_db_instance.wildlife_safari_db.status
  sensitive   = false
}

# Database availability zone
output "db_instance_availability_zone" {
  description = "The availability zone where the primary RDS instance is located"
  value       = aws_db_instance.wildlife_safari_db.availability_zone
  sensitive   = false
}

# Enhanced monitoring role ARN
output "monitoring_role_arn" {
  description = "The ARN of the IAM role used for enhanced RDS monitoring"
  value       = aws_db_instance.wildlife_safari_db.monitoring_role_arn
  sensitive   = false
}

# Performance insights enabled status
output "performance_insights_enabled" {
  description = "Indicates whether Performance Insights is enabled for the RDS instance"
  value       = aws_db_instance.wildlife_safari_db.performance_insights_enabled
  sensitive   = false
}

# Backup retention period
output "backup_retention_period" {
  description = "The number of days automated backups are retained"
  value       = aws_db_instance.wildlife_safari_db.backup_retention_period
  sensitive   = false
}

# Multi-AZ deployment status
output "multi_az" {
  description = "Indicates whether the RDS instance is deployed in multiple availability zones"
  value       = aws_db_instance.wildlife_safari_db.multi_az
  sensitive   = false
}

# Storage allocation details
output "allocated_storage" {
  description = "The amount of storage allocated to the RDS instance in gibibytes"
  value       = aws_db_instance.wildlife_safari_db.allocated_storage
  sensitive   = false
}

# Storage encryption status
output "storage_encrypted" {
  description = "Indicates whether the storage encryption is enabled for the RDS instance"
  value       = aws_db_instance.wildlife_safari_db.storage_encrypted
  sensitive   = false
}

# Database engine version
output "engine_version" {
  description = "The version number of the database engine"
  value       = aws_db_instance.wildlife_safari_db.engine_version
  sensitive   = false
}

# Security group ID
output "security_group_id" {
  description = "The ID of the security group associated with the RDS instance"
  value       = aws_security_group.rds_sg.id
  sensitive   = false
}