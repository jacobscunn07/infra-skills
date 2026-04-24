output "aurora_cluster_endpoint" {
  description = "Writer endpoint of the Aurora cluster."
  value       = module.aurora.cluster_endpoint
}

output "aurora_cluster_reader_endpoint" {
  description = "Read-only endpoint of the Aurora cluster (load-balanced across readers)."
  value       = module.aurora.cluster_reader_endpoint
}

output "aurora_cluster_id" {
  description = "Identifier of the Aurora cluster."
  value       = module.aurora.cluster_id
}

output "aurora_security_group_id" {
  description = "ID of the Aurora security group. Reference this from app security groups to add ingress rules."
  value       = module.aurora.security_group_id
}

output "rds_proxy_endpoint" {
  description = "Endpoint of the RDS Proxy. Use this for all application database connections when proxy is enabled."
  value       = var.enable_rds_proxy ? aws_db_proxy.main[0].endpoint : null
}

output "rds_proxy_security_group_id" {
  description = "ID of the RDS Proxy security group. Add ingress rules from application security groups to allow DB access."
  value       = var.enable_rds_proxy ? aws_security_group.rds_proxy[0].id : null
}

output "db_master_secret_arn" {
  description = "ARN of the RDS-managed Secrets Manager secret holding Aurora master credentials."
  value       = module.aurora.cluster_master_user_secret[0].secret_arn
  sensitive   = true
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for data tier encryption."
  value       = module.kms.key_arn
}

output "kms_key_id" {
  description = "Key ID of the data tier KMS key."
  value       = module.kms.key_id
}

output "app_data_bucket_name" {
  description = "Name of the app data S3 bucket."
  value       = module.s3_app_data.s3_bucket_id
}

output "app_data_bucket_arn" {
  description = "ARN of the app data S3 bucket."
  value       = module.s3_app_data.s3_bucket_arn
}
