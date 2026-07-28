################################################################################
# Aurora PostgreSQL Cluster — pgvector enabled
################################################################################

locals {
  default_tags = {
    Project   = "glm-chat"
    ManagedBy = "terraform"
  }
  tags = merge(local.default_tags, var.tags)
}

# ------------------------------------------------------------------------------
# DB Subnet Group — spans all private subnets
# ------------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-aurora-pg"
  subnet_ids = var.private_subnet_ids

  tags = merge(local.tags, {
    Name = "${var.project}-aurora-pg-subnet-group"
  })
}

# ------------------------------------------------------------------------------
# Cluster Parameter Group — enforce SSL and enable pgvector
# ------------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "this" {
  name   = "${var.project}-aurora-pg16"
  family = "aurora-postgresql16"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pgaudit,pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = merge(local.tags, {
    Name = "${var.project}-aurora-pg16-cluster-params"
  })
}

# ------------------------------------------------------------------------------
# Aurora PostgreSQL Cluster
# ------------------------------------------------------------------------------

resource "aws_rds_cluster" "this" {
  cluster_identifier = "${var.project}-aurora-pg"
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version

  database_name = "glmchat"
  master_username                 = "glmchat_admin"
  manage_master_user_password     = true

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [var.sg_rds_id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  storage_encrypted = true
  # Uses the default AWS-managed KMS key (aws/rds) when kms_key_id is omitted.

  deletion_protection     = var.deletion_protection
  backup_retention_period = var.backup_retention_period
  preferred_backup_window = "03:00-04:00"
  copy_tags_to_snapshot   = true
  skip_final_snapshot     = false
  final_snapshot_identifier = "${var.project}-aurora-pg-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(local.tags, {
    Name = "${var.project}-aurora-pg"
  })
}

# ------------------------------------------------------------------------------
# Cluster Instances — two instances across two AZs
# ------------------------------------------------------------------------------

resource "aws_rds_cluster_instance" "this" {
  count = 2

  identifier         = "${var.project}-aurora-pg-${count.index}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  # Place each instance in a different AZ by referencing different private subnets.
  # Aurora handles AZ placement via the DB subnet group; we explicitly set
  # availability_zone to ensure distribution across two AZs.
  availability_zone = data.aws_subnet.private[count.index].availability_zone

  publicly_accessible  = false
  db_subnet_group_name = aws_db_subnet_group.this.name

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  tags = merge(local.tags, {
    Name = "${var.project}-aurora-pg-${count.index}"
  })
}

# ------------------------------------------------------------------------------
# Data source to resolve AZs from the provided subnet IDs
# ------------------------------------------------------------------------------

data "aws_subnet" "private" {
  count = length(var.private_subnet_ids)
  id    = var.private_subnet_ids[count.index]
}

# ------------------------------------------------------------------------------
# Enhanced Monitoring IAM Role
# ------------------------------------------------------------------------------

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project}-rds-enhanced-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
