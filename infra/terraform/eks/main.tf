###############################################################################
# GLM Chat — EKS Module
#
# Resources:
#   - EKS control plane (Kubernetes 1.30+)
#   - Cluster security group and node security group
#   - IAM role for the EKS cluster service role
#   - IAM role for EKS managed node groups
#   - OIDC provider for IRSA (IAM Roles for Service Accounts)
#   - Managed node group "system-od" (m7i.2xlarge, on-demand, min 2 / max 4)
#     — hosts Karpenter controller, CoreDNS, ALB controller, Prometheus, Grafana
#   - Cluster add-ons: CoreDNS, kube-proxy, VPC CNI, EBS CSI driver
#
# Requirements: 5.6
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
# IAM — EKS Cluster Service Role
###############################################################################

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

###############################################################################
# IAM — EKS Node Group Role
# Shared by all managed node groups; Karpenter nodes use their own instance
# profile (KarpenterNodeRole-glm-chat) defined in karpenter_iam.tf (task 3.2).
###############################################################################

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

###############################################################################
# Security Groups
#
# Cluster SG — traffic between the control plane and managed nodes.
# Node SG    — intra-cluster communication between nodes and pods.
###############################################################################

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "EKS control plane security group: allows inbound traffic from node SG."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-cluster-sg"
  })
}

resource "aws_security_group" "node" {
  name        = "${var.cluster_name}-node-sg"
  description = "EKS node security group: allows all intra-cluster communication."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name                     = "${var.cluster_name}-node-sg"
    # Karpenter EC2NodeClass securityGroupSelectorTerms key
    "karpenter.sh/discovery" = var.cluster_name
  })
}

# Allow cluster control plane to receive traffic from nodes (API server kubelet comms)
resource "aws_vpc_security_group_ingress_rule" "cluster_from_node" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "Inbound from node SG (kubelet, metrics-server)"
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
}

# Allow all internal communication between nodes and pods (overlay + CNI)
resource "aws_vpc_security_group_ingress_rule" "node_self" {
  security_group_id            = aws_security_group.node.id
  description                  = "Allow all intra-cluster node-to-node traffic"
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
}

# Allow nodes to receive traffic from the cluster control plane (webhook, kube-proxy, etc.)
resource "aws_vpc_security_group_ingress_rule" "node_from_cluster" {
  security_group_id            = aws_security_group.node.id
  description                  = "Inbound from EKS control plane SG"
  referenced_security_group_id = aws_security_group.cluster.id
  ip_protocol                  = "-1"
}

# Allow all egress from nodes (NAT gateway handles internet egress)
resource "aws_vpc_security_group_egress_rule" "node_egress_all" {
  security_group_id = aws_security_group.node.id
  description       = "Allow all outbound traffic from nodes"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Allow all egress from cluster control plane
resource "aws_vpc_security_group_egress_rule" "cluster_egress_all" {
  security_group_id = aws_security_group.cluster.id
  description       = "Allow all outbound traffic from the EKS control plane"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

###############################################################################
# EKS Cluster
###############################################################################

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true # required for kubectl from outside the VPC
  }

  # Enable control plane logging (audit + API are particularly important for security)
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = merge(local.common_tags, {
    Name                     = var.cluster_name
    # Karpenter uses this tag to discover the cluster (EC2NodeClass clusterName)
    "karpenter.sh/discovery" = var.cluster_name
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
  ]
}

###############################################################################
# OIDC Provider (for IRSA — IAM Roles for Service Accounts)
#
# The TLS certificate thumbprint is fetched directly from the OIDC issuer
# endpoint so it does not need to be hardcoded or manually rotated.
###############################################################################

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-oidc-provider"
  })
}

###############################################################################
# Managed Node Group — system-od
#
# Purpose : hosts system-critical components that must always be available:
#           Karpenter controller, CoreDNS, AWS Load Balancer Controller,
#           Prometheus, and Grafana.
# Instance: m7i.2xlarge (8 vCPU / 32 GiB RAM), on-demand only.
# Capacity: min 2, desired 2, max 4 — spread across private subnets (3 AZs).
###############################################################################

resource "aws_eks_node_group" "system_od" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "system-od"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = ["m7i.2xlarge"]
  capacity_type  = "ON_DEMAND"
  ami_type       = "AL2023_x86_64_STANDARD"
  disk_size      = 50 # GiB, gp3 by default in AL2023

  scaling_config {
    min_size     = 2
    desired_size = 2
    max_size     = 4
  }

  update_config {
    max_unavailable = 1
  }

  # Label nodes so workloads can target the system node group explicitly
  labels = {
    "node-group"                         = "system-od"
    "node.kubernetes.io/node-group-type" = "system"
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-system-od"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
  ]
}

###############################################################################
# Cluster Add-ons
#
# All add-ons use "OVERWRITE" resolve_conflicts_on_update so that Terraform
# can manage add-on configuration without being blocked by field-manager
# conflicts introduced by the EKS console or Helm releases.
#
# resolve_conflicts_on_create = "OVERWRITE" prevents first-apply errors when
# an add-on was pre-installed by the cluster bootstrap.
###############################################################################

# CoreDNS — cluster DNS resolution
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-addon-coredns"
  })

  depends_on = [aws_eks_node_group.system_od]
}

# kube-proxy — per-node network rule maintenance
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-addon-kube-proxy"
  })
}

# VPC CNI — AWS native pod networking
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-addon-vpc-cni"
  })
}

# EBS CSI Driver — persistent volume support via Amazon EBS
# NOTE: Requires an IRSA role with EBS permissions. We create one inline here
# since the addon won't become ACTIVE without it.
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.ebs_csi.arn

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-addon-ebs-csi"
  })

  depends_on = [aws_iam_openid_connect_provider.this, aws_iam_role_policy_attachment.ebs_csi]
}

# IAM role for the EBS CSI driver (IRSA)
resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.this.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.cluster_name}-ebs-csi-role" })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
