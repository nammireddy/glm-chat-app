variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "glm-chat"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane (1.30+)."
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "ID of the VPC in which the EKS cluster is created."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS node groups and the control plane ENIs."
  type        = list(string)
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
