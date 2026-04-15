# ─── SSM OUTPUT PUBLISHING ───────────────────────────────────────────────────
#
# All Terraform outputs are mirrored to SSM Parameter Store so that any
# consumer — another Terraform project, a CDK app, a shell script — can
# retrieve them without depending on the Terraform state backend.
#
# Path convention: /<project>/<environment>/<component>/<output-name>
# Example:         /myapp/prod/networking-spoke/vpc_id

locals {
  ssm_prefix = "/${var.project}/${local.environment}/networking-spoke"
}

resource "aws_ssm_parameter" "vpc_id" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/vpc_id"
  type     = "String"
  value    = module.vpc.vpc_id
}

resource "aws_ssm_parameter" "vpc_cidr_block" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/vpc_cidr_block"
  type     = "String"
  value    = module.vpc.vpc_cidr_block
}

resource "aws_ssm_parameter" "internet_gateway_id" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/internet_gateway_id"
  type     = "String"
  value    = module.vpc.igw_id
}

# Lists are stored as comma-separated strings for broad compatibility.
resource "aws_ssm_parameter" "public_subnet_ids" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/public_subnet_ids"
  type     = "StringList"
  value    = join(",", module.vpc.public_subnets)
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/private_subnet_ids"
  type     = "StringList"
  value    = join(",", module.vpc.private_subnets)
}

resource "aws_ssm_parameter" "isolated_subnet_ids" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/isolated_subnet_ids"
  type     = "StringList"
  value    = join(",", module.vpc.database_subnets)
}

resource "aws_ssm_parameter" "nat_gateway_ids" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/nat_gateway_ids"
  type     = "StringList"
  value    = join(",", module.vpc.natgw_ids)
}

# Maps are JSON-encoded so the structure is preserved.
resource "aws_ssm_parameter" "public_subnet_ids_by_az" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/public_subnet_ids_by_az"
  type     = "String"
  value    = jsonencode(zipmap(var.availability_zones, module.vpc.public_subnets))
}

resource "aws_ssm_parameter" "private_subnet_ids_by_az" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/private_subnet_ids_by_az"
  type     = "String"
  value    = jsonencode(zipmap(var.availability_zones, module.vpc.private_subnets))
}

resource "aws_ssm_parameter" "isolated_subnet_ids_by_az" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/isolated_subnet_ids_by_az"
  type     = "String"
  value    = jsonencode(zipmap(var.availability_zones, module.vpc.database_subnets))
}
