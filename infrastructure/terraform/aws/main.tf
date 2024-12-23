# Provider and Backend Configuration for Wildlife Detection Safari Pokédex
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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket = "wildlife-safari-terraform-state-${var.environment}"
    key    = "aws/${var.environment}/terraform.tfstate"
    region = var.aws_region
    
    # Enhanced Security Configuration
    encrypt        = true
    kms_key_id     = var.state_encryption_key_arn
    dynamodb_table = "wildlife-safari-terraform-locks"
    
    # State File Versioning and Replication
    versioning = true
    replication_configuration {
      role = var.replication_role_arn
      rules {
        destination {
          bucket             = var.dr_state_bucket_arn
          replica_kms_key_id = var.dr_encryption_key_arn
        }
      }
    }
  }
}

# Common resource tags
locals {
  common_tags = {
    Project             = "wildlife-safari"
    Environment         = var.environment
    ManagedBy          = "terraform"
    Owner              = "wildlife-safari-team"
    CostCenter         = "wildlife-detection"
    SecurityLevel      = "high"
    DataClassification = "sensitive"
    BackupSchedule     = "daily"
    ComplianceLevel    = "high"
  }
}

# Primary AWS Provider Configuration
provider "aws" {
  region = var.aws_region
  
  # Security and compliance configurations
  default_tags = local.common_tags
  allowed_account_ids = [var.aws_account_id]
  
  assume_role {
    role_arn     = var.terraform_role_arn
    session_name = "TerraformDeployment"
  }
}

# Secondary region providers for high availability and disaster recovery
provider "aws" {
  for_each = toset(var.secondary_regions)
  alias    = "secondary-${each.key}"
  region   = each.value
  
  default_tags = local.common_tags
  
  assume_role {
    role_arn     = var.terraform_role_arn
    session_name = "TerraformDeployment-${each.key}"
  }
}

# Kubernetes provider configuration for EKS management
provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      data.aws_eks_cluster.main.name
    ]
  }
}

# Random provider for resource naming
provider "random" {}

# Data sources for existing resources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Primary region resources
module "primary_vpc" {
  source = "./modules/vpc"
  
  providers = {
    aws = aws
  }
  
  environment = var.environment
  region      = var.aws_region
  tags        = local.common_tags
}

module "primary_eks" {
  source = "./modules/eks"
  
  providers = {
    aws = aws
  }
  
  vpc_id     = module.primary_vpc.vpc_id
  subnet_ids = module.primary_vpc.private_subnet_ids
  
  environment = var.environment
  region      = var.aws_region
  tags        = local.common_tags
}

# Secondary region resources (for each secondary region)
module "secondary_vpcs" {
  for_each = toset(var.secondary_regions)
  
  source = "./modules/vpc"
  
  providers = {
    aws = aws.secondary-${each.key}
  }
  
  environment = var.environment
  region      = each.value
  tags        = local.common_tags
}

# Security configurations
module "security" {
  source = "./modules/security"
  
  providers = {
    aws = aws
  }
  
  environment        = var.environment
  enable_waf        = var.enable_waf
  enable_shield     = var.enable_shield_advanced
  enable_encryption = var.enable_encryption
  tags              = local.common_tags
}

# Monitoring and logging configuration
module "monitoring" {
  source = "./modules/monitoring"
  
  providers = {
    aws = aws
  }
  
  environment = var.environment
  tags        = local.common_tags
}

# Outputs for critical resource information
output "primary_vpc_id" {
  description = "ID of the primary VPC"
  value       = module.primary_vpc.vpc_id
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS cluster"
  value       = module.primary_eks.cluster_endpoint
  sensitive   = true
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.primary_eks.cluster_name
}

output "secondary_vpc_ids" {
  description = "Map of secondary region VPC IDs"
  value       = {
    for region, vpc in module.secondary_vpcs : region => vpc.vpc_id
  }
}