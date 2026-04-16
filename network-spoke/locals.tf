locals {
  # environment is derived from the Terraform workspace name.
  # Valid workspaces: dev, staging, prod
  # Usage: terraform workspace select dev && terraform apply -var-file=environments/dev/terraform.tfvars
  environment = terraform.workspace
  name_prefix = "${var.project}-${local.environment}"

  common_tags = {
    Project     = var.project
    Environment = local.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
    CostCenter  = var.cost_center
  }
}
