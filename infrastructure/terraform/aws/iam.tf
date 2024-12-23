# Provider configuration with required version constraint
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project             = "wildlife-safari"
    Environment         = var.environment
    ManagedBy          = "terraform"
    SecurityCompliance = "NIST800-53"
    DataClassification = "sensitive"
  }
  account_id = data.aws_caller_identity.current.account_id
}

# EKS Cluster Role
resource "aws_iam_role" "eks_cluster_role" {
  name        = "wildlife-safari-eks-cluster-${var.environment}"
  description = "IAM role for EKS cluster with NIST 800-53 compliance"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount": local.account_id
        }
      }
    }]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  ]

  force_detach_policies = true
  tags                 = local.common_tags
}

# EKS Node Group Role
resource "aws_iam_role" "eks_node_role" {
  name        = "wildlife-safari-eks-node-${var.environment}"
  description = "IAM role for EKS worker nodes with least privilege access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ]

  tags = local.common_tags
}

# KMS Key Administrator Role
resource "aws_iam_role" "kms_admin_role" {
  name        = "wildlife-safari-kms-admin-${var.environment}"
  description = "IAM role for KMS key administration with rotation policy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${local.account_id}:root"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:PrincipalTag/SecurityClearance": "kms-administrator"
        }
      }
    }]
  })

  tags = local.common_tags
}

# KMS Key Policy Document
data "aws_iam_policy_document" "kms_key_policy" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "Allow Key Rotation"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.kms_admin_role.arn]
    }

    actions = [
      "kms:CreateKey",
      "kms:ScheduleKeyDeletion",
      "kms:EnableKeyRotation"
    ]
    resources = ["*"]
  }
}

# Service Account Role for Application
resource "aws_iam_role" "app_service_account" {
  name        = "wildlife-safari-app-sa-${var.environment}"
  description = "IAM role for application service account with least privilege"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub": "system:serviceaccount:default:wildlife-safari-app"
        }
      }
    }]
  })

  tags = local.common_tags
}

# CloudWatch Logs Policy
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "wildlife-safari-cloudwatch-${var.environment}"
  role = aws_iam_role.app_service_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/eks/wildlife-safari-${var.environment}/*"
    }]
  })
}

# Outputs
output "eks_cluster_role_arn" {
  description = "ARN of EKS cluster IAM role"
  value       = aws_iam_role.eks_cluster_role.arn
}

output "eks_node_role_arn" {
  description = "ARN of EKS node group IAM role"
  value       = aws_iam_role.eks_node_role.arn
}

output "kms_key_admin_role_arn" {
  description = "ARN of KMS key administrator role"
  value       = aws_iam_role.kms_admin_role.arn
}

output "app_service_account_role_arn" {
  description = "ARN of application service account role"
  value       = aws_iam_role.app_service_account.arn
}