# TODO: Add outputs here. Mirror each output to SSM in ssm.tf using the pattern:
#
#   resource "aws_ssm_parameter" "<output_name>" {
#     provider = aws.ssm
#     name     = "${local.ssm_prefix}/<output_name>"
#     type     = "String"
#     value    = jsonencode({ value = <module_or_resource>.<output_name> })
#   }
#
# For sensitive values (ARNs, secrets), use type = "SecureString".
