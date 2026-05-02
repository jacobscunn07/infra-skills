# AWS Account Map

| Field   | Value |
|---------|-------|
| Owner   | Human |
| Purpose | Resolves account IDs, regions, and workspace names before generating Terraform or running AWS CLI commands. Update when accounts, regions, or environment mappings change. |

---

## Accounts

| Account Name | Account ID | Primary Region | Secondary Regions |
|---|---|---|---|
| management | `REPLACE_ME` | us-east-1 | |
| dev | `REPLACE_ME` | us-east-1 | |
| staging | `REPLACE_ME` | us-east-1 | |
| prod | `REPLACE_ME` | us-east-1 | |

---

## Environment → Workspace Mapping

| Environment | Terraform Workspace | AWS Account |
|---|---|---|
| dev | dev | dev |
| staging | staging | staging |
| prod | prod | prod |

---

## OIDC Role

| Field | Value |
|---|---|
| Role ARN | `REPLACE_ME` (e.g. `arn:aws:iam::<account-id>:role/github-actions-oidc`) |
| Trust policy conditions | `repo:REPLACE_ME/infra-skills:*` |
| GitHub variable name | `AWS_ROLE_ARN` |

---

## Backend Role (shared — all projects/workspaces)

| Field | Value |
|---|---|
| Role ARN | `REPLACE_ME` (e.g. `arn:aws:iam::<mgmt-account-id>:role/terraform-backend`) |
| Profile name | `terraform-backend` |
| Used for | S3 state bucket read/write; hardcoded in every `backend.tf` |

---

## SSM Role (shared — all projects/workspaces)

| Field | Value |
|---|---|
| Role ARN | `REPLACE_ME` (e.g. `arn:aws:iam::<mgmt-account-id>:role/terraform-ssm`) |
| Profile name | `terraform-ssm` |
| Used for | SSM Parameter Store writes via the `aws.ssm` provider alias in every project |

---

## Deploy Roles (per project/workspace)

Profile naming convention: `tf-<project>-<workspace>`

| Project | Workspace | AWS Account | Profile Name | Role ARN |
|---|---|---|---|---|
| tf-network-spoke | dev | dev | `tf-network-spoke-dev` | `REPLACE_ME` |
| tf-network-spoke | staging | staging | `tf-network-spoke-staging` | `REPLACE_ME` |
| tf-network-spoke | prod | prod | `tf-network-spoke-prod` | `REPLACE_ME` |
| tf-data | dev | dev | `tf-data-dev` | `REPLACE_ME` |
| tf-data | staging | staging | `tf-data-staging` | `REPLACE_ME` |
| tf-data | prod | prod | `tf-data-prod` | `REPLACE_ME` |

Profile definitions live in `.github/.aws/config` (CI) and `~/.aws/config` (local).
See `docs/reference/local-dev-setup.md` for the local profile template.
