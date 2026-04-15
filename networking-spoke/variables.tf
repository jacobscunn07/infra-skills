variable "project" {
  type        = string
  description = "Project name used in resource naming and tagging."
}

variable "aws_region" {
  type        = string
  description = "AWS region to deploy resources."
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

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones to deploy subnets into."
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets, one per availability zone."
  default     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets, one per availability zone."
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

variable "isolated_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for isolated (database) subnets, one per availability zone."
  default     = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Whether to create NAT Gateway(s) for private subnet internet access."
  default     = true
}

variable "single_nat_gateway" {
  type        = bool
  description = "Use a single NAT Gateway instead of one per AZ. Reduces cost but is a single point of failure. Suitable for dev/test only."
  default     = false
}

variable "enable_flow_logs" {
  type        = bool
  description = "Whether to enable VPC Flow Logs to CloudWatch."
  default     = true
}

variable "flow_log_retention_days" {
  type        = number
  description = "Number of days to retain VPC Flow Logs in CloudWatch."
  default     = 30
}
