output "cluster_endpoint" {
  description = "Writer endpoint of the Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint of the Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "cluster_identifier" {
  description = "Identifier of the Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.this.cluster_identifier
}

output "master_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the master user credentials (managed rotation)."
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
}
