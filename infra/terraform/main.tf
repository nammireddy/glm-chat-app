###############################################################################
# Root Terraform Module — GLM Chat Application
###############################################################################

locals {
  common_tags = {
    Project     = var.project
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

module "vpc" {
  source  = "./vpc"
  project = var.project
  region  = var.region
}

module "endpoints" {
  source = "./endpoints"

  vpc_id                  = module.vpc.vpc_id
  vpc_cidr                = module.vpc.vpc_cidr_block
  private_subnet_ids      = module.vpc.private_subnet_ids
  private_route_table_ids = module.vpc.private_route_table_ids
  region                  = var.region
  project                 = var.project
}

module "security_groups" {
  source = "./security_groups"

  vpc_id   = module.vpc.vpc_id
  vpc_cidr = module.vpc.vpc_cidr_block
  project  = var.project
}

# -----------------------------------------------------------------------------
# Compute — EKS
# -----------------------------------------------------------------------------

module "eks" {
  source = "./eks"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  project            = var.project
}

# -----------------------------------------------------------------------------
# TLS Certificate (optional — skip for dev/testing, use ALB URL directly)
# -----------------------------------------------------------------------------

module "acm" {
  source = "./acm"
  count  = var.enable_acm ? 1 : 0

  domain_name       = var.domain_name
  route53_zone_name = var.route53_zone_name
}

# -----------------------------------------------------------------------------
# Data Stores
# -----------------------------------------------------------------------------

module "rds" {
  source = "./rds"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  sg_rds_id          = module.security_groups.sg_rds_id
  project            = var.project
}

module "elasticache" {
  source = "./elasticache"

  private_subnet_ids = module.vpc.private_subnet_ids
  sg_redis_id        = module.security_groups.sg_redis_id
  project            = var.project
}

module "efs" {
  source = "./efs"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  sg_inference_id    = module.security_groups.sg_inference_id
  project            = var.project
}

module "s3" {
  source = "./s3"

  # Break circular dependency: construct the role ARN deterministically
  # since the IRSA module names the role "${var.project}-inference-service-irsa"
  inference_irsa_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-inference-service-irsa"
  project                = var.project
}

# -----------------------------------------------------------------------------
# IAM — IRSA
# -----------------------------------------------------------------------------

module "irsa" {
  source = "./irsa"

  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_issuer_url      = module.eks.cluster_oidc_issuer_url
  cluster_name         = module.eks.cluster_name
  project              = var.project

  # Resource ARNs for scoped policies
  aurora_cluster_arn   = "arn:aws:rds-db:${var.region}:${data.aws_caller_identity.current.account_id}:dbuser:${module.rds.cluster_identifier}/glmchat_admin"
  elasticache_arn      = "arn:aws:elasticache:${var.region}:${data.aws_caller_identity.current.account_id}:replicationgroup:${module.elasticache.replication_group_id}"
  log_group_arn        = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/glm-chat/chat-service"
  efs_access_point_arn = module.efs.access_point_arn
  s3_bucket_arn        = module.s3.bucket_arn
}

# -----------------------------------------------------------------------------
# S3 Bucket Policy (applied after IRSA role exists)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "model_weights" {
  bucket = module.s3.bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowInferenceIRSAGetObject"
        Effect    = "Allow"
        Principal = {
          AWS = module.irsa.inference_service_role_arn
        }
        Action   = "s3:GetObject"
        Resource = "${module.s3.bucket_arn}/*"
      }
    ]
  })

  depends_on = [module.irsa, module.s3]
}
