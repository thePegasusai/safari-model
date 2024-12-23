# AWS Provider version ~> 5.0
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Local variables for bucket naming
locals {
  s3_buckets = {
    media   = "wildlife-safari-media-${var.environment}"
    models  = "wildlife-safari-models-${var.environment}"
    assets  = "wildlife-safari-assets-${var.environment}"
    backups = "wildlife-safari-backups-${var.environment}"
  }

  common_tags = merge(var.tags, {
    Service = "storage"
  })
}

# Media Storage Bucket
resource "aws_s3_bucket" "media" {
  bucket = local.s3_buckets.media
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = "aws/s3"
    }
  }
}

resource "aws_s3_bucket_replication_configuration" "media" {
  depends_on = [aws_s3_bucket_versioning.media]
  bucket     = aws_s3_bucket.media.id
  role       = aws_iam_role.replication.arn

  rule {
    id     = "media-replication"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.media_replica.arn
      storage_class = "STANDARD_IA"
    }
  }
}

resource "aws_s3_bucket" "media_replica" {
  provider = aws.secondary
  bucket   = "${local.s3_buckets.media}-replica"
  tags     = local.common_tags
}

resource "aws_s3_bucket_lifecycle_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    id     = "media-lifecycle"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# ML Models Bucket
resource "aws_s3_bucket" "models" {
  bucket = local.s3_buckets.models
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "models" {
  bucket = aws_s3_bucket.models.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "models" {
  bucket = aws_s3_bucket.models.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = "aws/s3"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "models" {
  bucket = aws_s3_bucket.models.id

  rule {
    id     = "models-lifecycle"
    status = "Enabled"

    transition {
      days          = 7
      storage_class = "INTELLIGENT_TIERING"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Application Assets Bucket
resource "aws_s3_bucket" "assets" {
  bucket = local.s3_buckets.assets
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

# Logging Bucket
resource "aws_s3_bucket" "logs" {
  bucket = local.s3_buckets.backups
  tags   = local.common_tags
}

resource "aws_s3_bucket_logging" "media" {
  bucket = aws_s3_bucket.media.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "media-logs/"
}

resource "aws_s3_bucket_logging" "models" {
  bucket = aws_s3_bucket.models.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "models-logs/"
}

resource "aws_s3_bucket_logging" "assets" {
  bucket = aws_s3_bucket.assets.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "assets-logs/"
}

# IAM Role for Replication
resource "aws_iam_role" "replication" {
  name = "s3-bucket-replication-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

# Outputs
output "media_bucket_id" {
  value       = aws_s3_bucket.media.id
  description = "ID of the media storage bucket"
}

output "models_bucket_id" {
  value       = aws_s3_bucket.models.id
  description = "ID of the ML models bucket"
}

output "assets_bucket_id" {
  value       = aws_s3_bucket.assets.id
  description = "ID of the application assets bucket"
}