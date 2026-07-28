output "chat_service_role_arn" {
  description = "IAM role ARN for the chat-service Kubernetes service account (IRSA)."
  value       = aws_iam_role.chat_service.arn
}

output "rag_service_role_arn" {
  description = "IAM role ARN for the rag-service Kubernetes service account (IRSA)."
  value       = aws_iam_role.rag_service.arn
}

output "inference_service_role_arn" {
  description = "IAM role ARN for the inference-service Kubernetes service account (IRSA)."
  value       = aws_iam_role.inference_service.arn
}
