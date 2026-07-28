###############################################################################
# GLM Chat — VPC Module
#
# Resources:
#   - VPC (10.0.0.0/16)
#   - 3 Public  subnets across us-east-1a/b/c  (ALB, NAT GW)
#   - 3 Private subnets across us-east-1a/b/c  (EKS nodes, RDS, ElastiCache)
#   - Internet Gateway
#   - 1 Elastic IP + NAT Gateway per AZ (high-availability egress)
#   - Public  route table (default route → IGW)
#   - Private route tables (one per AZ, default route → AZ-local NAT GW)
#
# Requirements: 5.1, 5.6
###############################################################################

locals {
  common_tags = merge(
    {
      Project              = var.project
      ManagedBy            = "terraform"
    },
    var.tags,
  )
}

###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name                    = "${var.project}-vpc"
    # Karpenter uses this tag to discover the VPC's subnets for node provisioning
    "karpenter.sh/discovery" = var.project
  })
}

###############################################################################
# Internet Gateway
###############################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.project}-igw"
  })
}

###############################################################################
# Public Subnets
###############################################################################

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-public-${var.availability_zones[count.index]}"
    Tier = "public"
    # Required by AWS Load Balancer Controller for internet-facing ALB discovery
    "kubernetes.io/role/elb" = "1"
  })
}

###############################################################################
# Private Subnets
###############################################################################

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.project}-private-${var.availability_zones[count.index]}"
    Tier = "private"
    # Required by AWS Load Balancer Controller for internal ALB discovery
    "kubernetes.io/role/internal-elb" = "1"
    # Karpenter EC2NodeClass subnetSelectorTerms key — used to place GPU nodes
    "karpenter.sh/discovery"           = var.project
  })
}

###############################################################################
# Elastic IPs for NAT Gateways (one per AZ)
###############################################################################

resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project}-eip-nat-${var.availability_zones[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# NAT Gateways — one per AZ for high-availability egress (req 5.6)
###############################################################################

resource "aws_nat_gateway" "this" {
  count = length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${var.project}-nat-${var.availability_zones[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# Public Route Table
# One shared table: default route → Internet Gateway
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-rtb-public"
  })
}

resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

###############################################################################
# Private Route Tables
# One per AZ: default route → AZ-local NAT Gateway (ensures traffic stays
# within the same AZ to avoid cross-AZ data transfer charges and to maintain
# availability if a single NAT GW is disrupted)
###############################################################################

resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-rtb-private-${var.availability_zones[count.index]}"
  })
}

resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
