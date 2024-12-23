# Core Terraform functionality for variable definitions
terraform {
  required_version = "~> 1.0"
}

# Project identification variables
variable "project_name" {
  type        = string
  description = "Name of the Wildlife Detection Safari Pokédex project for resource naming and tagging"
}

variable "environment" {
  type        = string
  description = "Deployment environment (e.g., dev, staging, prod)"
}

# CloudFront Distribution Configuration
variable "price_class" {
  type        = string
  description = "CloudFront distribution price class determining edge location coverage (PriceClass_All, PriceClass_200, PriceClass_100)"
  default     = "PriceClass_All" # Default to global coverage for optimal performance
}

# Cache TTL Configuration
variable "default_ttl" {
  type        = number
  description = "Default time-to-live in seconds for cached objects"
  default     = 3600 # 1 hour default cache duration
}

variable "min_ttl" {
  type        = number
  description = "Minimum time-to-live in seconds for cached objects"
  default     = 0 # Allow immediate cache invalidation if needed
}

variable "max_ttl" {
  type        = number
  description = "Maximum time-to-live in seconds for cached objects"
  default     = 86400 # 24 hours maximum cache duration
}

# Security Configuration
variable "ssl_protocol_version" {
  type        = string
  description = "Minimum TLS protocol version for viewer connections to CloudFront"
  default     = "TLSv1.2_2021" # Modern TLS configuration for enhanced security
}

# Resource Tagging
variable "tags" {
  type        = map(string)
  description = "Map of tags to apply to all resources created by this module"
  default     = {
    Terraform   = "true"
    Application = "wildlife-detection-safari-pokedex"
  }
}

# Origin Configuration
variable "origin_domain_name" {
  type        = string
  description = "Domain name of the S3 bucket or custom origin for CloudFront distribution"
}

variable "origin_path" {
  type        = string
  description = "Optional path that CloudFront appends to the origin domain name when requesting content"
  default     = ""
}

# Custom Domain Configuration
variable "domain_names" {
  type        = list(string)
  description = "List of custom domain names (CNAME) for the CloudFront distribution"
  default     = []
}

variable "acm_certificate_arn" {
  type        = string
  description = "ARN of ACM certificate for custom domain SSL/TLS"
  default     = null
}

# WAF Configuration
variable "web_acl_id" {
  type        = string
  description = "ID of AWS WAF web ACL to associate with the distribution"
  default     = null
}

# Performance Optimization
variable "compress" {
  type        = bool
  description = "Whether CloudFront should automatically compress certain files"
  default     = true
}

variable "default_root_object" {
  type        = string
  description = "Object that CloudFront returns when root URL is requested"
  default     = "index.html"
}

# Geographic Restrictions
variable "geo_restriction_type" {
  type        = string
  description = "Method to restrict distribution of content by country (none, whitelist, blacklist)"
  default     = "none"
}

variable "geo_restriction_locations" {
  type        = list(string)
  description = "List of country codes for geo restriction"
  default     = []
}

# Logging Configuration
variable "enable_logging" {
  type        = bool
  description = "Enable CloudFront access logging"
  default     = true
}

variable "log_bucket" {
  type        = string
  description = "S3 bucket for CloudFront access logs"
  default     = null
}

variable "log_prefix" {
  type        = string
  description = "Prefix for CloudFront access logs in the log bucket"
  default     = "cdn-logs/"
}