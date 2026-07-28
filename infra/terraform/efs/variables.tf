variable "vpc_id" {
  description = "ID of the VPC where the EFS security group will be created."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EFS mount targets (one per AZ)."
  type        = list(string)
}

variable "sg_inference_id" {
  description = "Security group ID of the inference service; used to allow NFS ingress."
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
