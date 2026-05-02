# Local AWS Credentials Setup

Reference for configuring your local AWS credentials to run Terraform in this repo. Profile names in `~/.aws/config` must match the profile names in [`.github/.aws/config`](../../.github/.aws/config) exactly — Terraform selects profiles by name from `aws_profile` in each workspace's `terraform.tfvars`.

---

## Profile Name Reference

| Profile | Role | Used by |
|---|---|---|
| `terraform-backend` | Shared backend role | All projects — `backend.tf` |
| `terraform-ssm` | Shared SSM role | All projects — `aws.ssm` provider alias |
| `tf-network-spoke-dev` | Deploy role, dev account | `tf-network-spoke` / dev workspace |
| `tf-network-spoke-staging` | Deploy role, staging account | `tf-network-spoke` / staging workspace |
| `tf-network-spoke-prod` | Deploy role, prod account | `tf-network-spoke` / prod workspace |
| `tf-data-dev` | Deploy role, dev account | `tf-data` / dev workspace |
| `tf-data-staging` | Deploy role, staging account | `tf-data` / staging workspace |
| `tf-data-prod` | Deploy role, prod account | `tf-data` / prod workspace |

Role ARNs for each profile are documented in [`.claude/memory/aws-account-map.md`](../../.claude/memory/aws-account-map.md).

---

## `~/.aws/config` Profiles

Add the following blocks to your `~/.aws/config`. Replace `source_profile` with your local base profile (see credential source patterns below).

```ini
# ── Shared roles ──────────────────────────────────────────────────────────────

[profile terraform-backend]
role_arn       = REPLACE_WITH_BACKEND_ROLE_ARN
source_profile = REPLACE_WITH_YOUR_BASE_PROFILE

[profile terraform-ssm]
role_arn       = REPLACE_WITH_SSM_ROLE_ARN
source_profile = REPLACE_WITH_YOUR_BASE_PROFILE

# ── tf-network-spoke ──────────────────────────────────────────────────────────

[profile tf-network-spoke-dev]
role_arn       = REPLACE_WITH_TF_NETWORK_SPOKE_DEV_ROLE_ARN
source_profile = REPLACE_WITH_YOUR_BASE_PROFILE

[profile tf-network-spoke-staging]
role_arn       = REPLACE_WITH_TF_NETWORK_SPOKE_STAGING_ROLE_ARN
source_profile = REPLACE_WITH_YOUR_BASE_PROFILE

[profile tf-network-spoke-prod]
role_arn       = REPLACE_WITH_TF_NETWORK_SPOKE_PROD_ROLE_ARN
source_profile = REPLACE_WITH_YOUR_BASE_PROFILE

# ── tf-data ───────────────────────────────────────────────────────────────────

[profile tf-data-dev]
role_arn       = REPLACE_WITH_TF_DATA_DEV_ROLE_ARN
source_profile = REPLACE_WITH_YOUR_BASE_PROFILE

[profile tf-data-staging]
role_arn       = REPLACE_WITH_TF_DATA_STAGING_ROLE_ARN
source_profile = REPLACE_WITH_YOUR_BASE_PROFILE

[profile tf-data-prod]
role_arn       = REPLACE_WITH_TF_DATA_PROD_ROLE_ARN
source_profile = REPLACE_WITH_YOUR_BASE_PROFILE
```

---

## Credential Source Patterns

### AWS SSO (`source_profile`)

Configure your SSO base profile once, then reference it as `source_profile` in all Terraform profiles above.

```ini
[profile sso-base]
sso_start_url  = REPLACE_WITH_SSO_START_URL
sso_region     = us-east-1
sso_account_id = REPLACE_WITH_MANAGEMENT_ACCOUNT_ID
sso_role_name  = REPLACE_WITH_SSO_ROLE_NAME
region         = us-east-1
```

Set `source_profile = sso-base` (or whatever you name it) in all Terraform profiles.

### aws-vault (`credential_process`)

If you use [aws-vault](https://github.com/99designs/aws-vault) as your credential store, replace `source_profile` with `credential_process`:

```ini
[profile terraform-backend]
role_arn           = REPLACE_WITH_BACKEND_ROLE_ARN
credential_process = aws-vault exec REPLACE_WITH_YOUR_VAULT_PROFILE --json
```

Apply the same `credential_process` line to all Terraform profiles.

---

## Daily Workflow

```bash
# 1. Authenticate (SSO — once per session)
aws sso login --profile sso-base

# 2. Select the workspace you want to work in
terraform -chdir=tf-network-spoke workspace select dev

# 3. Init (reads terraform-backend profile from backend.tf automatically)
terraform -chdir=tf-network-spoke init

# 4. Plan (reads aws_profile from environments/dev/terraform.tfvars automatically)
terraform -chdir=tf-network-spoke plan -var-file=environments/dev/terraform.tfvars
```

No flags or environment variables are required — profile selection is fully driven by `backend.tf` and `terraform.tfvars`.
