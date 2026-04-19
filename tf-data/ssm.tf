# ─── SSM OUTPUT PUBLISHING ───────────────────────────────────────────────────
#
# All Terraform outputs are mirrored to SSM Parameter Store so that any
# consumer — another Terraform project, a CDK app, a shell script — can
# retrieve them without depending on the Terraform state backend.
#
# Path convention: /<project>/<environment>/<component>/<output-name>
# Example:         /myapp/prod/data/aurora_cluster_endpoint
#
# Encoding convention:
#   - All values are JSON-encoded for type-safe, consistent parsing.
#   - Single values:  { "value": "<output>" }
#   - Lists / maps:   native JSON array / object

locals {
  ssm_prefix = "/${var.project}/${local.environment}/data"
}

# ─── Aurora ──────────────────────────────────────────────────────────────────

resource "aws_ssm_parameter" "aurora_cluster_endpoint" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/aurora_cluster_endpoint"
  type     = "String"
  value    = jsonencode({ value = module.aurora.cluster_endpoint })
}

resource "aws_ssm_parameter" "aurora_cluster_reader_endpoint" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/aurora_cluster_reader_endpoint"
  type     = "String"
  value    = jsonencode({ value = module.aurora.cluster_reader_endpoint })
}

resource "aws_ssm_parameter" "aurora_cluster_id" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/aurora_cluster_id"
  type     = "String"
  value    = jsonencode({ value = module.aurora.cluster_id })
}

resource "aws_ssm_parameter" "aurora_security_group_id" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/aurora_security_group_id"
  type     = "String"
  value    = jsonencode({ value = module.aurora.security_group_id })
}

# ─── RDS Proxy (conditional) ─────────────────────────────────────────────────

resource "aws_ssm_parameter" "rds_proxy_endpoint" {
  count = var.enable_rds_proxy ? 1 : 0

  provider = aws.ssm
  name     = "${local.ssm_prefix}/rds_proxy_endpoint"
  type     = "String"
  value    = jsonencode({ value = aws_db_proxy.main[0].endpoint })
}

resource "aws_ssm_parameter" "rds_proxy_security_group_id" {
  count = var.enable_rds_proxy ? 1 : 0

  provider = aws.ssm
  name     = "${local.ssm_prefix}/rds_proxy_security_group_id"
  type     = "String"
  value    = jsonencode({ value = aws_security_group.rds_proxy[0].id })
}

# ─── KMS ─────────────────────────────────────────────────────────────────────

resource "aws_ssm_parameter" "kms_key_arn" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/kms_key_arn"
  type     = "String"
  value    = jsonencode({ value = module.kms.key_arn })
}

resource "aws_ssm_parameter" "kms_key_id" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/kms_key_id"
  type     = "String"
  value    = jsonencode({ value = module.kms.key_id })
}

# ─── Secrets ─────────────────────────────────────────────────────────────────

resource "aws_ssm_parameter" "db_master_secret_arn" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/db_master_secret_arn"
  type     = "SecureString"
  value    = jsonencode({ value = module.aurora.cluster_master_user_secret[0].secret_arn })
}

# ─── S3 ──────────────────────────────────────────────────────────────────────

resource "aws_ssm_parameter" "app_data_bucket_name" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/app_data_bucket_name"
  type     = "String"
  value    = jsonencode({ value = module.s3_app_data.s3_bucket_id })
}

resource "aws_ssm_parameter" "app_data_bucket_arn" {
  provider = aws.ssm
  name     = "${local.ssm_prefix}/app_data_bucket_arn"
  type     = "String"
  value    = jsonencode({ value = module.s3_app_data.s3_bucket_arn })
}
