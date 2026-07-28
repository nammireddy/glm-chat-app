###############################################################################
# GLM Chat — Karpenter IAM Resources
#
# Resources:
#   - Karpenter Controller IAM Role (IRSA) with EC2 fleet/spot permissions
#     scoped to cluster tags (no wildcard resource ARNs where AWS supports
#     resource-level conditions).
#   - KarpenterNodeRole-glm-chat: EC2 instance role for Karpenter-provisioned
#     nodes, with the four standard EKS worker policies attached.
#   - EC2 instance profile wrapping the node role (referenced by EC2NodeClass).
#
# Requirements: 5.1, 5.2, 8.2
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

###############################################################################
# Local helpers
###############################################################################

locals {
  # OIDC provider URL without the "https://" prefix — required for IAM subjects.
  oidc_issuer_host = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")

  karpenter_controller_role_name = "KarpenterControllerRole-${var.cluster_name}"
  karpenter_node_role_name       = "KarpenterNodeRole-${var.cluster_name}"
  karpenter_instance_profile_name = "KarpenterNodeRole-${var.cluster_name}"
}

###############################################################################
# Karpenter Controller Role — IRSA
###############################################################################

# Trust policy: allow the karpenter service account in the karpenter namespace
# to assume this role via OIDC web identity federation.
data "aws_iam_policy_document" "karpenter_controller_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = local.karpenter_controller_role_name
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume_role.json

  tags = merge(local.common_tags, {
    Name = local.karpenter_controller_role_name
  })
}

###############################################################################
# Karpenter Controller Inline Policy
#
# Permissions are scoped as tightly as AWS resource-level conditions allow:
#   - Describe* actions have no resource-level conditions in IAM (AWS limitation),
#     so they are granted on "*".
#   - Mutating actions (RunInstances, CreateFleet, TerminateInstances, etc.) are
#     restricted by tag conditions or explicit ARNs.
###############################################################################

data "aws_iam_policy_document" "karpenter_controller_policy" {

  # --------------------------------------------------------------------------
  # EC2 read-only Describe actions
  # AWS does not support resource-level restrictions for these actions.
  # --------------------------------------------------------------------------
  statement {
    sid    = "EC2DescribeActions"
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
    ]

    resources = ["*"]
  }

  # --------------------------------------------------------------------------
  # RunInstances / CreateFleet — scoped by karpenter.sh/discovery cluster tag
  # --------------------------------------------------------------------------
  statement {
    sid    = "EC2RunInstancesCreateFleet"
    effect = "Allow"

    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
    ]

    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/discovery"
      values   = [var.cluster_name]
    }
  }

  # Allow RunInstances to reference AMIs, subnets, security groups, and
  # launch templates that do not carry the karpenter tag (they carry other
  # cluster tags set by EKS/VPC modules).  These are read-only references
  # within the RunInstances call; actual instance creation is gated above.
  statement {
    sid    = "EC2RunInstancesResources"
    effect = "Allow"

    actions = ["ec2:RunInstances"]

    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}::image/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:subnet/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:security-group/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:launch-template/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:volume/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:spot-instances-request/*",
    ]
  }

  # --------------------------------------------------------------------------
  # TerminateInstances — scoped to instances tagged karpenter.sh/managed-by
  # --------------------------------------------------------------------------
  statement {
    sid    = "EC2TerminateInstances"
    effect = "Allow"

    actions = ["ec2:TerminateInstances"]

    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/karpenter.sh/managed-by"
      values   = [var.cluster_name]
    }
  }

  # --------------------------------------------------------------------------
  # CreateTags — scoped to EC2 instances, fleet requests, and spot requests
  # --------------------------------------------------------------------------
  statement {
    sid    = "EC2CreateTags"
    effect = "Allow"

    actions = ["ec2:CreateTags"]

    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:fleet/*",
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:spot-instances-request/*",
    ]
  }

  # --------------------------------------------------------------------------
  # iam:PassRole — scoped to the Karpenter node role only (req 8.2)
  # --------------------------------------------------------------------------
  statement {
    sid    = "IAMPassRole"
    effect = "Allow"

    actions = ["iam:PassRole"]

    resources = [
      aws_iam_role.karpenter_node.arn,
    ]
  }

  # --------------------------------------------------------------------------
  # eks:DescribeCluster — scoped to this cluster's ARN
  # --------------------------------------------------------------------------
  statement {
    sid    = "EKSDescribeCluster"
    effect = "Allow"

    actions = ["eks:DescribeCluster"]

    resources = [
      "arn:aws:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}",
    ]
  }

  # --------------------------------------------------------------------------
  # ssm:GetParameter — EKS-optimised AMI SSM paths only
  # --------------------------------------------------------------------------
  statement {
    sid    = "SSMGetParameter"
    effect = "Allow"

    actions = ["ssm:GetParameter"]

    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}::parameter/aws/service/eks/optimized-ami/*",
      "arn:aws:ssm:${data.aws_region.current.name}::parameter/aws/service/bottlerocket/*",
    ]
  }

  # --------------------------------------------------------------------------
  # Pricing read — required by Karpenter to estimate node costs for bin-packing
  # AWS Pricing API has no resource-level conditions.
  # --------------------------------------------------------------------------
  statement {
    sid    = "PricingGetProducts"
    effect = "Allow"

    actions = ["pricing:GetProducts"]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name   = "KarpenterControllerPolicy"
  role   = aws_iam_role.karpenter_controller.name
  policy = data.aws_iam_policy_document.karpenter_controller_policy.json
}

###############################################################################
# Karpenter Node Role — KarpenterNodeRole-glm-chat
#
# Attached to EC2 instances launched by Karpenter via the instance profile.
# Requires the same four policies as a standard EKS managed node group role,
# plus SSM for remote access / patch management.
###############################################################################

data "aws_iam_policy_document" "karpenter_node_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "karpenter_node" {
  name               = local.karpenter_node_role_name
  assume_role_policy = data.aws_iam_policy_document.karpenter_node_assume_role.json

  tags = merge(local.common_tags, {
    Name = local.karpenter_node_role_name
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_worker_policy" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni_policy" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr_policy" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm_policy" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

###############################################################################
# EC2 Instance Profile — wraps the node role so EC2 instances can assume it
###############################################################################

resource "aws_iam_instance_profile" "karpenter_node" {
  name = local.karpenter_instance_profile_name
  role = aws_iam_role.karpenter_node.name

  tags = merge(local.common_tags, {
    Name = local.karpenter_instance_profile_name
  })
}
