variable "vpc_id" {
  description = "ID of the VPC in which to create the endpoints."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC; used to scope the endpoint security group ingress rule."
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets used to place interface endpoint ENIs (one per AZ)."
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "IDs of the per-AZ private route tables to associate with the S3 Gateway endpoint."
  type        = list(string)
}

variable "project" {
  description = "Project name used for tagging and resource naming."
  type        = string
  default     = "glm-chat"
}

variable "region" {
  description = "AWS region; used to build the endpoint service names."
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Additional tags to merge onto all resources."
  type        = map(string)
  default     = {}
}
