# AWS Provider configuration
# Provider version: ~> 5.0
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Local variables for common configuration
locals {
  db_name = "wildlife_safari"
  engine  = "postgres"
  engine_version = "15.3"
  port = 5432
  
  common_tags = {
    Project     = "wildlife-safari"
    ManagedBy   = "terraform"
    Environment = var.environment
    Application = "wildlife-detection-safari"
  }
}

# RDS subnet group for multi-AZ deployment
resource "aws_db_subnet_group" "wildlife_safari_db" {
  name        = "${var.identifier}-subnet-group"
  subnet_ids  = var.subnet_ids
  description = "RDS subnet group for Wildlife Safari database"
  
  tags = merge(local.common_tags, var.tags)
}

# Enhanced parameter group for PostgreSQL optimization
resource "aws_db_parameter_group" "wildlife_safari_db" {
  name   = "${var.identifier}-param-group"
  family = "postgres15"
  
  # Performance optimization parameters
  parameter {
    name  = "max_connections"
    value = "1000"
  }
  
  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/4096}"
  }
  
  parameter {
    name  = "work_mem"
    value = "16384"
  }
  
  parameter {
    name  = "maintenance_work_mem"
    value = "2097152"
  }
  
  parameter {
    name  = "effective_cache_size"
    value = "{DBInstanceClassMemory/2}"
  }
  
  parameter {
    name  = "autovacuum_work_mem"
    value = "1048576"
  }
  
  tags = merge(local.common_tags, var.tags)
}

# IAM role for enhanced monitoring
resource "aws_iam_role" "rds_monitoring_role" {
  name = "${var.identifier}-monitoring-role"

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

  tags = merge(local.common_tags, var.tags)
}

# Attach enhanced monitoring policy to the IAM role
resource "aws_iam_role_policy_attachment" "rds_monitoring_policy" {
  role       = aws_iam_role.rds_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Primary RDS instance with high availability configuration
resource "aws_db_instance" "wildlife_safari_db" {
  identifier     = var.identifier
  engine         = local.engine
  engine_version = local.engine_version
  
  # Instance configuration
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  iops                  = 12000
  
  # Database configuration
  db_name  = local.db_name
  port     = local.port
  username = var.db_username
  password = var.db_password
  
  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.wildlife_safari_db.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  parameter_group_name   = aws_db_parameter_group.wildlife_safari_db.name
  
  # High availability configuration
  multi_az                     = true
  availability_zone            = var.primary_az
  backup_retention_period      = 30
  backup_window               = "03:00-04:00"
  maintenance_window          = "Mon:04:00-Mon:05:00"
  auto_minor_version_upgrade  = true
  
  # Security configuration
  storage_encrypted           = true
  deletion_protection         = true
  copy_tags_to_snapshot      = true
  skip_final_snapshot        = false
  final_snapshot_identifier  = "${var.identifier}-final-snapshot"
  
  # Performance and monitoring configuration
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  monitoring_interval                   = 60
  monitoring_role_arn                  = aws_iam_role.rds_monitoring_role.arn
  enabled_cloudwatch_logs_exports      = ["postgresql", "upgrade"]
  
  tags = merge(local.common_tags, var.tags)
}

# Security group for RDS access
resource "aws_security_group" "rds_sg" {
  name        = "${var.identifier}-sg"
  description = "Security group for Wildlife Safari RDS instance"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, var.tags)
}

# Security group rule for application access
resource "aws_security_group_rule" "app_access" {
  type              = "ingress"
  from_port         = local.port
  to_port           = local.port
  protocol          = "tcp"
  security_group_id = aws_security_group.rds_sg.id
  source_security_group_id = var.app_security_group_id
  description       = "Allow access from application servers"
}

# Outputs for reference in other modules
output "db_instance_id" {
  description = "The RDS instance identifier"
  value       = aws_db_instance.wildlife_safari_db.id
}

output "db_instance_endpoint" {
  description = "The RDS connection endpoint"
  value       = aws_db_instance.wildlife_safari_db.endpoint
}

output "db_instance_port" {
  description = "The RDS port number"
  value       = aws_db_instance.wildlife_safari_db.port
}

output "db_security_group_id" {
  description = "The security group ID for RDS instance"
  value       = aws_security_group.rds_sg.id
}