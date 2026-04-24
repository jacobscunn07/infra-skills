locals {
  environment = terraform.workspace
  name_prefix = "${var.project}-${local.environment}"
}
