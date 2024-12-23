# AWS Provider Configuration
# AWS Provider version ~> 4.0
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Main VPC Resource
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}-vpc"
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# Public Subnets
resource "aws_subnet" "public" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}-public-${var.availability_zones[count.index]}"
      Environment = var.environment
      Type        = "public"
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# Private Subnets
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + length(var.availability_zones))
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}-private-${var.availability_zones[count.index]}"
      Environment = var.environment
      Type        = "private"
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# Database Subnets
resource "aws_subnet" "database" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + (2 * length(var.availability_zones)))
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}-database-${var.availability_zones[count.index]}"
      Environment = var.environment
      Type        = "database"
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}-igw"
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.availability_zones)) : 0
  vpc   = true

  tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}-eip-${count.index + 1}"
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.availability_zones)) : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}-nat-${count.index + 1}"
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )

  depends_on = [aws_internet_gateway.main]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}-public-rt"
      Environment = var.environment
      Type        = "public"
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# Private Route Tables
resource "aws_route_table" "private" {
  count  = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.availability_zones)) : 1
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id
    }
  }

  tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}-private-rt-${count.index + 1}"
      Environment = var.environment
      Type        = "private"
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = var.single_nat_gateway ? aws_route_table.private[0].id : aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "database" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = var.single_nat_gateway ? aws_route_table.private[0].id : aws_route_table.private[count.index].id
}

# Database Subnet Group
resource "aws_db_subnet_group" "database" {
  count       = var.create_database_subnet_group ? 1 : 0
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids  = aws_subnet.database[*].id
  description = "Database subnet group for ${var.project_name} ${var.environment} environment"

  tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}-db-subnet-group"
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# Outputs
output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "List of database subnet IDs"
  value       = aws_subnet.database[*].id
}

output "database_subnet_group_name" {
  description = "Name of the database subnet group"
  value       = try(aws_db_subnet_group.database[0].name, "")
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.main[*].id
}