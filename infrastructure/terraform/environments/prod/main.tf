# Production Environment Terraform Configuration
# Version: 1.0.0

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

  backend "s3" {
    bucket         = "wildlife-safari-terraform-state-prod"
    key            = "prod/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "wildlife-safari-terraform-locks-prod"
    kms_key_id     = "${aws_kms_key.terraform_state.arn}"
  }
}

# Common resource tags
locals {
  environment = "prod"
  common_tags = {
    Environment        = "production"
    Project           = "wildlife-safari"
    ManagedBy         = "terraform"
    Owner             = "wildlife-safari-team"
    SecurityLevel     = "high"
    DataClassification = "sensitive"
  }
}

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region
  default_tags = local.common_tags
}

# Kubernetes Provider Configuration
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = module.eks.cluster_token
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# KMS key for state encryption
resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                   = local.common_tags
}

# EKS Cluster Module
module "eks" {
  source = "../../modules/eks"

  cluster_name         = "wildlife-safari-prod"
  cluster_version      = "1.27"
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  node_instance_types = ["c5.2xlarge", "c5.4xlarge"]
  min_nodes           = 5
  max_nodes           = 50
  
  enable_private_access = true
  enable_public_access  = false
  enable_encryption     = true
  kms_key_arn          = aws_kms_key.eks.arn
  
  enable_waf             = true
  enable_shield_advanced = true
  
  tags = local.common_tags
}

# RDS Database Module
module "rds" {
  source = "../../modules/rds"

  identifier             = "wildlife-safari-prod"
  instance_class         = "db.r6g.2xlarge"
  allocated_storage      = 100
  max_allocated_storage  = 1000
  
  multi_az                = true
  backup_retention_period = 30
  deletion_protection     = true
  
  enable_performance_insights          = true
  performance_insights_retention_period = 7
  
  enable_encryption = true
  kms_key_arn       = aws_kms_key.rds.arn
  
  vpc_id               = module.vpc.vpc_id
  subnet_ids           = module.vpc.database_subnet_ids
  app_security_group_id = module.eks.cluster_security_group_id
  
  tags = local.common_tags
}

# KMS key for RDS encryption
resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                   = local.common_tags
}

# KMS key for EKS encryption
resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                   = local.common_tags
}

# Outputs
output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint for application deployment"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "rds_endpoint" {
  description = "RDS instance endpoint for database connections"
  value       = module.rds.db_instance_endpoint
  sensitive   = true
}