# Security Baselines

| Field   | Value |
|---------|-------|
| Owner   | Human |
| Purpose | Non-negotiable security constraints Claude must enforce when generating or reviewing Terraform. Before proposing any resource, verify it meets every REQUIRED rule in the relevant section. Flag deviations explicitly — never silently omit a control. |

---

## S3

- **REQUIRED** — All four public access block flags must be `true`:
  ```hcl
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
  ```
- **REQUIRED** — Server-side encryption must be enabled. SSE-KMS with a CMK is preferred; SSE-S3 is acceptable only for non-sensitive, non-application buckets (e.g., logging targets).
- **REQUIRED** — `attach_deny_insecure_transport_policy = true` on all buckets (deny non-TLS requests).
- **REQUIRED** — Versioning enabled on buckets that hold application state, secrets, or Terraform state.

---

## KMS

- **REQUIRED** — Customer-managed keys (CMKs) for Aurora, S3 application buckets, and Secrets Manager. AWS-managed keys (`aws/s3`, `aws/rds`) are not acceptable for production data.
- **REQUIRED** — `enable_key_rotation = true` on every CMK. No exceptions.
- **REQUIRED** — `deletion_window_in_days = 30` minimum on all CMKs.
- Alias naming convention: `alias/<project>-<env>-<descriptor>` (e.g., `alias/myapp-prod-data`).

---

## IAM

- **REQUIRED** — No wildcard (`*`) actions or resources in user-written inline or managed policies. Scope every statement to the minimum required ARN(s).
- **REQUIRED** — Use condition keys (e.g., `kms:ViaService`, `aws:SourceAccount`) to further restrict where broad actions are unavoidable.
- **REQUIRED** — OIDC-based authentication for all CI/CD. No static IAM user credentials or long-lived access keys in GitHub Actions or any automated pipeline.
- **REQUIRED** — OIDC trust policies must include a `sub` condition scoped to at least `repo:<org>/<repo>:*`. Prefer scoping to specific branches or environments for prod roles.
- No `AdministratorAccess` or `PowerUserAccess` attached to roles used by automation. Prefer purpose-built, least-privilege policies.

---

## RDS / Aurora

- **REQUIRED** — `storage_encrypted = true` using a CMK (not the default AWS-managed RDS key).
- **REQUIRED** — `manage_master_user_password = true`. No plaintext passwords in Terraform state, tfvars, or environment variables.
- **REQUIRED** — `publicly_accessible = false`.
- **REQUIRED** — Deletion protection must be enabled in prod: `deletion_protection = local.environment == "prod"`.
- **REQUIRED** — Final snapshots must be kept in prod: `skip_final_snapshot = local.environment != "prod"`.
- **REQUIRED** — CloudWatch Logs export enabled (e.g., `enabled_cloudwatch_logs_exports = ["postgresql"]`).
- Enhanced Monitoring and Performance Insights recommended for prod (preferred).
- Backup retention: minimum 7 days in dev/staging, minimum 14 days in prod.

---

## Security Groups

- **REQUIRED** — No `0.0.0.0/0` or `::/0` ingress on any port except ALB port 80 and 443 for public-facing load balancers.
- **REQUIRED** — Never allow `0.0.0.0/0` ingress on: port 22 (SSH), 5432 (Postgres), 3306 (MySQL), 6379 (Redis), 27017 (MongoDB), or any database port.
- **REQUIRED** — Database-tier and cache-tier security groups must restrict ingress to specific source security group references — never CIDR blocks wider than the VPC.
- Use `create_before_destroy = true` on security groups attached to RDS Proxy or ALB target groups.

---

## Networking

- **REQUIRED** — Database subnets must have no route to an internet gateway. Use isolated subnets with no NAT route for database tiers.
- **REQUIRED** — VPC Flow Logs enabled on every VPC with at minimum 30-day CloudWatch retention.
- NAT Gateway is required for private subnet outbound access. Direct internet gateway routes on private subnets are not acceptable.

---

## Tagging

- **REQUIRED** — Every resource must carry these tags: `Environment`, `Project`, `ManagedBy=terraform`, `Owner`, `CostCenter`.
- **REQUIRED** — Apply via provider-level `default_tags` block. Do not rely on per-resource `tags` arguments as the sole tagging mechanism.
- `copy_tags_to_snapshot = true` on RDS/Aurora to propagate tags to snapshots.

---

## State Backend

- **REQUIRED** — `encrypt = true` on every S3 backend configuration.
- **REQUIRED** — `use_lockfile = true` to prevent concurrent state writes.
- **REQUIRED** — Each project (`tf-*/`) must have its own unique `key` in `backend.tf`. Never share a state file between projects.

---

## Secrets & Hardcoded Values

- **REQUIRED** — No secrets, passwords, or tokens in `.tf` or `.tfvars` files. Use Secrets Manager or SSM Parameter Store references.
- **REQUIRED** — No hardcoded AWS account IDs. Use `data.aws_caller_identity.current.account_id`.
- **REQUIRED** — No hardcoded regions. Use `data.aws_region.current.name` or a variable with a validated default.
- **REQUIRED** — All sensitive Terraform outputs published to SSM as `SecureString` (not `String`).
