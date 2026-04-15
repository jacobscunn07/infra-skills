project     = "myapp"
aws_region  = "us-east-1"
owner       = "platform-team"
cost_center = "eng-platform"

vpc_cidr           = "10.1.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

public_subnet_cidrs   = ["10.1.0.0/24", "10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs  = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]
isolated_subnet_cidrs = ["10.1.20.0/24", "10.1.21.0/24", "10.1.22.0/24"]

# One NAT gateway per AZ for HA.
enable_nat_gateway = true
single_nat_gateway = false

enable_flow_logs        = true
flow_log_retention_days = 30
