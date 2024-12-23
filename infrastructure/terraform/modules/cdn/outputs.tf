# Core Terraform functionality for output definitions
terraform {
  required_version = "~> 1.0"
}

# CloudFront Distribution ID output
output "distribution_id" {
  description = "The ID of the CloudFront distribution. Used for resource references and monitoring integration with Datadog and other observability tools."
  value       = aws_cloudfront_distribution.main.id
}

# CloudFront Distribution Domain Name output
output "distribution_domain_name" {
  description = "The domain name of the CloudFront distribution. Used for configuring application endpoints and enabling global content delivery with sub-100ms processing time targets."
  value       = aws_cloudfront_distribution.main.domain_name
}

# CloudFront Distribution Hosted Zone ID output
output "distribution_hosted_zone_id" {
  description = "The Route 53 hosted zone ID of the CloudFront distribution. Required for DNS configuration and domain management to achieve 99.9% system availability."
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}