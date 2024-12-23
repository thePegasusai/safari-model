# Provider configuration with required version constraint
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Local variables for resource naming and configuration
locals {
  db_name     = "wildlife_safari_${var.environment}"
  db_username = "wildlife_admin"
  db_port     = 5432

  # Common tags for RDS resources
  rds_tags = merge(var.tags, {
    Service     = "RDS"
    Database    = "PostgreSQL"
    Encryption  = "AES-256"
    Compliance  = "GDPR"
  })
}

# Data source to fetch database subnet information
data "aws_subnets" "database" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  tags = {
    Tier = "database"
  }
}

# RDS subnet group
resource "aws_db_subnet_group" "main" {
  name        = "${local.db_name}-subnet-group"
  description = "Database subnet group for ${local.db_name}"
  subnet_ids  = data.aws_subnets.database.ids

  tags = merge(local.rds_tags, {
    Name = "${local.db_name}-subnet-group"
  })
}

# RDS parameter group for PostgreSQL optimization
resource "aws_db_parameter_group" "main" {
  family = "postgres15"
  name   = "${local.db_name}-params"

  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/4096}MB"
  }

  parameter {
    name  = "max_connections"
    value = "1000"
  }

  parameter {
    name  = "work_mem"
    value = "64MB"
  }

  parameter {
    name  = "maintenance_work_mem"
    value = "256MB"
  }

  parameter {
    name  = "effective_cache_size"
    value = "{DBInstanceClassMemory/2048}MB"
  }

  parameter {
    name  = "checkpoint_timeout"
    value = "900"
  }

  tags = local.rds_tags
}

# IAM role for enhanced monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${local.db_name}-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = local.rds_tags
}

# Attach enhanced monitoring policy to IAM role
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Main RDS instance
resource "aws_db_instance" "main" {
  identifier = local.db_name
  
  # Engine configuration
  engine         = "postgres"
  engine_version = "15.3"
  
  # Instance configuration
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = 1000
  
  # Database configuration
  db_name  = local.db_name
  username = local.db_username
  port     = local.db_port

  # Network configuration
  db_subnet_group_name = aws_db_subnet_group.main.name
  parameter_group_name = aws_db_parameter_group.main.name

  # Storage configuration
  storage_type      = "gp3"
  storage_encrypted = true

  # High availability configuration
  multi_az = true

  # Backup configuration
  backup_retention_period = 30
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"

  # Performance and monitoring
  auto_minor_version_upgrade               = true
  performance_insights_enabled             = true
  performance_insights_retention_period    = 7
  monitoring_interval                      = 60
  monitoring_role_arn                      = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports          = ["postgresql", "upgrade"]

  # Protection settings
  deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "${local.db_name}-final-snapshot"
  copy_tags_to_snapshot    = true

  # Update settings
  apply_immediately = false

  tags = merge(local.rds_tags, {
    Name = local.db_name
  })
}

# Outputs
output "rds_endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = aws_db_instance.main.endpoint
}

output "rds_arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.main.arn
}

output "rds_security_group_id" {
  description = "The security group ID of the RDS instance"
  value       = aws_db_instance.main.vpc_security_group_ids[0]
}