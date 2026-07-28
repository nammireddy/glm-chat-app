###############################################################################
# IRSA — inference-service
#
# Permissions:
#   - s3:GetObject              (scoped to the weights bucket prefix)
#   - elasticfilesystem:ClientMount (scoped to the specific EFS access point)
#
# Requirement: 8.2 — no wildcard actions or resources.
# Requirement: 8.3 — no public access; S3 access restricted to this role.
###############################################################################

locals {
  inference_service_sa_name      = "inference-service"
  inference_service_sa_namespace = "default"
}

data "aws_iam_policy_document" "inference_service_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${local.inference_service_sa_namespace}:${local.inference_service_sa_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "inference_service" {
  name               = "${var.project}-inference-service-irsa"
  assume_role_policy = data.aws_iam_policy_document.inference_service_trust.json

  tags = merge(var.tags, {
    Project   = var.project
    ManagedBy = "terraform"
  })
}

data "aws_iam_policy_document" "inference_service_permissions" {
  statement {
    sid       = "S3GetModelWeights"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.s3_bucket_arn}/*"]
  }

  statement {
    sid       = "EFSClientMount"
    effect    = "Allow"
    actions   = ["elasticfilesystem:ClientMount"]
    resources = [var.efs_access_point_arn]
  }
}

resource "aws_iam_role_policy" "inference_service" {
  name   = "${var.project}-inference-service-policy"
  role   = aws_iam_role.inference_service.id
  policy = data.aws_iam_policy_document.inference_service_permissions.json
}
