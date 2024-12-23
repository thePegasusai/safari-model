# AWS Provider configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Local variables for domain names
locals {
  domain_name         = var.environment == "prod" ? "wildlifesafari.com" : "${var.environment}.wildlifesafari.com"
  api_domain         = var.environment == "prod" ? "api.wildlifesafari.com" : "api.${var.environment}.wildlifesafari.com"
  api_failover_domain = var.environment == "prod" ? "api-failover.wildlifesafari.com" : "api-failover.${var.environment}.wildlifesafari.com"
}

# CloudWatch Log Group for DNS Query Logging
resource "aws_cloudwatch_log_group" "dns_logs" {
  name              = "/aws/route53/${local.domain_name}"
  retention_in_days = 30
  
  tags = merge(var.tags, {
    Name = "${local.domain_name}-dns-logs"
  })
}

# Primary Route53 Hosted Zone
resource "aws_route53_zone" "main" {
  name    = local.domain_name
  comment = "Managed by Terraform - Wildlife Safari DNS Zone"
  
  force_destroy = false
  
  tags = merge(var.tags, {
    Name = "${local.domain_name}-zone"
  })

  # Enable query logging
  enable_query_logging = true
  query_log_config {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.dns_logs.arn
    log_format              = "json"
  }
}

# DNSSEC Configuration
resource "aws_route53_zone_dnssec" "main" {
  hosted_zone_id = aws_route53_zone.main.zone_id
  signing_status = "SIGNING"

  key_signing_key {
    name               = "wildlife-safari-ksk"
    algorithm         = "ECDSAP256SHA256"
    key_length        = 2048
    status            = "ACTIVE"
    rotation_frequency = "P1Y"  # 1 year rotation
  }

  zone_signing_key {
    name               = "wildlife-safari-zsk"
    algorithm         = "ECDSAP256SHA256"
    key_length        = 1024
    status            = "ACTIVE"
    rotation_frequency = "P3M"  # 3 months rotation
  }

  tags = merge(var.tags, {
    Name = "${local.domain_name}-dnssec"
  })
}

# CDN Alias Record
resource "aws_route53_record" "cdn_alias" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.domain_name
  type    = "A"

  alias {
    name                   = var.cloudfront_distribution_domain
    zone_id                = "Z2FDTNDATAQYW2"  # CloudFront's fixed zone ID
    evaluate_target_health = true
  }
}

# API Primary Health Check
resource "aws_route53_health_check" "api_primary" {
  fqdn              = local.api_domain
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = "3"
  request_interval  = "30"
  
  regions = ["us-east-1", "us-west-2", "eu-west-1"]
  
  enable_sni = true
  search_string = "\"status\":\"healthy\""
  
  tags = merge(var.tags, {
    Name = "${local.api_domain}-primary-health-check"
  })
}

# API Secondary Health Check
resource "aws_route53_health_check" "api_secondary" {
  fqdn              = local.api_failover_domain
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = "3"
  request_interval  = "30"
  
  regions = ["us-east-2", "us-west-1", "eu-central-1"]
  
  enable_sni = true
  search_string = "\"status\":\"healthy\""
  
  tags = merge(var.tags, {
    Name = "${local.api_domain}-secondary-health-check"
  })
}

# API Primary Record (Failover)
resource "aws_route53_record" "api_primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.api_domain
  type    = "A"

  failover_routing_policy {
    type = "PRIMARY"
  }
  
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.api_primary.id

  alias {
    name                   = aws_lb.api_primary.dns_name
    zone_id                = aws_lb.api_primary.zone_id
    evaluate_target_health = true
  }
}

# API Secondary Record (Failover)
resource "aws_route53_record" "api_secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.api_domain
  type    = "A"

  failover_routing_policy {
    type = "SECONDARY"
  }
  
  set_identifier  = "secondary"
  health_check_id = aws_route53_health_check.api_secondary.id

  alias {
    name                   = aws_lb.api_secondary.dns_name
    zone_id                = aws_lb.api_secondary.zone_id
    evaluate_target_health = true
  }
}

# Outputs
output "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS management"
  value       = aws_route53_zone.main.zone_id
}

output "domain_name" {
  description = "Application domain name for reference"
  value       = local.domain_name
}