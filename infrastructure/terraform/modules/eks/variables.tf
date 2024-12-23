# Terraform AWS EKS Module Variables
# Version: 1.0.0
# Provider Requirements:
# - terraform ~> 1.0
# - aws ~> 4.0

variable "cluster_name" {
  description = "Name of the EKS cluster for the Wildlife Detection Safari Pokédex application"
  type        = string
  validation {
    condition     = length(var.cluster_name) > 0 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.cluster_name))
    error_message = "Cluster name must start with a letter, contain only alphanumeric characters and hyphens, and cannot be empty"
  }
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster (must be compatible with AWS EKS)"
  type        = string
  default     = "1.27"
  validation {
    condition     = can(regex("^1\\.(2[5-7])$", var.cluster_version))
    error_message = "Cluster version must be 1.25, 1.26, or 1.27"
  }
}

variable "vpc_id" {
  description = "ID of the VPC where EKS will be deployed (must have appropriate subnets and routing)"
  type        = string
  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "VPC ID must start with 'vpc-'"
  }
}

variable "subnet_ids" {
  description = "List of subnet IDs for EKS node groups (must be in at least 3 different AZs)"
  type        = list(string)
  validation {
    condition     = length(var.subnet_ids) >= 3
    error_message = "At least 3 subnet IDs are required for high availability"
  }
}

variable "node_instance_types" {
  description = "Instance types for worker nodes (must support container workloads)"
  type        = list(string)
  default     = ["c5.2xlarge"]
  validation {
    condition     = alltrue([for t in var.node_instance_types : can(regex("^[a-z][0-9][.][a-z0-9]+$", t))])
    error_message = "Instance types must be valid AWS instance type formats"
  }
}

variable "min_nodes" {
  description = "Minimum number of worker nodes per node group"
  type        = number
  default     = 5
  validation {
    condition     = var.min_nodes >= 3 && var.min_nodes <= var.max_nodes
    error_message = "Minimum nodes must be at least 3 and not exceed maximum nodes"
  }
}

variable "max_nodes" {
  description = "Maximum number of worker nodes per node group"
  type        = number
  default     = 50
  validation {
    condition     = var.max_nodes <= 100
    error_message = "Maximum nodes cannot exceed 100"
  }
}

variable "node_disk_size" {
  description = "Disk size in GB for worker nodes (must accommodate container images and volumes)"
  type        = number
  default     = 100
  validation {
    condition     = var.node_disk_size >= 50 && var.node_disk_size <= 500
    error_message = "Node disk size must be between 50 and 500 GB"
  }
}

variable "enable_private_access" {
  description = "Enable private API server endpoint access for enhanced security"
  type        = bool
  default     = true
}

variable "enable_public_access" {
  description = "Enable public API server endpoint access (required for external integrations)"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name for resource tagging and configuration"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

# Additional variables for enhanced security and monitoring
variable "enable_encryption" {
  description = "Enable envelope encryption for Kubernetes secrets using AWS KMS"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain cluster control plane logs"
  type        = number
  default     = 90
  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be one of the allowed CloudWatch Log retention periods"
  }
}

variable "tags" {
  description = "Additional tags for all resources created by this module"
  type        = map(string)
  default     = {}
}

variable "node_labels" {
  description = "Kubernetes labels to apply to all nodes"
  type        = map(string)
  default     = {}
}

variable "node_taints" {
  description = "Kubernetes taints to apply to all nodes"
  type        = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
  validation {
    condition     = alltrue([for t in var.node_taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)])
    error_message = "Node taint effect must be one of: NoSchedule, PreferNoSchedule, NoExecute"
  }
}