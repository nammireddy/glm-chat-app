###############################################################################
# IRSA — rag-service
#
# Permissions:
#   - rds-db:connect (scoped to the specific Aurora PostgreSQL cluster ARN)
#
# Requirement: 8.2 — no wildcard actions or resources.
###############################################################################

locals {
  rag_service_sa_name      = "rag-service"
  rag_service_sa_namespace = "default"
}

data "aws_iam_policy_document" "rag_service_trust" {
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
      values   = ["system:serviceaccount:${local.rag_service_sa_namespace}:${local.rag_service_sa_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rag_service" {
  name               = "${var.project}-rag-service-irsa"
  assume_role_policy = data.aws_iam_policy_document.rag_service_trust.json

  tags = merge(var.tags, {
    Project   = var.project
    ManagedBy = "terraform"
  })
}

data "aws_iam_policy_document" "rag_service_permissions" {
  statement {
    sid       = "RDSConnect"
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = [var.aurora_cluster_arn]
  }
}

resource "aws_iam_role_policy" "rag_service" {
  name   = "${var.project}-rag-service-policy"
  role   = aws_iam_role.rag_service.id
  policy = data.aws_iam_policy_document.rag_service_permissions.json
}
