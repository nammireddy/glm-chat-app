###############################################################################
# Security Groups — GLM Chat Application
#
# Groups defined here:
#   sg-alb        — Internet-facing Application Load Balancer
#   sg-chat-svc   — Chat Service pods (FastAPI / Uvicorn on port 8080)
#   sg-rag        — RAG Pipeline pods (referenced by sg-rds)
#   sg-inference  — Inference Service pods (vLLM on port 8000); VPC-only ingress (req 8.3)
#   sg-rds        — Aurora PostgreSQL cluster
#   sg-redis      — ElastiCache Redis cluster
#
# Karpenter EC2NodeClass SG selector tags:
#   karpenter.sh/discovery = var.project          → ALB, chat-svc, inference, rag
#   karpenter.sh/discovery = "${var.project}-gpu" → inference only (GPU NodeClass)
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

# ---------------------------------------------------------------------------
# sg-alb — Internet-facing ALB
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.project}-sg-alb"
  description = "Internet-facing ALB: accepts HTTPS (443) and HTTP (80) from anywhere; forwards to chat-service on 8080."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name                    = "${var.project}-sg-alb"
    "karpenter.sh/discovery" = var.project
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the public internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the public internet (redirected to HTTPS by ALB listener)"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_chat_svc" {
  security_group_id = aws_security_group.alb.id
  description       = "Forward requests to chat-service pods on port 8080"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
}

# ---------------------------------------------------------------------------
# sg-chat-svc — Chat Service pods
# ---------------------------------------------------------------------------
resource "aws_security_group" "chat_svc" {
  name        = "${var.project}-sg-chat-svc"
  description = "Chat Service: accepts traffic from ALB on 8080; reaches Redis (6379), RAG/Scorer/vLLM (VPC)."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name                    = "${var.project}-sg-chat-svc"
    "karpenter.sh/discovery" = var.project
  })
}

resource "aws_vpc_security_group_ingress_rule" "chat_svc_from_alb" {
  security_group_id            = aws_security_group.chat_svc.id
  description                  = "Ingress from ALB on port 8080"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

# Egress: Redis on 6379
resource "aws_vpc_security_group_egress_rule" "chat_svc_to_redis" {
  security_group_id = aws_security_group.chat_svc.id
  description       = "To ElastiCache Redis"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 6379
  to_port           = 6379
  ip_protocol       = "tcp"
}

# Egress: RAG Pipeline on 8002
resource "aws_vpc_security_group_egress_rule" "chat_svc_to_rag" {
  security_group_id = aws_security_group.chat_svc.id
  description       = "To RAG Pipeline service"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 8002
  to_port           = 8002
  ip_protocol       = "tcp"
}

# Egress: Confidence Scorer on 8003
resource "aws_vpc_security_group_egress_rule" "chat_svc_to_scorer" {
  security_group_id = aws_security_group.chat_svc.id
  description       = "To Confidence Scorer service"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 8003
  to_port           = 8003
  ip_protocol       = "tcp"
}

# Egress: vLLM Inference Service on 8000
resource "aws_vpc_security_group_egress_rule" "chat_svc_to_inference" {
  security_group_id = aws_security_group.chat_svc.id
  description       = "To vLLM Inference Service"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 8000
  to_port           = 8000
  ip_protocol       = "tcp"
}

# ---------------------------------------------------------------------------
# sg-rag — RAG Pipeline pods (referenced as ingress source for sg-rds)
# ---------------------------------------------------------------------------
resource "aws_security_group" "rag" {
  name        = "${var.project}-sg-rag"
  description = "RAG Pipeline: accepts traffic from chat-service on 8002; reaches Aurora PG on 5432."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name                    = "${var.project}-sg-rag"
    "karpenter.sh/discovery" = var.project
  })
}

resource "aws_vpc_security_group_ingress_rule" "rag_from_chat_svc" {
  security_group_id            = aws_security_group.rag.id
  description                  = "Ingress from chat-service on port 8002"
  referenced_security_group_id = aws_security_group.chat_svc.id
  from_port                    = 8002
  to_port                      = 8002
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "rag_to_rds" {
  security_group_id = aws_security_group.rag.id
  description       = "To Aurora PostgreSQL (pgvector)"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

# Embedding Service is co-located in the same VPC; allow egress on 8001
resource "aws_vpc_security_group_egress_rule" "rag_to_embed" {
  security_group_id = aws_security_group.rag.id
  description       = "To Embedding Service"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 8001
  to_port           = 8001
  ip_protocol       = "tcp"
}

# ---------------------------------------------------------------------------
# sg-inference — vLLM Inference Service pods
#
# SECURITY REQUIREMENT 8.3: NO ingress rule sourced from 0.0.0.0/0 or ::/0.
# The only allowed ingress is from sg-chat-svc on port 8000 (VPC-internal).
# Egress is limited to the S3 VPC gateway endpoint (HTTPS 443) and EFS (2049).
# ---------------------------------------------------------------------------
resource "aws_security_group" "inference" {
  name        = "${var.project}-sg-inference"
  description = "vLLM Inference: VPC-only ingress from chat-svc on 8000; egress to S3 VPC endpoint and EFS only."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name                     = "${var.project}-sg-inference"
    # Used by both the general Karpenter discovery and the GPU-specific EC2NodeClass
    "karpenter.sh/discovery" = "${var.project}-gpu"
    # Additional tag so the general NodePool subnet/SG selector also matches
    "karpenter.sh/discovery-base" = var.project
  })
}

# Ingress: only from chat-service pods on the vLLM API port — NO public ingress
resource "aws_vpc_security_group_ingress_rule" "inference_from_chat_svc" {
  security_group_id            = aws_security_group.inference.id
  description                  = "VPC-only ingress from chat-service pods on port 8000"
  referenced_security_group_id = aws_security_group.chat_svc.id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

# Egress: S3 VPC Gateway endpoint (HTTPS/443) for model weight downloads
resource "aws_vpc_security_group_egress_rule" "inference_to_s3" {
  security_group_id = aws_security_group.inference.id
  description       = "HTTPS to S3 VPC Gateway endpoint for model weights"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# Egress: EFS mount target (NFS/2049) for weight cache volume
resource "aws_vpc_security_group_egress_rule" "inference_to_efs" {
  security_group_id = aws_security_group.inference.id
  description       = "NFS to EFS mount target for model weight cache"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 2049
  to_port           = 2049
  ip_protocol       = "tcp"
}

# ---------------------------------------------------------------------------
# sg-rds — Aurora PostgreSQL cluster
# ---------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${var.project}-sg-rds"
  description = "Aurora PostgreSQL: accepts connections from RAG Pipeline on 5432; no egress required."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.project}-sg-rds"
  })
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_rag" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL (5432) ingress from RAG Pipeline pods"
  referenced_security_group_id = aws_security_group.rag.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# ---------------------------------------------------------------------------
# sg-redis — ElastiCache Redis cluster
# ---------------------------------------------------------------------------
resource "aws_security_group" "redis" {
  name        = "${var.project}-sg-redis"
  description = "ElastiCache Redis: accepts connections from chat-service on 6379; no egress required."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.project}-sg-redis"
  })
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_chat_svc" {
  security_group_id            = aws_security_group.redis.id
  description                  = "Redis (6379) ingress from chat-service pods"
  referenced_security_group_id = aws_security_group.chat_svc.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}
