# Configure Terraform and required providers
terraform {
  required_version = "~> 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Create Origin Access Identity for secure S3 bucket access
resource "aws_cloudfront_origin_access_identity" "main" {
  comment = "${var.project_name}-${var.environment}-oai"
}

# Main CloudFront Distribution
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled    = true
  price_class        = var.price_class
  aliases            = var.domain_names
  default_root_object = var.default_root_object
  web_acl_id         = var.web_acl_id
  
  # Origin configuration for S3
  origin {
    domain_name = var.origin_domain_name
    origin_id   = "S3Origin"
    origin_path = var.origin_path

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.main.cloudfront_access_identity_path
    }
  }

  # Default cache behavior
  default_cache_behavior {
    target_origin_id       = "S3Origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress              = var.compress
    default_ttl           = var.default_ttl
    min_ttl               = var.min_ttl
    max_ttl               = var.max_ttl

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }
  }

  # Custom error response
  custom_error_response {
    error_code         = 403
    response_code      = 404
    response_page_path = "/404.html"
  }

  # Viewer certificate configuration
  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    minimum_protocol_version = var.ssl_protocol_version
    ssl_support_method       = var.acm_certificate_arn != null ? "sni-only" : null
    cloudfront_default_certificate = var.acm_certificate_arn == null
  }

  # Geographic restrictions
  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_restriction_locations
    }
  }

  # Access logging configuration
  dynamic "logging_config" {
    for_each = var.enable_logging && var.log_bucket != null ? [1] : []
    content {
      include_cookies = false
      bucket         = var.log_bucket
      prefix         = var.log_prefix
    }
  }

  # Resource tags
  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-cdn"
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  )
}

# Outputs for cross-module reference
output "distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.id
}

output "distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.arn
}

output "distribution_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "distribution_hosted_zone_id" {
  description = "Route 53 zone ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "origin_access_identity_path" {
  description = "Path of the CloudFront Origin Access Identity"
  value       = aws_cloudfront_origin_access_identity.main.cloudfront_access_identity_path
}

output "origin_access_identity_iam_arn" {
  description = "IAM ARN of the CloudFront Origin Access Identity"
  value       = aws_cloudfront_origin_access_identity.main.iam_arn
}