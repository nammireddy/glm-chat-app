variable "vpc_id" {
  description = "ID of the VPC in which to create the security groups."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC; used to scope egress rules to VPC-internal traffic."
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
