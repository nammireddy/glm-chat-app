###############################################################################
# Shared variables
###############################################################################

variable "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for the EKS cluster."
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster (e.g. https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE)."
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "project" {
  description = "Project name used for tagging and resource naming."
  type        = string
  default     = "glm-chat"
}

variable "tags" {
  description = "Additional tags to merge onto all resources."
  type        = map(string)
  default     = {}
}

###############################################################################
# Resource-specific ARNs
###############################################################################

variable "elasticache_arn" {
  description = "ARN of the ElastiCache Redis replication group (used by chat-service)."
  type        = string
}

variable "log_group_arn" {
  description = "ARN of the CloudWatch Log Group for the chat-service (e.g. arn:aws:logs:us-east-1:123456789012:log-group:/glm-chat/chat-service)."
  type        = string
}

variable "aurora_cluster_arn" {
  description = "ARN of the Aurora PostgreSQL cluster (used by rag-service)."
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing model weights (used by inference-service)."
  type        = string
}

variable "efs_access_point_arn" {
  description = "ARN of the EFS access point for the inference service."
  type        = string
}
