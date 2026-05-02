# Outputs from tf-network-spoke read via SSM
# TODO: Add data blocks for the specific outputs this project needs, e.g.:
#
#   data "aws_ssm_parameter" "vpc_id" {
#     name = "/${var.project}/${local.environment}/network-spoke/vpc_id"
#   }
#
#   data "aws_ssm_parameter" "private_subnet_ids" {
#     name = "/${var.project}/${local.environment}/network-spoke/private_subnet_ids"
#   }
#
# Then decode in locals:
#   locals {
#     vpc_id             = jsondecode(data.aws_ssm_parameter.vpc_id.value)["value"]
#     private_subnet_ids = jsondecode(data.aws_ssm_parameter.private_subnet_ids.value)["value"]
#   }

# Outputs from tf-data read via SSM
# TODO: Add data blocks for the specific outputs this project needs, e.g.:
#
#   data "aws_ssm_parameter" "aurora_cluster_endpoint" {
#     name = "/${var.project}/${local.environment}/data/aurora_cluster_endpoint"
#   }

# TODO: Replace the stub below with module calls. Query the terraform-registry
# MCP (search_modules / get_module_details) for the latest community module
# before writing any raw resource blocks.
