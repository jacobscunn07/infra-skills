project     = "myapp"
aws_region  = "us-east-1"
owner       = "platform-team"
cost_center = "eng-platform"

vpc_cidr           = "10.2.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

public_subnet_cidrs   = ["10.2.0.0/24", "10.2.1.0/24", "10.2.2.0/24"]
private_subnet_cidrs  = ["10.2.10.0/24", "10.2.11.0/24", "10.2.12.0/24"]
isolated_subnet_cidrs = ["10.2.20.0/24", "10.2.21.0/24", "10.2.22.0/24"]

# One NAT gateway per AZ for HA.
enable_nat_gateway = true
single_nat_gateway = false

enable_flow_logs        = true
flow_log_retention_days = 90
