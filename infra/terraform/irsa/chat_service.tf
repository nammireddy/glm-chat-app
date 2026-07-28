###############################################################################
# IRSA — chat-service
#
# Permissions:
#   - elasticache:Connect  (scoped to the specific ElastiCache replication group)
#   - logs:PutLogEvents    (scoped to the specific CloudWatch Log Group)
#   - logs:CreateLogStream (scoped to the specific CloudWatch Log Group)
#
# Requirement: 8.2 — no wildcard actions or resources.
###############################################################################

locals {
  chat_service_sa_name      = "chat-service"
  chat_service_sa_namespace = "default"
  oidc_issuer               = replace(var.oidc_issuer_url, "https://", "")
}

data "aws_iam_policy_document" "chat_service_trust" {
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
      values   = ["system:serviceaccount:${local.chat_service_sa_namespace}:${local.chat_service_sa_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "chat_service" {
  name               = "${var.project}-chat-service-irsa"
  assume_role_policy = data.aws_iam_policy_document.chat_service_trust.json

  tags = merge(var.tags, {
    Project   = var.project
    ManagedBy = "terraform"
  })
}

data "aws_iam_policy_document" "chat_service_permissions" {
  statement {
    sid       = "ElastiCacheConnect"
    effect    = "Allow"
    actions   = ["elasticache:Connect"]
    resources = [var.elasticache_arn]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream",
    ]
    resources = [
      var.log_group_arn,
      "${var.log_group_arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "chat_service" {
  name   = "${var.project}-chat-service-policy"
  role   = aws_iam_role.chat_service.id
  policy = data.aws_iam_policy_document.chat_service_permissions.json
}
