# AWS Provider version constraint
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data source for available AZs in the current region
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Local variables for resource naming and tagging
locals {
  vpc_name = "${var.project_name}-${var.environment}-vpc"
  
  # Get all available AZ names
  availability_zones = data.aws_availability_zones.available.names
  
  # Common tags for all resources
  common_tags = {
    Project       = "wildlife-safari"
    Environment   = var.environment
    ManagedBy     = "terraform"
    SecurityLevel = "high"
    CostCenter    = "infrastructure"
  }
}

# VPC Module configuration
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.1"

  name = local.vpc_name
  cidr = var.vpc_cidr

  # AZ configuration
  azs = local.availability_zones

  # Subnet configuration with CIDR blocks
  private_subnets     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets      = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  database_subnets    = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]

  # NAT Gateway configuration
  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  # DNS configuration
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Database subnet configuration
  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  # VPN Gateway configuration
  enable_vpn_gateway = false

  # Default security group with no rules (explicit rules defined separately)
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  # Enable flow logs
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  tags = local.common_tags
}

# VPC Flow Logs configuration
resource "aws_flow_log" "vpc_flow_logs" {
  vpc_id                   = module.vpc.vpc_id
  traffic_type            = "ALL"
  log_destination_type    = "cloud-watch-logs"
  retention_in_days       = 30
  max_aggregation_interval = 60

  tags = merge(local.common_tags, {
    Name = "${local.vpc_name}-flow-logs"
  })
}

# Network ACL for private subnets
resource "aws_network_acl" "private" {
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Inbound rules
  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  # Outbound rules
  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(local.common_tags, {
    Name = "${local.vpc_name}-private-nacl"
  })
}

# Outputs for use in other Terraform configurations
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

output "database_subnet_ids" {
  description = "List of database subnet IDs"
  value       = module.vpc.database_subnets
}

output "database_subnet_group_name" {
  description = "Name of database subnet group"
  value       = module.vpc.database_subnet_group_name
}

output "nat_public_ips" {
  description = "List of public Elastic IPs created for NAT gateways"
  value       = module.vpc.nat_public_ips
}