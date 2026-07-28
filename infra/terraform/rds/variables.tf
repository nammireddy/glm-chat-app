variable "project" {
  description = "Project name used as a prefix for all resource names."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC in which the Aurora cluster will be placed."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of at least three private subnet IDs. The DB subnet group spans all three; instances are placed in [0] and [1]."
  type        = list(string)
}

variable "sg_rds_id" {
  description = "ID of the sg-rds security group that will be attached to the Aurora cluster."
  type        = string
}

variable "deletion_protection" {
  description = "Whether deletion protection is enabled on the Aurora cluster. Default true for production."
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups."
  type        = number
  default     = 7
}

variable "instance_class" {
  description = "Instance class for Aurora cluster instances."
  type        = string
  default     = "db.r7g.large"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version."
  type        = string
  default     = "16.8"
}

variable "tags" {
  description = "Map of tags to apply to all resources."
  type        = map(string)
  default     = {}
}
