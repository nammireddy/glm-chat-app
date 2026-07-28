output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API server endpoint for the EKS cluster."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded certificate authority data for the EKS cluster."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster (used to construct IRSA trust policies)."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "node_role_arn" {
  description = "ARN of the IAM role attached to EKS managed node groups."
  value       = aws_iam_role.node.arn
}

output "system_node_group_id" {
  description = "ID of the system-od managed node group."
  value       = aws_eks_node_group.system_od.id
}

output "karpenter_controller_role_arn" {
  description = "ARN of the Karpenter controller IAM role (IRSA)."
  value       = aws_iam_role.karpenter_controller.arn
}

output "karpenter_node_role_arn" {
  description = "ARN of the Karpenter node IAM role (used by EC2NodeClass instance profile)."
  value       = aws_iam_role.karpenter_node.arn
}
