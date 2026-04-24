variable "project" {
  type        = string
  description = "Project name used in resource naming and tagging."
}

variable "aws_region" {
  type        = string
  description = "AWS region to deploy resources."
  default     = "us-east-1"
}

variable "ssm_region" {
  type        = string
  description = "AWS region for SSM Parameter Store output publishing. Defaults to the deployment region. Override to write outputs to a central/shared region."
  default     = "us-east-1"
}

variable "owner" {
  type        = string
  description = "Team or individual responsible for this infrastructure."
}

variable "cost_center" {
  type        = string
  description = "Cost center for billing attribution."
}

# ─── Networking remote state ─────────────────────────────────────────────────

variable "networking_state_bucket" {
  type        = string
  description = "S3 bucket containing the network-spoke Terraform state."
}

variable "networking_state_region" {
  type        = string
  description = "Region of the network-spoke state bucket."
  default     = "us-east-1"
}

# ─── Aurora ──────────────────────────────────────────────────────────────────

variable "db_name" {
  type        = string
  description = "Name of the initial database created in the Aurora cluster."
  default     = "appdb"
}

variable "db_master_username" {
  type        = string
  description = "Master username for the Aurora cluster."
  default     = "dbadmin"
}

variable "aurora_engine_version" {
  type        = string
  description = "Aurora PostgreSQL engine version."
  default     = "16.4"
}

variable "aurora_min_capacity" {
  type        = number
  description = "Minimum Aurora Serverless v2 capacity in ACUs (0.5 increments). Use 0 only for dev/test scale-to-zero."
  default     = 0.5
}

variable "aurora_max_capacity" {
  type        = number
  description = "Maximum Aurora Serverless v2 capacity in ACUs."
  default     = 8
}

variable "backup_retention_period" {
  type        = number
  description = "Number of days to retain automated Aurora backups (1–35)."
  default     = 7
}

variable "aurora_allowed_sg_ids" {
  type        = list(string)
  description = "Security group IDs allowed to connect to Aurora (or the RDS Proxy) on port 5432."
  default     = []
}

# ─── RDS Proxy ───────────────────────────────────────────────────────────────

variable "enable_rds_proxy" {
  type        = bool
  description = "Whether to create an RDS Proxy in front of the Aurora cluster. Recommended for Lambda/serverless workloads."
  default     = true
}

# ─── S3 ──────────────────────────────────────────────────────────────────────

variable "app_data_bucket_suffix" {
  type        = string
  description = "Unique suffix appended to the app data S3 bucket name (e.g. account ID last 6 digits)."
}
