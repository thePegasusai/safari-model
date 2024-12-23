# Output definitions for the EKS cluster module
# Version: 1.0.0
# Provider version: terraform ~> 1.0

# Cluster identifier output
output "cluster_id" {
  description = "The unique identifier of the EKS cluster for resource tagging and monitoring integration"
  value       = aws_eks_cluster.main.id
  sensitive   = false
}

# Cluster endpoint output
output "cluster_endpoint" {
  description = "The HTTPS endpoint for Kubernetes API server access, required for kubectl and service integration"
  value       = aws_eks_cluster.main.endpoint
  sensitive   = false
}

# Cluster certificate authority data output
output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data required for secure cluster authentication and API communication"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

# Node group identifier output
output "node_group_id" {
  description = "The identifier of the EKS managed node group running c5.2xlarge instances with auto-scaling configuration"
  value       = aws_eks_node_group.ml_workers.id
  sensitive   = false
}

# Node group status output
output "node_group_status" {
  description = "Current operational status of the managed node group, useful for monitoring auto-scaling events and health"
  value       = aws_eks_node_group.ml_workers.status
  sensitive   = false
}

# Additional outputs for enhanced monitoring and integration

output "node_group_scaling_config" {
  description = "Current scaling configuration of the managed node group including min, max, and desired sizes"
  value = {
    min_size     = aws_eks_node_group.ml_workers.scaling_config[0].min_size
    max_size     = aws_eks_node_group.ml_workers.scaling_config[0].max_size
    desired_size = aws_eks_node_group.ml_workers.scaling_config[0].desired_size
  }
  sensitive = false
}

output "cluster_security_group_id" {
  description = "ID of the security group associated with the EKS cluster control plane"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  sensitive   = false
}

output "cluster_version" {
  description = "The Kubernetes version running on the EKS cluster"
  value       = aws_eks_cluster.main.version
  sensitive   = false
}

output "cluster_platform_version" {
  description = "Platform version of the EKS cluster"
  value       = aws_eks_cluster.main.platform_version
  sensitive   = false
}

output "cluster_status" {
  description = "Current status of the EKS cluster"
  value       = aws_eks_cluster.main.status
  sensitive   = false
}