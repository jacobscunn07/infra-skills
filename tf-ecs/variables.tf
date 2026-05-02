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

# ─── IAM ─────────────────────────────────────────────────────────────────────

variable "aws_profile" {
  type        = string
  description = "AWS config profile for the main provider. Matches a profile in .github/.aws/config (CI) or ~/.aws/config (local)."
}

variable "ssm_profile" {
  type        = string
  description = "AWS config profile for the SSM provider alias. Shared across all workspaces — default set by setup script."
  default     = "REPLACE_WITH_SSM_PROFILE"
}

# -----------------------------------------------------------------------------
# Project-specific variables — add below
# -----------------------------------------------------------------------------
