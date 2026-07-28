###############################################################################
# Root Outputs — GLM Chat Application
###############################################################################

# --- EKS ---
output "eks_cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "API server endpoint of the EKS cluster."
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA."
  value       = module.eks.oidc_provider_arn
}

output "karpenter_controller_role_arn" {
  description = "Karpenter controller IAM role ARN."
  value       = module.eks.karpenter_controller_role_arn
}

output "karpenter_node_role_arn" {
  description = "Karpenter node IAM role ARN."
  value       = module.eks.karpenter_node_role_arn
}

# --- ACM ---
output "acm_certificate_arn" {
  description = "ARN of the validated ACM certificate (empty if ACM disabled)."
  value       = var.enable_acm ? module.acm[0].certificate_arn : ""
}

# --- RDS ---
output "rds_cluster_endpoint" {
  description = "Writer endpoint of the Aurora PostgreSQL cluster."
  value       = module.rds.cluster_endpoint
}

output "rds_reader_endpoint" {
  description = "Reader endpoint of the Aurora PostgreSQL cluster."
  value       = module.rds.reader_endpoint
}

# --- ElastiCache (Redis) ---
output "redis_primary_endpoint" {
  description = "Primary endpoint of the Redis replication group."
  value       = module.elasticache.primary_endpoint_address
}

output "redis_reader_endpoint" {
  description = "Reader endpoint of the Redis replication group."
  value       = module.elasticache.reader_endpoint_address
}

output "redis_port" {
  description = "Redis port."
  value       = module.elasticache.port
}

# --- EFS ---
output "efs_file_system_id" {
  description = "EFS file system ID for model weights."
  value       = module.efs.file_system_id
}

output "efs_access_point_id" {
  description = "EFS access point ID for the inference service."
  value       = module.efs.access_point_id
}

# --- S3 ---
output "s3_model_weights_bucket" {
  description = "Name of the S3 bucket for model weights."
  value       = module.s3.bucket_id
}

output "s3_model_weights_bucket_arn" {
  description = "ARN of the model weights S3 bucket."
  value       = module.s3.bucket_arn
}

# --- IRSA Role ARNs ---
output "irsa_chat_service_role_arn" {
  description = "IRSA role ARN for chat-service."
  value       = module.irsa.chat_service_role_arn
}

output "irsa_rag_service_role_arn" {
  description = "IRSA role ARN for rag-service."
  value       = module.irsa.rag_service_role_arn
}

output "irsa_inference_service_role_arn" {
  description = "IRSA role ARN for inference-service."
  value       = module.irsa.inference_service_role_arn
}

# --- ECR Repositories ---
output "ecr_chat_service_url" {
  description = "ECR repository URL for chat-service."
  value       = aws_ecr_repository.chat_service.repository_url
}

output "ecr_inference_service_url" {
  description = "ECR repository URL for inference-service."
  value       = aws_ecr_repository.inference_service.repository_url
}

output "ecr_rag_service_url" {
  description = "ECR repository URL for rag-service."
  value       = aws_ecr_repository.rag_service.repository_url
}

output "ecr_embedding_service_url" {
  description = "ECR repository URL for embedding-service."
  value       = aws_ecr_repository.embedding_service.repository_url
}

output "ecr_confidence_scorer_url" {
  description = "ECR repository URL for confidence-scorer."
  value       = aws_ecr_repository.confidence_scorer.repository_url
}

output "ecr_frontend_url" {
  description = "ECR repository URL for frontend."
  value       = aws_ecr_repository.frontend.repository_url
}

# --- Misc ---
output "region" {
  description = "AWS region."
  value       = var.region
}

output "acm_certificate_domain_name" {
  description = "Domain name of the ACM certificate (empty if ACM disabled)."
  value       = var.enable_acm ? module.acm[0].certificate_domain_name : ""
}
