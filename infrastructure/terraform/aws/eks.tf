# Provider Configuration
# AWS Provider v5.0
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# Local variables for EKS configuration
locals {
  cluster_name = "wildlife-safari-${var.environment}"
  node_groups = {
    min_size       = 5
    max_size       = 50
    desired_size   = 5
    instance_types = ["c5.2xlarge"]
  }
  common_tags = {
    Environment = var.environment
    Application = "wildlife-safari"
    ManagedBy   = "terraform"
  }
}

# KMS key for EKS cluster encryption
resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS cluster encryption"
  deletion_window_in_days = 7
  enable_key_rotation    = true
  tags                   = local.common_tags
}

# IAM role for EKS cluster
resource "aws_iam_role" "eks_cluster_role" {
  name = "${local.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  ]

  tags = local.common_tags
}

# IAM role for EKS node groups
resource "aws_iam_role" "eks_node_role" {
  name = "${local.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ]

  tags = local.common_tags
}

# Security group for EKS cluster
resource "aws_security_group" "eks_cluster" {
  name        = "${local.cluster_name}-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# EKS cluster
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  version  = "1.27"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids              = module.vpc.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = local.common_tags
}

# EKS node group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-workers"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = module.vpc.private_subnet_ids
  instance_types  = local.node_groups.instance_types

  scaling_config {
    desired_size = local.node_groups.desired_size
    min_size     = local.node_groups.min_size
    max_size     = local.node_groups.max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "wildlife-safari-worker"
  }

  # Enable auto-scaling
  tags = merge(
    local.common_tags,
    {
      "k8s.io/cluster-autoscaler/enabled"                 = "true"
      "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_policy
  ]
}

# IAM role policy attachments
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

# Data sources for cluster authentication
data "aws_eks_cluster" "main" {
  name = aws_eks_cluster.main.name
}

data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

# Outputs
output "cluster_id" {
  description = "EKS cluster identifier"
  value       = aws_eks_cluster.main.id
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_auth_token" {
  description = "EKS cluster authentication token"
  value       = data.aws_eks_cluster_auth.main.token
  sensitive   = true
}