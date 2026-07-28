output "sg_alb_id" {
  description = "ID of the ALB security group (sg-alb)."
  value       = aws_security_group.alb.id
}

output "sg_chat_svc_id" {
  description = "ID of the Chat Service security group (sg-chat-svc)."
  value       = aws_security_group.chat_svc.id
}

output "sg_rag_id" {
  description = "ID of the RAG Pipeline security group (sg-rag)."
  value       = aws_security_group.rag.id
}

output "sg_inference_id" {
  description = "ID of the Inference Service security group (sg-inference). No public ingress — req 8.3."
  value       = aws_security_group.inference.id
}

output "sg_rds_id" {
  description = "ID of the Aurora PostgreSQL security group (sg-rds)."
  value       = aws_security_group.rds.id
}

output "sg_redis_id" {
  description = "ID of the ElastiCache Redis security group (sg-redis)."
  value       = aws_security_group.redis.id
}
