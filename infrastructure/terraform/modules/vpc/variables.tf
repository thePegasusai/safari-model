# Core VPC Configuration
variable "vpc_cidr" {
  type        = string
  description = "The CIDR block for the VPC network space"
}

variable "project_name" {
  type        = string
  description = "Project identifier used for resource naming and tagging (Wildlife Detection Safari Pokédex)"
}

variable "environment" {
  type        = string
  description = "Environment identifier (dev, staging, prod) for resource segmentation and naming"
}

# Availability Zone Configuration
variable "availability_zones" {
  type        = list(string)
  description = "List of AWS availability zones for multi-AZ deployment within the selected region"
}

# NAT Gateway Configuration
variable "enable_nat_gateway" {
  type        = bool
  default     = true
  description = "Flag to enable NAT Gateways for private subnet internet access"
}

variable "single_nat_gateway" {
  type        = bool
  default     = false
  description = "Flag to use a single NAT Gateway instead of one per AZ (true for cost optimization in non-prod environments)"
}

# DNS Configuration
variable "enable_dns_hostnames" {
  type        = bool
  default     = true
  description = "Flag to enable DNS hostname support in the VPC for EC2 instance DNS resolution"
}

variable "enable_dns_support" {
  type        = bool
  default     = true
  description = "Flag to enable DNS resolution support in the VPC for Amazon-provided DNS server"
}

# Database Subnet Configuration
variable "create_database_subnet_group" {
  type        = bool
  default     = true
  description = "Flag to create a dedicated subnet group for RDS database instances in private subnets"
}

# Resource Tagging
variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional resource tags for cost allocation, environment tracking, and resource management"
}