locals {
  default_tags = {
    Project   = "glm-chat"
    ManagedBy = "terraform"
  }
  tags = merge(local.default_tags, var.tags)
}

# ------------------------------------------------------------------------------
# Subnet Group — spans all three private subnets
# ------------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = local.tags
}

# ------------------------------------------------------------------------------
# ElastiCache Redis Replication Group
# Engine 7.x, single shard (1 primary + 1 replica), Multi-AZ, encryption enabled
# ------------------------------------------------------------------------------
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.project}-redis"
  description          = "Redis cluster for ${var.project} session store"

  engine         = "redis"
  engine_version = "7.1"
  port           = 6379
  node_type      = "cache.r7g.large"

  # Single shard with one read replica (cluster mode disabled)
  num_node_groups         = 1
  replicas_per_node_group = 1

  # Multi-AZ with automatic failover
  automatic_failover_enabled = true
  multi_az_enabled           = true

  # Networking
  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.sg_redis_id]

  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  # Maintenance and snapshots
  maintenance_window       = "sun:05:00-sun:06:00"
  snapshot_retention_limit = 1

  tags = local.tags
}
