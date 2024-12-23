# Core AWS Region Configuration
variable "aws_region" {
  type        = string
  description = "AWS region for resource deployment"
  default     = "us-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d{1}$", var.aws_region))
    error_message = "AWS region must be in format: xx-xxxx-#"
  }
}

# Environment Configuration
variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod)"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

# EKS Cluster Configuration
variable "eks_cluster_version" {
  type        = string
  description = "Kubernetes version for EKS cluster"
  default     = "1.27"

  validation {
    condition     = can(regex("^\\d+\\.\\d+$", var.eks_cluster_version))
    error_message = "EKS cluster version must be in format: #.#"
  }
}

variable "eks_node_instance_types" {
  type        = list(string)
  description = "Instance types for EKS worker nodes"
  default     = ["c5.2xlarge"]

  validation {
    condition     = length(var.eks_node_instance_types) > 0
    error_message = "At least one instance type must be specified"
  }
}

variable "eks_min_nodes" {
  type        = number
  description = "Minimum number of EKS worker nodes"
  default     = 5

  validation {
    condition     = var.eks_min_nodes >= 3
    error_message = "Minimum node count must be at least 3 for high availability"
  }
}

variable "eks_max_nodes" {
  type        = number
  description = "Maximum number of EKS worker nodes"
  default     = 50

  validation {
    condition     = var.eks_max_nodes <= 100
    error_message = "Maximum node count cannot exceed 100"
  }
}

# RDS Configuration
variable "rds_instance_class" {
  type        = string
  description = "RDS instance type"
  default     = "db.r6g.2xlarge"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.rds_instance_class))
    error_message = "Invalid RDS instance class format"
  }
}

variable "rds_allocated_storage" {
  type        = number
  description = "Allocated storage for RDS in GB"
  default     = 100

  validation {
    condition     = var.rds_allocated_storage >= 100
    error_message = "Minimum RDS storage must be 100GB"
  }
}

# ElastiCache Configuration
variable "elasticache_node_type" {
  type        = string
  description = "ElastiCache node type"
  default     = "cache.r6g.xlarge"

  validation {
    condition     = can(regex("^cache\\.[a-z0-9]+\\.[a-z0-9]+$", var.elasticache_node_type))
    error_message = "Invalid ElastiCache node type format"
  }
}

# Network Configuration
variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Invalid VPC CIDR format"
  }
}

# Security Configuration
variable "enable_waf" {
  type        = bool
  description = "Enable AWS WAF for application protection"
  default     = true
}

variable "enable_shield_advanced" {
  type        = bool
  description = "Enable AWS Shield Advanced for DDoS protection"
  default     = true
}

variable "enable_encryption" {
  type        = bool
  description = "Enable encryption for sensitive resources"
  default     = true
}

# Backup Configuration
variable "backup_retention_days" {
  type        = number
  description = "Number of days to retain backups"
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 7
    error_message = "Backup retention must be at least 7 days"
  }
}

# Resource Tagging
variable "tags" {
  type        = map(string)
  description = "Common tags for all resources"
  default = {
    Project     = "wildlife-safari"
    ManagedBy   = "terraform"
    Environment = "var.environment"
  }
}