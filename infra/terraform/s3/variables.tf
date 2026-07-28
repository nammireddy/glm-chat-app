variable "project" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "glm-chat"
}

variable "inference_irsa_role_arn" {
  description = "ARN of the inference service IRSA role allowed to read model weights."
  type        = string
}

variable "tags" {
  description = "Additional tags to merge onto all resources."
  type        = map(string)
  default     = {}
}
