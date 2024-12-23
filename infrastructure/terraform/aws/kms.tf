# AWS KMS configuration for Wildlife Detection Safari Pokédex
# Provider version: hashicorp/aws ~> 5.0

# Get current AWS account ID for KMS policy
data "aws_caller_identity" "current" {
  description = "Get current AWS account ID for KMS policy"
}

# Local variables
locals {
  kms_key_alias = "wildlife-safari-${var.environment}"
}

# Primary KMS key for application-wide encryption
resource "aws_kms_key" "main" {
  description              = "Primary KMS key for Wildlife Safari application encryption"
  deletion_window_in_days  = 30
  enable_key_rotation     = true
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  key_usage               = "ENCRYPT_DECRYPT"
  multi_region            = true

  # Key policy allowing root account access and service-specific permissions
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowEKSEncryption"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowRDSEncryption"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  # Merge common tags with KMS-specific tags
  tags = merge(local.common_tags, {
    Name = "wildlife-safari-${var.environment}-key"
  })
}

# KMS alias for easier key reference
resource "aws_kms_alias" "main" {
  name          = "alias/${local.kms_key_alias}"
  target_key_id = aws_kms_key.main.key_id
  description   = "Alias for the Wildlife Safari KMS key"
}

# Output the KMS key ARN for use by other resources
output "kms_key_arn" {
  description = "ARN of the KMS key for Wildlife Safari application"
  value       = aws_kms_key.main.arn
}