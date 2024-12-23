# Wildlife Detection Safari Pokédex - Staging Environment Infrastructure
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
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket         = "wildlife-safari-terraform-state"
    key            = "staging/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "wildlife-safari-terraform-locks"
  }
}

# Common resource tags for staging environment
locals {
  environment = "staging"
  common_tags = {
    Environment     = "staging"
    Project         = "wildlife-safari"
    ManagedBy      = "terraform"
    BackupSchedule  = "daily"
    RetentionPeriod = "30days"
    CostCenter     = "staging-testing"
    AutoShutdown   = "enabled"
  }
}

# AWS Provider Configuration
provider "aws" {
  region = "us-west-2"
  default_tags = local.common_tags
}

# Primary AWS Infrastructure Module
module "aws_infrastructure" {
  source = "../../aws"
  
  providers = {
    aws = aws
  }

  # Core Infrastructure Settings
  environment         = local.environment
  aws_region         = "us-west-2"
  vpc_cidr           = "10.1.0.0/16"
  availability_zones = ["us-west-2a", "us-west-2b"]

  # EKS Configuration - Staging Optimized
  eks_cluster_version    = "1.27"
  eks_node_instance_types = ["c5.xlarge"]  # Smaller instance type for staging
  eks_min_nodes         = 3                # Reduced node count for staging
  eks_max_nodes         = 10               # Limited max nodes for cost control

  # Database Configuration - Staging Sized
  rds_instance_class    = "db.t3.large"    # Smaller instance for staging
  rds_allocated_storage = 50               # Reduced storage for staging

  # Cache Configuration
  elasticache_node_type       = "cache.t3.medium"
  elasticache_num_cache_nodes = 2

  # Security Features
  enable_waf            = true
  enable_ddos_protection = true
  enable_auto_shutdown  = true             # Enable auto-shutdown for cost savings

  # Backup and Monitoring
  backup_retention_days = 7                # Reduced retention for staging
  monitoring_interval   = 60               # 1-minute monitoring intervals

  tags = local.common_tags
}

# Kubernetes Provider Configuration
provider "kubernetes" {
  host                   = module.aws_infrastructure.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.aws_infrastructure.eks_cluster_ca_cert)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.aws_infrastructure.eks_cluster_name
    ]
  }
}

# Datadog Provider for Monitoring
provider "datadog" {
  api_key = data.aws_secretsmanager_secret_version.datadog_api_key.secret_string
  app_key = data.aws_secretsmanager_secret_version.datadog_app_key.secret_string
}

# Fetch Datadog credentials from AWS Secrets Manager
data "aws_secretsmanager_secret_version" "datadog_api_key" {
  secret_id = "wildlife-safari/staging/datadog-api-key"
}

data "aws_secretsmanager_secret_version" "datadog_app_key" {
  secret_id = "wildlife-safari/staging/datadog-app-key"
}

# Outputs
output "vpc_id" {
  description = "VPC ID for staging environment"
  value       = module.aws_infrastructure.vpc_id
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint URL"
  value       = module.aws_infrastructure.eks_cluster_endpoint
  sensitive   = true
}

output "monitoring_endpoints" {
  description = "Endpoints for monitoring and logging services"
  value = {
    cloudwatch_logs = module.aws_infrastructure.cloudwatch_log_group_name
    datadog_url     = "https://app.datadoghq.com"
  }
}

output "staging_environment_info" {
  description = "Staging environment configuration details"
  value = {
    environment     = local.environment
    region         = "us-west-2"
    eks_version    = "1.27"
    backup_retention = "7 days"
    auto_shutdown  = "enabled"
  }
}