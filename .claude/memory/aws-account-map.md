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

## Notes

- All Terraform projects use a single OIDC role unless noted otherwise.
- Add per-project exceptions here if a project assumes a different role.
