# ─── REMOTE STATE ────────────────────────────────────────────────────────────

data "terraform_remote_state" "networking" {
  backend   = "s3"
  workspace = terraform.workspace

  config = {
    bucket = var.networking_state_bucket
    key    = "network-spoke/terraform.tfstate"
    region = var.networking_state_region
  }
}

data "aws_caller_identity" "current" {}

# ─── KMS KEY ─────────────────────────────────────────────────────────────────

module "kms" {
  # terraform-aws-modules/kms/aws v4.2.0
  source = "github.com/terraform-aws-modules/terraform-aws-kms?ref=407e3db34a65b384c20ef718f55d9ceacb97a846"

  description             = "Encryption key for ${local.name_prefix} data tier (Aurora, S3)"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # enable_default_policy = true (the default) grants the root account full kms:* access.

  # computed_aliases is used instead of aliases because the name contains a computed local.
  computed_aliases = {
    main = { name = "alias/${local.name_prefix}-data" }
  }

  tags = local.common_tags
}

# ─── AURORA CLUSTER (SERVERLESS V2, POSTGRESQL) ──────────────────────────────

module "aurora" {
  # terraform-aws-modules/rds-aurora/aws v10.2.0
  source = "github.com/terraform-aws-modules/terraform-aws-rds-aurora?ref=2c3946c8191278ad974bbb077da5e03986e24f4d"

  name           = "${local.name_prefix}-aurora"
  engine         = "aurora-postgresql"
  engine_version = var.aurora_engine_version

  vpc_id  = data.terraform_remote_state.networking.outputs.vpc_id
  subnets = data.terraform_remote_state.networking.outputs.isolated_subnet_ids

  master_username             = var.db_master_username
  manage_master_user_password = true

  storage_encrypted = true
  kms_key_id        = module.kms.key_arn

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  copy_tags_to_snapshot     = true
  skip_final_snapshot       = local.environment != "prod"
  final_snapshot_identifier = "${local.name_prefix}-aurora-final-snapshot"

  deletion_protection = local.environment == "prod"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  serverlessv2_scaling_configuration = {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }

  instances = {
    writer = {
      instance_class                        = "db.serverless"
      publicly_accessible                   = false
      monitoring_interval                   = 60
      performance_insights_enabled          = true
      performance_insights_kms_key_id       = module.kms.key_arn
      performance_insights_retention_period = 7
    }
  }

  create_monitoring_role = true

  # When proxy is enabled, only the proxy SG may reach Aurora.
  # When proxy is disabled, allowed app SGs connect directly.
  security_group_ingress_rules = var.enable_rds_proxy ? {
    from_proxy = {
      description                  = "Allow PostgreSQL from RDS Proxy"
      from_port                    = 5432
      to_port                      = 5432
      ip_protocol                  = "tcp"
      referenced_security_group_id = aws_security_group.rds_proxy[0].id
    }
    } : { for sg_id in var.aurora_allowed_sg_ids : sg_id => {
      description                  = "Allow PostgreSQL from application security group"
      from_port                    = 5432
      to_port                      = 5432
      ip_protocol                  = "tcp"
      referenced_security_group_id = sg_id
  } }

  apply_immediately = local.environment != "prod"

  tags = local.common_tags
}

# ─── RDS PROXY SECURITY GROUP ────────────────────────────────────────────────

resource "aws_security_group" "rds_proxy" {
  count = var.enable_rds_proxy ? 1 : 0

  name        = "${local.name_prefix}-sg-rds-proxy"
  description = "Controls inbound access to the RDS Proxy"
  vpc_id      = data.terraform_remote_state.networking.outputs.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sg-rds-proxy"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_proxy_from_app" {
  for_each = var.enable_rds_proxy ? toset(var.aurora_allowed_sg_ids) : toset([])

  security_group_id            = aws_security_group.rds_proxy[0].id
  description                  = "Allow PostgreSQL from application security group"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value
}

# ─── RDS PROXY ───────────────────────────────────────────────────────────────

resource "aws_iam_role" "rds_proxy" {
  count = var.enable_rds_proxy ? 1 : 0

  name = "${local.name_prefix}-role-rds-proxy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "rds_proxy_secrets" {
  count = var.enable_rds_proxy ? 1 : 0

  name = "${local.name_prefix}-policy-rds-proxy-secrets"
  role = aws_iam_role.rds_proxy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [module.aurora.cluster_master_user_secret[0].secret_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [module.kms.key_arn]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_db_proxy" "main" {
  count = var.enable_rds_proxy ? 1 : 0

  name                = "${local.name_prefix}-rds-proxy"
  debug_logging       = false
  engine_family       = "POSTGRESQL"
  idle_client_timeout = 1800
  require_tls         = true
  role_arn            = aws_iam_role.rds_proxy[0].arn

  # Proxy lives in private subnets; Aurora lives in isolated subnets.
  vpc_security_group_ids = [aws_security_group.rds_proxy[0].id]
  vpc_subnet_ids         = data.terraform_remote_state.networking.outputs.private_subnet_ids

  auth {
    auth_scheme = "SECRETS"
    description = "Aurora master credentials (RDS-managed)"
    iam_auth    = "DISABLED"
    secret_arn  = module.aurora.cluster_master_user_secret[0].secret_arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-proxy"
  })
}

resource "aws_db_proxy_default_target_group" "main" {
  count = var.enable_rds_proxy ? 1 : 0

  db_proxy_name = aws_db_proxy.main[0].name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 100
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "main" {
  count = var.enable_rds_proxy ? 1 : 0

  db_proxy_name         = aws_db_proxy.main[0].name
  target_group_name     = aws_db_proxy_default_target_group.main[0].name
  db_cluster_identifier = module.aurora.cluster_id
}

# ─── S3 APP DATA BUCKET ──────────────────────────────────────────────────────

module "s3_app_data" {
  # terraform-aws-modules/s3-bucket/aws v5.12.0
  source = "github.com/terraform-aws-modules/terraform-aws-s3-bucket?ref=6c5e082b5d2fde77cb59c387a7f553dd2ed5da29"

  bucket = "${local.name_prefix}-app-data-${var.app_data_bucket_suffix}"

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = module.kms.key_arn
      }
      # Bucket keys reduce per-object KMS API calls by up to 99%.
      bucket_key_enabled = true
    }
  }

  # All public access blocked (these are the module defaults, stated explicitly).
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true

  # Deny non-TLS requests — replaces the manual aws_s3_bucket_policy DenyNonTLS statement.
  attach_deny_insecure_transport_policy = true

  lifecycle_rule = [
    {
      id     = "tiering-and-cleanup"
      status = "Enabled"

      transition = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]

      noncurrent_version_expiration = {
        noncurrent_days           = 30
        newer_noncurrent_versions = 3
      }

      abort_incomplete_multipart_upload = {
        days_after_initiation = 7
      }
    }
  ]

  tags = local.common_tags
}
