variable "private_subnet_ids" {
  description = "List of private subnet IDs for the ElastiCache subnet group."
  type        = list(string)
}

variable "sg_redis_id" {
  description = "Security group ID for the Redis cluster (sg-redis)."
  type        = string
}

variable "project" {
  description = "Project name used for resource naming."
  type        = string
  default     = "glm-chat"
}

variable "tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}
