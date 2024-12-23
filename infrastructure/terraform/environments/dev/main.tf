# Development Environment Configuration for Wildlife Detection Safari Pokédex
# Version: 1.0
# Last Updated: 2024

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }

  # State management configuration for development environment
  backend "s3" {
    bucket         = "wildlife-safari-terraform-state-dev"
    key            = "dev/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "wildlife-safari-terraform-locks-dev"
  }
}

# Local variables for development environment
locals {
  environment = "dev"
  aws_region = "us-west-2"
  
  # Common tags for development resources
  common_tags = {
    Project      = "wildlife-safari"
    Environment  = "development"
    ManagedBy    = "terraform"
    CostCenter   = "development"
    AutoShutdown = "true"  # Enable auto-shutdown for cost savings
  }
}

# AWS provider configuration
provider "aws" {
  region = local.aws_region
  default_tags = local.common_tags
}

# Core AWS infrastructure module
module "aws" {
  source = "../../aws"
  
  environment = local.environment
  aws_region  = local.aws_region
  vpc_cidr    = "10.0.0.0/16"
  
  # Development-specific configurations
  enable_vpc_endpoints = true  # Enable VPC endpoints for better security
  single_nat_gateway  = true   # Use single NAT gateway for cost optimization
  
  tags = local.common_tags
}

# EKS cluster configuration for development
module "eks" {
  source = "../../modules/eks"
  
  cluster_name    = "wildlife-safari-dev"
  cluster_version = "1.27"
  
  # Development-optimized node configuration
  min_nodes = 2  # Reduced node count for development
  max_nodes = 5  # Limited max nodes for cost control
  
  node_instance_types = ["c5.2xlarge"]  # ML-optimized instance type
  
  # Cost optimization features
  enable_spot_instances = true  # Use spot instances for cost savings
  enable_private_access = true  # Enable private endpoint access
  enable_public_access  = true  # Enable public access for development
  
  # Auto shutdown schedule for non-working hours
  auto_shutdown_schedule = "0 20 * * 1-5"  # Shutdown at 8 PM
  auto_startup_schedule  = "0 8 * * 1-5"   # Startup at 8 AM
  
  tags = local.common_tags
}

# RDS configuration for development
module "rds" {
  source = "../../modules/rds"
  
  identifier = "wildlife-safari-dev"
  
  # Development-optimized database configuration
  instance_class        = "db.t3.large"  # Cost-effective instance type
  allocated_storage     = 50             # Reduced storage for development
  max_allocated_storage = 100            # Limited storage growth
  
  # Simplified HA configuration for development
  multi_az = false  # Disable multi-AZ for cost savings
  
  # Development-appropriate backup configuration
  backup_retention_period = 7  # Reduced backup retention
  
  # Development security settings
  deletion_protection = false      # Allow deletion in development
  skip_final_snapshot = true       # Skip final snapshot for easier cleanup
  
  # Monitoring configuration
  auto_shutdown_enabled        = true  # Enable auto shutdown
  performance_insights_enabled = true  # Keep monitoring for debugging
  
  tags = local.common_tags
}

# Outputs for development environment
output "eks_cluster_name" {
  description = "Name of the development EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for development EKS cluster"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "rds_endpoint" {
  description = "Endpoint for development RDS instance"
  value       = module.rds.db_instance_endpoint
  sensitive   = true
}

output "vpc_id" {
  description = "ID of the development VPC"
  value       = module.aws.vpc_id
}