# AWS Provider configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Local variables for CloudFront configuration
locals {
  cdn_name    = "wildlife-safari-${var.environment}-cdn"
  origin_id   = "wildlife-safari-${var.environment}-media-origin"
  log_bucket  = "wildlife-safari-${var.environment}-cdn-logs"
  
  # Common tags for CloudFront resources
  cdn_tags = merge(var.tags, {
    Service = "cdn"
  })
}

# Create Origin Access Identity for S3 bucket access
resource "aws_cloudfront_origin_access_identity" "main" {
  comment = "OAI for ${local.cdn_name}"
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled    = true
  http_version       = "http2and3"
  price_class        = "PriceClass_All"
  aliases            = ["cdn.${var.domain_name}"]
  web_acl_id         = aws_wafv2_web_acl.cdn.arn
  retain_on_delete   = false
  wait_for_deployment = false
  
  # Origin configuration for S3
  origin {
    domain_name = aws_s3_bucket.media.bucket_regional_domain_name
    origin_id   = local.origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.main.cloudfront_access_identity_path
    }
  }

  # Default cache behavior
  default_cache_behavior {
    target_origin_id = local.origin_id
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    compress         = true

    # Cache configuration
    default_ttl = 86400    # 24 hours
    min_ttl     = 0
    max_ttl     = 31536000 # 1 year

    # Security settings
    viewer_protocol_policy = "redirect-to-https"

    # Cache key and origin requests
    cache_policy_id = aws_cloudfront_cache_policy.default.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.default.id
  }

  # Custom error responses
  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/error/404.html"
    error_caching_min_ttl = 300
  }

  custom_error_response {
    error_code            = 500
    response_code         = 500
    response_page_path    = "/error/500.html"
    error_caching_min_ttl = 300
  }

  # Geo restrictions
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL/TLS configuration
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cdn.arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  # Access logging
  logging_config {
    include_cookies = true
    bucket         = aws_s3_bucket.logs.bucket_domain_name
    prefix         = "cdn/"
  }

  tags = local.cdn_tags
}

# Cache policy for CloudFront
resource "aws_cloudfront_cache_policy" "default" {
  name        = "${local.cdn_name}-cache-policy"
  comment     = "Default cache policy for ${local.cdn_name}"
  min_ttl     = 0
  default_ttl = 86400
  max_ttl     = 31536000

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

# Origin request policy
resource "aws_cloudfront_origin_request_policy" "default" {
  name    = "${local.cdn_name}-origin-policy"
  comment = "Default origin policy for ${local.cdn_name}"

  cookies_config {
    cookie_behavior = "none"
  }
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers"]
    }
  }
  query_strings_config {
    query_string_behavior = "none"
  }
}

# Outputs
output "cloudfront_distribution_id" {
  description = "The ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_domain" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_arn" {
  description = "The ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.arn
}