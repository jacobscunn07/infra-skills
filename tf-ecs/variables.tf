variable "project" {
  description = "Project name used in resource naming and tagging."
  type        = string
}

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "ssm_region" {
  description = "AWS region for SSM Parameter Store outputs."
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# Project-specific variables — add below
# -----------------------------------------------------------------------------
