# EKS Cluster Outputs
output "eks_cluster_id" {
  description = "The ID of the EKS cluster for Kubernetes service integration"
  value       = aws_eks_cluster.main.id
}

output "eks_cluster_endpoint" {
  description = "The endpoint URL for the EKS cluster API server"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_certificate_authority" {
  description = "The base64 encoded certificate authority data for the EKS cluster"
  value       = aws_eks_cluster.main.certificate_authority
  sensitive   = true
}

# VPC and Network Outputs
output "vpc_id" {
  description = "The ID of the VPC containing all application resources"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs for internet-facing resources"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs for internal application resources"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "List of database subnet IDs for RDS and ElastiCache instances"
  value       = aws_subnet.database[*].id
}

# Additional Network Information
output "nat_gateway_ips" {
  description = "List of Elastic IPs associated with NAT Gateways"
  value       = aws_nat_gateway.main[*].public_ip
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

# Security Outputs
output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "eks_node_security_group_id" {
  description = "Security group ID attached to the EKS worker nodes"
  value       = aws_security_group.eks_nodes.id
}

# IAM Outputs
output "eks_cluster_role_arn" {
  description = "ARN of IAM role used by EKS cluster"
  value       = aws_iam_role.eks_cluster_role.arn
}

output "eks_node_role_arn" {
  description = "ARN of IAM role used by EKS worker nodes"
  value       = aws_iam_role.eks_node_role.arn
}

# Region Information
output "availability_zones" {
  description = "List of availability zones used in the VPC"
  value       = data.aws_availability_zones.available.names
}

# Cluster Autoscaling
output "eks_node_group_name" {
  description = "Name of the EKS node group for autoscaling configuration"
  value       = aws_eks_node_group.main.node_group_name
}

output "eks_node_group_resources" {
  description = "List of resources associated with the EKS node group"
  value       = aws_eks_node_group.main.resources
}

# Encryption
output "eks_kms_key_arn" {
  description = "ARN of KMS key used for EKS cluster encryption"
  value       = aws_kms_key.eks.arn
}

output "eks_kms_key_id" {
  description = "ID of KMS key used for EKS cluster encryption"
  value       = aws_kms_key.eks.key_id
}

# Tags
output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}