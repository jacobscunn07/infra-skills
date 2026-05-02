locals {
  ssm_prefix = "/${var.project}/${local.environment}/ecs"
}

# TODO: Add one aws_ssm_parameter resource per output. See outputs.tf for the pattern.
