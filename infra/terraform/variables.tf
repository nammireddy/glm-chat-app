###############################################################################
# Root-level Variables
###############################################################################

variable "project" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "glm-chat"
}

variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Primary domain name for the chat application. Leave empty to use ALB auto-generated URL."
  type        = string
  default     = ""
}

variable "route53_zone_name" {
  description = "Route53 hosted zone name for DNS validation. Leave empty to skip ACM certificate."
  type        = string
  default     = ""
}

variable "enable_acm" {
  description = "Whether to create an ACM certificate and Route53 validation. Set false to use ALB URL directly."
  type        = bool
  default     = false
}
