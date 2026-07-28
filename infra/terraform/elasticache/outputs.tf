output "primary_endpoint_address" {
  description = "Primary endpoint address of the Redis replication group."
  value       = aws_elasticache_replication_group.this.configuration_endpoint_address
}

output "reader_endpoint_address" {
  description = "Reader endpoint address of the Redis replication group."
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  description = "Port the Redis cluster listens on."
  value       = aws_elasticache_replication_group.this.port
}

output "replication_group_id" {
  description = "ID of the ElastiCache replication group."
  value       = aws_elasticache_replication_group.this.id
}
