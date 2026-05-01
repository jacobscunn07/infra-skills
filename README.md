# infra-skills

AWS infrastructure as code, managed with Terraform and Claude Code.

## Table of Contents

**Getting started**
- [Overview](#overview)
- [How This Repo Works](#how-this-repo-works)
- [Prerequisites](#prerequisites)
- [First-Time Setup](#first-time-setup)

**Daily use**
- [Day-to-Day Workflow](#day-to-day-workflow)
- [Terraform Projects](#terraform-projects)
- [CI/CD Workflows](#cicd-workflows)
- [Runbooks](#runbooks)

**Reference**
- [Claude Code Configuration](#claude-code-configuration)
- [Adding a New Project](#adding-a-new-project)
- [Guard Rails](#guard-rails)
- [Secrets & Variables](#secrets--variables)
- [Docs & Knowledge Base](#docs--knowledge-base)

---

## Overview

This repo manages AWS infrastructure using Terraform. Claude Code is the primary interface: Claude writes all Terraform, runs validation, keeps docs current, and surfaces plan output before anything touches AWS. Remote state lives in S3 with native file locking. Three environments (dev, staging, prod) are isolated as Terraform workspaces. GitHub Actions handles CI validation, automated applies, nightly drift detection, and emergency state unlock.

---

## How This Repo Works

Claude does the implementation; you direct, review, and approve.

1. Tell Claude what infrastructure you need in plain language.
2. Claude looks up the latest provider and module versions via the Terraform Registry MCP server, writes the Terraform, and runs `terraform validate` + `terraform fmt`.
3. Claude surfaces `terraform plan` output before opening a PR. Ask questions or request changes.
4. On merge, GitHub Actions validates and applies to workspaces with `continuous-deploy: true` (dev and staging by default).
5. Prod workspaces are never auto-applied. Trigger `tf-release` manually when ready.
6. Hooks block destructive commands and enforce branch discipline automatically. You don't need to memorize the rules.

---

## Prerequisites

| Tool | Required | Purpose |
|---|---|---|
| [Claude Code](https://claude.ai/code) (latest) | **required** | Primary interface — all infrastructure work happens here |
| Docker | **required** | Runs the Terraform Registry MCP server (`hashicorp/terraform-mcp-server`) |
| Terraform ≥ 1.x | **required** | Claude runs `init / validate / fmt / plan` locally |
| AWS CLI v2 | **required** | Claude runs read-only describe/list queries during planning |
| Git ≥ 2.x | **required** | |
| Python 3.9+ | **required** | One-time setup scripts |
| gh (GitHub CLI) | optional | Useful for PR operations from the terminal |
| kubectl | optional | Needed only if working with EKS or Kubernetes resources |
| jq | optional | Useful for inspecting Terraform JSON output |
| yq | optional | Useful for inspecting YAML config files |
| tflint | optional | Additional Terraform linting; Claude uses it if installed |
| terraform-docs | optional | Auto-generates module documentation |
| trivy | optional | Container and IaC vulnerability scanning |
| checkov | optional | Security and compliance scanning; the `run-checkov` hook fires automatically if installed |
| gitleaks | optional | Secret scanning; the `scan-secrets` hook fires on every file write/edit if installed |

The `document-environment` hook runs at session start and injects which of these tools are installed and their versions into Claude's context.

---

## First-Time Setup

Run these steps once after cloning the repo. After setup, Claude takes over.

**1. Clone and open in Claude Code**

```bash
git clone <repo-url>
cd infra-skills
claude  # or open in VS Code with the Claude Code extension
```

**2. Run the setup script**

Fills in your S3 bucket name, AWS account IDs, OIDC role ARN, and CODEOWNERS reviewer. Edits `tf-data/backend.tf`, `tf-network-spoke/backend.tf`, and `.claude/memory/aws-account-map.md`.

```bash
python3 scripts/setup.py
```

**3. Configure GitHub**

Creates all GitHub Environments (`terraform/<project>/<workspace>`) and sets the `AWS_ROLE_ARN` Actions variable. Requires a personal access token with `repo` scope. Safe to re-run; all operations are upserts.

```bash
GITHUB_TOKEN=ghp_xxx python3 scripts/setup-github.py

# Preview without making changes:
DRY_RUN=1 GITHUB_TOKEN=ghp_xxx python3 scripts/setup-github.py
```

**4. (Optional) Add required reviewers for prod**

In the GitHub repo: Settings → Environments → `terraform/<project>/prod` → Required reviewers. Without reviewers, the environment still gates deploys but skips the approval step.

**5. Start Claude Code**

```bash
claude
```

The `document-environment` hook injects your installed tool versions into Claude's context on startup.

---

## Day-to-Day Workflow

Open Claude Code and describe the change. Claude handles the rest.

**1. Open Claude Code**

```bash
claude  # terminal
# or open the repo in VS Code with the Claude Code extension
```

**2. Describe the change**

> "Add an S3 bucket for audit logs in tf-data, encrypted with KMS, with a lifecycle rule to expire objects after 90 days."

**3. Claude implements**

Claude creates a feature branch (`INFRA-xxx/slug`), looks up the current module version via the Terraform Registry MCP server, writes the Terraform, runs `terraform validate` + `terraform fmt`, and surfaces plan output for review.

**4. Review and merge**

Review the plan. Ask questions or request changes. Once satisfied, approve the PR.

**5. CI validates automatically**

On PR open and sync, `tf-ci` runs fmt check, security scan, validate, and plan on all changed projects. Results appear in the PR checks.

**6. Merge**

On merge to `main`, `tf-release` applies changed projects in dependency order. Workspaces with `continuous-deploy: true` apply automatically.

**7. Prod requires a manual dispatch**

Prod workspaces have `continuous-deploy: false`. Trigger `tf-release` manually in GitHub Actions when ready to promote.

---

## Terraform Projects

Each project under `tf-<name>/` manages a related group of AWS resources. All three environments (dev, staging, prod) are Terraform workspaces within each project. Environment-specific values live in `tf-<name>/environments/<env>/terraform.tfvars`.

| Project | Depends on | Auto-deploys dev/staging |
|---|---|---|
| `tf-testA` | none | yes |
| `tf-testB` | `tf-testA` | yes |
| `tf-network-spoke` | none | yes |
| `tf-data` | `tf-network-spoke` | yes |

Dependency order is enforced in `tf-release.yaml`. If `tf-testA` fails, `tf-testB` will not apply.

**Standard project structure:**

```
tf-<name>/
├── main.tf                 # Module calls — no env-specific values
├── variables.tf
├── outputs.tf
├── locals.tf               # environment = terraform.workspace
├── versions.tf
├── backend.tf              # S3 remote state
├── ssm.tf                  # Mirrors outputs to SSM Parameter Store
├── ci.yaml                 # CI/CD config (enabled, workspaces, continuous-deploy)
└── environments/
    ├── dev/terraform.tfvars
    ├── staging/terraform.tfvars
    └── prod/terraform.tfvars
```

---

## CI/CD Workflows

| Workflow | Trigger | What it does |
|---|---|---|
| [`tf-ci`](.github/workflows/tf-ci.yaml) | PR opened/updated against `main` | fmt check + security scan + validate + plan on changed projects only |
| [`tf-plan`](.github/workflows/tf-plan.yaml) | `workflow_dispatch` (dropdown) | On-demand plan for any project/workspace without opening a PR |
| [`tf-release`](.github/workflows/tf-release.yaml) | Push to `main` | Applies changed projects in dependency order; `continuous-deploy: false` workspaces are skipped |
| [`tf-drift`](.github/workflows/tf-drift.yaml) | Nightly 02:00 UTC + manual | Plans all projects/workspaces unconditionally; notifies Slack or email when drift is found |
| [`tf-unlock`](.github/workflows/tf-unlock.yaml) | `workflow_dispatch` (dropdown + lock ID) | Releases a stuck Terraform state lock via `dflook/terraform-unlock-state` |

All AWS-authenticated jobs use OIDC (`id-token: write`). No long-lived credentials are stored anywhere.

See [CI/CD Reference](docs/reference/ci-cd.md) for full workflow details, the project discovery mechanism, composite action inputs/outputs, and GitHub Environment naming.

---

## Runbooks

When something goes wrong, start here.

| Runbook | When to use |
|---|---|
| [Drift Remediation](docs/runbooks/drift-remediation.md) | Slack alert or nightly `tf-drift` shows live AWS resources have diverged from Terraform state |
| [Rollback](docs/runbooks/rollback.md) | A `terraform apply` completed but produced unwanted changes; need to restore the last known-good state |
| [State Recovery](docs/runbooks/state-recovery.md) | `Error acquiring the state lock` — stuck lock or corrupted/diverged state file |

---

## Claude Code Configuration

All of this is wired up automatically. Nothing to configure after setup.

### MCP Server — Terraform Registry

Runs via Docker using `hashicorp/terraform-mcp-server:0.5.1`. Configured in [`.mcp.json`](.mcp.json).

Claude queries this before writing any Terraform to fetch the latest provider and module versions and resource argument schemas. Docker must be running.

### Skills

Claude invokes these automatically based on the task. You can also invoke them manually.

| Skill | When Claude uses it |
|---|---|
| `/terraform` | Any Terraform HCL — resources, modules, state, backends, lifecycle rules |
| `/technical-docs` | Writing runbooks, reference docs, and tutorials |
| `/github-actions` | CI/CD workflows, composite actions, OIDC, permissions |

### Hooks

| Hook | Fires on | What it does |
|---|---|---|
| `block-dangerous-commands` | Bash | Intercepts `terraform apply/destroy`, `git push --force`, `rm -rf`, destructive AWS calls, and more |
| `block-commit-on-main` | Bash | Prevents direct commits to `main`/`master` |
| `run-checkov` | Bash | Runs Checkov security scan before `terraform plan/validate` (skipped if not installed) |
| `scan-secrets` | Write, Edit | Scans written/edited content for secrets using gitleaks (skipped if not installed) |
| `sync-workflow-options-on-change` | Write, Edit | Keeps `tf-plan` and `tf-unlock` dropdowns in sync when `backend.tf` or `environments/` change |
| `log-tool-activity` | Bash, Write, Edit | Appends a timestamped record to `.claude/logs/tool-activity.log` |
| `document-environment` | SessionStart | Injects installed CLI tool versions into session context |

Hook definitions live in [`.claude/settings.json`](.claude/settings.json).

### Memory

Claude reads `.claude/memory/` for persistent cross-session context. You own [`aws-account-map.md`](.claude/memory/aws-account-map.md). Keep it updated when accounts or the OIDC role change.

---

## Adding a New Project

Tell Claude: *"Create a new Terraform project called tf-\<name\> that provisions..."* Claude handles steps 1 and 2. Steps 3 and 4 are yours.

1. Create `tf-<name>/` with `main.tf`, `variables.tf`, `outputs.tf`, `locals.tf`, `versions.tf`, `backend.tf`, `ssm.tf`, `ci.yaml`, and `environments/dev|staging|prod/terraform.tfvars`.

2. The `sync-workflow-options-on-change` hook updates `tf-plan.yaml` and `tf-unlock.yaml` whenever `backend.tf` or `environments/` are written. The `validate-dropdowns` CI job catches any gaps.

3. Add a `deploy-tf-<name>:` job to [`.github/workflows/tf-release.yaml`](.github/workflows/tf-release.yaml) with `needs:` matching the `project-dependencies` declared in `ci.yaml`.

4. Run `python3 scripts/setup-github.py` to create the `terraform/<project>/<workspace>` environments in GitHub.

---

## Guard Rails

Claude hooks and the `.claude/settings.json` deny list enforce these automatically. If you ask Claude to run a blocked command, it stops and explains.

| Blocked | Reason |
|---|---|
| `terraform apply` | Must go through CI/CD with explicit human review |
| `terraform destroy` | Accidental resource deletion |
| `terraform force-unlock` | Use the [`tf-unlock`](.github/workflows/tf-unlock.yaml) workflow instead |
| `git push --force` | Protects shared branch history |
| `rm -rf` | Filesystem destruction |
| `aws iam delete-*` | IAM permission destruction |
| `aws s3 rb` | Bucket deletion |
| `aws ec2 terminate-instances` | Instance termination |
| `kubectl delete namespace` | Workload destruction |
| Git commits on `main`/`master` | All commits must land on a feature branch |

---

## Secrets & Variables

Set once during setup. Only revisit when rotating the OIDC role or adding notification integrations.

**GitHub Actions secrets**

| Secret | Required | Purpose |
|---|---|---|
| `SLACK_WEBHOOK_URL` | optional | Drift detection Slack notifications (drift found + all-clear) |
| `MAIL_SERVER` | optional (all or none) | Drift detection email notifications |
| `MAIL_PORT` | optional (all or none) | |
| `MAIL_USERNAME` | optional (all or none) | |
| `MAIL_PASSWORD` | optional (all or none) | |
| `MAIL_TO` | optional (all or none) | |
| `MAIL_FROM` | optional (all or none) | |

Email notifications require all six `MAIL_*` secrets. If any are missing, email is silently skipped.

**GitHub Actions variables**

| Variable | Set by | Value |
|---|---|---|
| `AWS_ROLE_ARN` | `scripts/setup-github.py` | OIDC role ARN used by all workflows for AWS authentication |

Authentication uses OIDC. No long-lived AWS access keys are stored anywhere.

---

## Docs & Knowledge Base

| Location | Contents |
|---|---|
| [`docs/reference/`](docs/reference/) | Reference docs, including the [CI/CD Reference](docs/reference/ci-cd.md) |
| [`docs/runbooks/`](docs/runbooks/) | Operational playbooks for incidents |
| [`wiki/`](wiki/) | Organized knowledge base across 9 categories (networking, IAM, security, compute, storage, database, observability, CI/CD, concepts). Claude reads and writes these automatically. |
| [`wiki/learnings.md`](wiki/learnings.md) | Append-only log of what worked and didn't across sessions |
| [`.claude/memory/`](.claude/memory/) | Persistent cross-session context for Claude (account map, decisions, conventions) |
