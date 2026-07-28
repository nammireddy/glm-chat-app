###############################################################################
# GLM Chat — VPC Endpoints Module
#
# Resources:
#   - S3 Gateway endpoint          (free; eliminates NAT GW data-processing cost
#                                   for ECR layer pulls and model weight downloads)
#   - ECR API interface endpoint   (com.amazonaws.<region>.ecr.api)
#   - ECR DKR interface endpoint   (com.amazonaws.<region>.ecr.dkr)
#   - CloudWatch Logs interface endpoint (com.amazonaws.<region>.logs)
#   - STS interface endpoint       (com.amazonaws.<region>.sts — required for IRSA
#                                   token exchange without traversing NAT GW)
#   - Security group for interface endpoints (port 443 ingress from VPC CIDR only)
#
# Requirements: 8.2, 8.3
###############################################################################

locals {
  common_tags = merge(
    {
      Project   = var.project
      ManagedBy = "terraform"
    },
    var.tags,
  )
}

###############################################################################
# Security Group — Interface Endpoints
#
# Allows HTTPS (443) ingress only from within the VPC CIDR.  All other traffic
# is implicitly denied.  This enforces requirement 8.3 — the inference service
# (and every other VPC workload) can reach AWS APIs without any public internet
# exposure.
###############################################################################

resource "aws_security_group" "endpoints" {
  name        = "${var.project}-sg-vpc-endpoints"
  description = "Allow HTTPS ingress from the VPC to AWS interface endpoints."
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # No explicit egress rule — the default allow-all-egress on a new SG is
  # intentionally overridden by providing an explicit egress block so that
  # the endpoint ENI cannot initiate outbound connections.
  egress {
    description = "Deny all outbound (endpoint ENI is server-side only)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = []
    self        = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-sg-vpc-endpoints"
  })
}

###############################################################################
# S3 Gateway Endpoint
#
# Type: Gateway — routes S3 traffic through AWS backbone at no per-request cost.
# Associating all private route tables means ECR image pulls and model weight
# downloads bypass the NAT Gateways entirely, eliminating NAT data-processing
# charges (requirement 8.3 / cost-optimisation goal).
###############################################################################

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = merge(local.common_tags, {
    Name = "${var.project}-vpce-s3"
  })
}

###############################################################################
# ECR API Interface Endpoint
#
# Used for ECR API calls (DescribeImages, GetAuthorizationToken, etc.).
# Private DNS enabled so the standard AWS SDK endpoint resolves inside the VPC.
###############################################################################

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-vpce-ecr-api"
  })
}

###############################################################################
# ECR DKR Interface Endpoint
#
# Used for Docker Registry v2 calls (layer pulls, manifests).  Combined with the
# S3 Gateway endpoint, image pulls produce zero NAT GW data charges.
###############################################################################

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-vpce-ecr-dkr"
  })
}

###############################################################################
# CloudWatch Logs Interface Endpoint
#
# Fluent Bit and the AWS SDK ship structured logs to CloudWatch Logs Groups
# (/glm-chat/*) over this endpoint, keeping log traffic inside the AWS backbone.
###############################################################################

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-vpce-logs"
  })
}

###############################################################################
# STS Interface Endpoint
#
# Required for IRSA (IAM Roles for Service Accounts): the Kubernetes pod
# web-identity token exchange with STS must resolve to a VPC-internal endpoint
# so that it never traverses a NAT Gateway or the public internet (req 8.2).
###############################################################################

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-vpce-sts"
  })
}
