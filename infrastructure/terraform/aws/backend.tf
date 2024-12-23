# Backend configuration for Wildlife Detection Safari Pokédex Infrastructure
# Version: Terraform ~> 1.0
# Purpose: Defines the state storage and locking mechanism for infrastructure management

terraform {
  # S3 Backend Configuration
  backend "s3" {
    # Environment-specific state bucket with consistent naming
    bucket = "wildlife-safari-terraform-state-${var.environment}"
    
    # Hierarchical state file organization
    key = "aws/${var.environment}/terraform.tfstate"
    
    # Region configuration from variables
    region = var.aws_region
    
    # Mandatory encryption settings
    encrypt        = true
    kms_key_id     = "alias/terraform-state-key"
    
    # DynamoDB locking configuration
    dynamodb_table = "wildlife-safari-terraform-locks-${var.environment}"
    
    # Workspace support for multiple deployment scenarios
    workspace_key_prefix = "workspaces"
    
    # Additional security configurations
    force_path_style = false
    sse_algorithm    = "aws:kms"
    
    # Versioning and access logging
    versioning = true
    
    # ACL settings
    acl = "private"
    
    # Lifecycle rules for state files
    lifecycle_rule = {
      enabled = true
      noncurrent_version_expiration = {
        days = 90
      }
    }
    
    # Access control settings
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
}

# Backend configuration validation
locals {
  backend_validation = {
    environment_valid = contains(["dev", "staging", "prod"], var.environment)
    region_valid      = can(regex("^[a-z]{2}-[a-z]+-\\d{1}$", var.aws_region))
  }
}

# Ensure backend validation passes
resource "null_resource" "backend_validation" {
  count = local.backend_validation.environment_valid && local.backend_validation.region_valid ? 0 : "Backend validation failed"
}