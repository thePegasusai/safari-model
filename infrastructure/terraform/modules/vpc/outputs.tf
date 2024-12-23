# VPC Outputs
output "vpc_id" {
  description = "The ID of the created VPC for resource association"
  value       = aws_vpc.main.id
  sensitive   = false
}

output "vpc_cidr" {
  description = "The CIDR block of the created VPC for network planning"
  value       = aws_vpc.main.cidr_block
  sensitive   = true
}

# Subnet ID Outputs
output "public_subnet_ids" {
  description = "List of IDs of public subnets for load balancer and ingress resources"
  value       = aws_subnet.public[*].id
  sensitive   = false
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets for application workloads"
  value       = aws_subnet.private[*].id
  sensitive   = false
}

output "database_subnet_ids" {
  description = "List of IDs of database subnets for data tier isolation"
  value       = aws_subnet.database[*].id
  sensitive   = false
}

# Subnet CIDR Outputs
output "public_subnet_cidrs" {
  description = "List of CIDR blocks of public subnets for network security planning"
  value       = aws_subnet.public[*].cidr_block
  sensitive   = true
}

output "private_subnet_cidrs" {
  description = "List of CIDR blocks of private subnets for network security planning"
  value       = aws_subnet.private[*].cidr_block
  sensitive   = true
}

output "database_subnet_cidrs" {
  description = "List of CIDR blocks of database subnets for network security planning"
  value       = aws_subnet.database[*].cidr_block
  sensitive   = true
}

# Availability Zone Output
output "availability_zones" {
  description = "List of availability zones where subnets are created for HA planning"
  value       = aws_subnet.public[*].availability_zone
  sensitive   = false
}

# Database Subnet Group Output
output "database_subnet_group_name" {
  description = "Name of the database subnet group for RDS instance deployment"
  value       = try(aws_db_subnet_group.database[0].name, "")
  sensitive   = false
}

# NAT Gateway Outputs
output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs for private subnet internet access"
  value       = aws_nat_gateway.main[*].id
  sensitive   = false
}

# Route Table Outputs
output "public_route_table_id" {
  description = "ID of the public route table for custom route management"
  value       = aws_route_table.public.id
  sensitive   = false
}

output "private_route_table_ids" {
  description = "List of private route table IDs for custom route management"
  value       = aws_route_table.private[*].id
  sensitive   = false
}

# Composite Output for Module Integration
output "vpc_outputs" {
  description = "Combined VPC outputs for module integration"
  value = {
    vpc_id = aws_vpc.main.id
    subnet_ids = {
      public    = aws_subnet.public[*].id
      private   = aws_subnet.private[*].id
      database  = aws_subnet.database[*].id
    }
    subnet_cidrs = {
      public    = aws_subnet.public[*].cidr_block
      private   = aws_subnet.private[*].cidr_block
      database  = aws_subnet.database[*].cidr_block
    }
    availability_zones = aws_subnet.public[*].availability_zone
    nat_gateway_ids   = aws_nat_gateway.main[*].id
    route_table_ids = {
      public  = aws_route_table.public.id
      private = aws_route_table.private[*].id
    }
  }
  sensitive = true
}