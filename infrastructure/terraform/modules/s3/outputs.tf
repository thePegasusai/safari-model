# Output definitions for the S3 bucket module
# AWS Provider version ~> 5.0

# The unique identifier of the S3 bucket
output "bucket_id" {
  description = "The unique identifier of the created S3 bucket, used for resource references and CloudWatch metrics"
  value       = aws_s3_bucket.main.id
}

# The ARN (Amazon Resource Name) of the S3 bucket
output "bucket_arn" {
  description = "The ARN (Amazon Resource Name) of the S3 bucket, required for IAM policies and cross-service access control"
  value       = aws_s3_bucket.main.arn
}

# The fully-qualified domain name of the S3 bucket
output "bucket_domain_name" {
  description = "The fully-qualified domain name of the S3 bucket, used for direct S3 access and CloudFront origin configuration"
  value       = aws_s3_bucket.main.bucket_domain_name
}

# The region-specific domain name of the S3 bucket
output "bucket_regional_domain_name" {
  description = "The region-specific domain name of the S3 bucket, required for regional access patterns and cross-region replication"
  value       = aws_s3_bucket.main.bucket_regional_domain_name
}