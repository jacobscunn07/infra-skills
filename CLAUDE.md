# Infrastructure Skills

## Description

This is an infrastructure-as-code repository using Terraform to provision and manage AWS resources. Claude handles all work directly — designing architecture, writing Terraform, reviewing security, analyzing costs, ensuring reliability, and maintaining documentation. Skills provide domain expertise for each of these areas; invoke them when the task calls for it.

---

## Project Overview

Infrastructure-as-code repository targeting AWS. Terraform is the sole provisioning tool. Remote state lives in S3 with native file locking (`use_lockfile = true`), isolated per environment via **Terraform workspaces**.

---

## Agent Behavior

Claude handles requests end-to-end. The workflow for any infrastructure task is:

1. **Understand the request** — clarify scope, environment, and constraints if needed.
2. **Consult the Terraform registry** — use the `terraform-registry` MCP server to look up current provider/module versions and resource schemas before generating any Terraform code.
3. **Apply the relevant skill(s)** — invoke the appropriate skill(s) listed below for domain guidance before writing code or making recommendations.
4. **Implement** — write Terraform, update docs, etc.
5. **Validate** — run `terraform validate` then `terraform fmt`. Surface the plan output before any apply is considered.
6. **Human approval required** — `terraform apply`, `terraform destroy`, and all destructive AWS commands are blocked by hooks. Always surface plan output and wait for explicit confirmation.

---

## Coding Principles

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

---

## Skills

Invoke these skills when the task touches their domain. Skills provide current best-practice guidance that should shape the implementation.

| Skill | When to invoke |
|---|---|
| `/terraform` | Writing, reviewing, or debugging any Terraform HCL — resources, modules, variables, state, backends, lifecycle rules |
| `/technical-docs` | Writing or reviewing tutorials, how-to guides, reference docs, and runbooks |
| `/github-actions` | CI/CD workflows, matrix builds, reusable workflows, OIDC, secrets, composite actions |

---

## MCP Servers

### HashiCorp Terraform Registry MCP
- **Image:** `hashicorp/terraform-mcp-server:0.5.1` (runs via Docker)
- **Configured in:** [.mcp.json](.mcp.json)
- **Purpose:** Browse Terraform provider docs, resource schemas, and module registry.
- **Use:** Query for latest provider/module versions and resource argument references before generating Terraform code.
- **Requires:** Docker running locally.

---

## Guard Rails

The following actions are blocked by pre-tool hooks. Explicit human confirmation in the terminal is required before any of these can proceed.

| Command pattern | Reason |
|---|---|
| `terraform apply` | Unreviewed infra changes |
| `terraform destroy` | Accidental resource deletion |
| `terraform force-unlock` | State corruption |
| `aws s3 rb` | Bucket deletion |
| `aws iam delete-*` | IAM permission destruction |
| `aws ec2 terminate-instances` | Instance termination |
| `rm -rf` | File system destruction |
| `git push --force` | History rewriting on shared branches |
| `kubectl delete namespace` | Namespace/workload destruction |

Hooks are defined in [.claude/settings.json](.claude/settings.json) under `hooks.PreToolUse`.

**Terraform authority:** Claude may run `terraform validate`, `terraform fmt`, and `terraform plan` autonomously. It must surface plan output to the human before an apply is considered. Claude may never run `terraform apply` or `terraform destroy` without explicit human confirmation.

**State unlock:** To release a stuck state lock, use the **`tf-unlock` GitHub Actions workflow** (`workflow_dispatch`). Select the project/workspace and supply the lock ID from the Terraform error message. Never run `terraform force-unlock` directly from the terminal.

---

## CI/CD

Five public GitHub Actions workflows manage the full Terraform lifecycle. All AWS-authenticated jobs use OIDC (`id-token: write`) via the `AWS_ROLE_ARN` secret.

| Workflow | Trigger | What it does |
|---|---|---|
| `tf-ci.yaml` | PR opened/updated against `main` | Discovers changed projects; runs fmt, validate, and plan per workspace |
| `tf-plan.yaml` | Manual (`workflow_dispatch`) | On-demand plan for any project/workspace; **static dropdown must be updated when adding a project** |
| `tf-release.yaml` | Push to `main` | Applies changed projects in dependency order; only workspaces with `continuous-deploy: true` auto-apply |
| `tf-drift.yaml` | Nightly 02:00 UTC + manual | Plans all projects/workspaces; reports drift via GitHub summary, Slack (`SLACK_WEBHOOK_URL`), or email |
| `tf-unlock.yaml` | Manual (`workflow_dispatch`) | Force-unlocks a stuck state lock; **static dropdown must be updated when adding a project** |

**Reusable workflows** (`_tf-project-*.yaml`) are called by the public workflows — never triggered directly.

**Composite actions:**
- `get-project-workspace-matrix` — discovers all `tf-*` projects and their workspaces from `environments/` dirs and `ci.yaml`; used by every workflow
- `tf-summarize` — writes a plan/apply summary table to the GitHub Actions job summary

Set `aws-credentials: false` in a project's `ci.yaml` for workspaces that need no AWS access (e.g., local-only validation).

---

## Hooks

Defined in [.claude/settings.json](.claude/settings.json).

### PreToolUse
- **Block dangerous commands:** Intercepts `Bash` tool calls matching the guard rail patterns above and exits with an error before execution.
- **Block commits on main/master:** Intercepts `git commit` calls and exits with an error when the current branch is `main` or `master`. All commits must land on a feature branch.
- **Log tool calls:** Appends a timestamped record to `.claude/logs/tool-activity.log` for all `Bash`, `Write`, and `Edit` tool calls.
- **PostToolUse — process raw files:** After every `Write`, checks if the file was written inside `raw/`. If yes, injects a processing reminder into context.

---

## Knowledge Base

The `raw/` and `wiki/` directories form a self-organizing knowledge base for this repo. A PostToolUse hook fires whenever Claude writes a file to `raw/`, injecting a processing reminder into the conversation.

- **`raw/`** — Drop zone for source material: paste-ins, exports, notes. All content is tracked in git.
- **`wiki/`** — Organized reference pages with wikilinks. One page per concept, tool, or pattern.
- **`wiki/learnings.md`** — Append-only log of what worked and what didn't.

---

### Wiki Page Schema

Every page in `wiki/` must follow this structure:

```markdown
---
title: Human-Readable Page Title
tags: [tag1, tag2]
related: ["[[Category/Other Page]]"]
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

## Overview

One paragraph — what this is and why it matters for IaC.

## Key Concepts

Bullet list of the most important ideas. Use wikilinks: [[Category/Related Page]].

## Patterns

Named patterns with brief descriptions. When to use. Tradeoffs.

## Gotchas

Known failure modes and non-obvious behavior.

## References

- [[Category/Related Page]]
```

**Slug format:** lowercase, hyphen-separated, matching the filename without `.md`. Example: `wiki/networking/transit-gateway-routing.md` → title `Transit Gateway Routing`.

---

### Wikilink Conventions

| Format | When to use |
|---|---|
| `[[Category/Page Name]]` | Standard form — always include the category |
| `[[Category/Page Name\|Display Text]]` | When the page title reads awkwardly inline |

Links are case-sensitive and must match the `title` field in the target page's frontmatter. The slug (filename) is the lowercase-hyphen version of that title.

---

### Category Taxonomy

| Directory | Contents |
|---|---|
| `wiki/networking/` | VPCs, subnets, routing, Transit Gateway, VPN, security groups, NACLs |
| `wiki/iam/` | IAM policies, roles, trust policies, permission boundaries, SCPs, cross-account |
| `wiki/security/` | KMS, ACM, Secrets Manager, WAF, GuardDuty, encryption patterns |
| `wiki/compute/` | EC2, ECS, Fargate, Lambda, Auto Scaling, instance types, purchasing options |
| `wiki/storage/` | S3, EFS, EBS, storage classes, lifecycle, replication |
| `wiki/database/` | RDS, Aurora, ElastiCache, DynamoDB, backups, Multi-AZ |
| `wiki/observability/` | CloudWatch, alarms, Logs Insights, dashboards, SLIs/SLOs |
| `wiki/cicd/` | GitHub Actions, OIDC, Terraform CI patterns, drift detection |
| `wiki/concepts/` | Cross-cutting patterns: least privilege, immutable infra, cost tagging |

When a topic spans categories, place the page in the primary one and wikilink from the others.

---

### Processing a `raw/` File

When the PostToolUse hook fires (or when asked to process a raw file), follow these steps:

1. **Read** the file — identify its type (paste, export, doc snippet, notes).
2. **Extract** key concepts, patterns, and gotchas. Discard filler.
3. **Choose a category** from the taxonomy table.
4. **Find or create** the target page: `wiki/<category>/<slug>.md`.
5. **Write or merge** using the wiki page schema above.
6. **Cross-reference** — update `related:` frontmatter in adjacent pages.
7. **Update `wiki/learnings.md`** if the session produced new insights.
8. Leave the source file in `raw/` — do not delete it.

---

### `learnings.md` Format

`wiki/learnings.md` is append-only. Each session gets one dated entry. Never edit or delete existing entries. If a session produces no new insights, skip it.

```markdown
## YYYY-MM-DD

### What Worked
- Specific thing with enough context to be actionable later.

### What Didn't Work
- Specific failure, with root cause if known.

### Changed Approach
- What we tried first, what we switched to, and why.
```

---

## Memory

Shared memory lives in `.claude/memory/`. Use it to record decisions and context that should persist across sessions.

| File | Owner | Purpose |
|---|---|---|
| `decisions.md` | Claude | Architectural and security decisions with rationale |
| `conventions.md` | Claude | Terraform naming, tagging, and module conventions |
| `aws-account-map.md` | Human | Account IDs, regions, and environment names |
| `security-baselines.md` | Human | Approved security baselines and non-negotiables |
| `cost-targets.md` | Human | Per-environment budget targets |
| `oncall-runbooks.md` | Claude | SRE runbook index |

---

## Conventions

### Terraform

- **Modules first:** Always prefer `terraform-aws-modules/*` community modules over raw resource blocks. Search the Terraform registry MCP before writing any raw `resource`. Only fall back to raw resources when no suitable module exists.
- **Workspaces:** Each environment (`dev`, `staging`, `prod`) is a Terraform workspace. Run with `terraform workspace select <env> && terraform apply -var-file=environments/<env>/terraform.tfvars`. Never use a `variable "environment"` — derive it from `terraform.workspace` via `locals.tf`.
- **Environment vars:** Environment-specific values live in `environments/<workspace>/terraform.tfvars` within each project folder. Do not commit secrets to these files.
- **Module structure:** Reusable local modules live in `modules/<module-name>/`. Each must have `main.tf`, `variables.tf`, `outputs.tf`, and `README.md`. Every root module (`tf-*/`) must include `main.tf`, `variables.tf`, `outputs.tf`, `locals.tf`, `versions.tf`, `backend.tf`, `ssm.tf`, and `ci.yaml`.
- **Naming:** `<project>-<env>-<resource-type>-<descriptor>` (e.g., `myapp-prod-sg-alb`).
- **Tagging:** Every resource must include: `Environment`, `Project`, `ManagedBy=terraform`, `Owner`, `CostCenter`. Use provider-level `default_tags` to apply common tags automatically.
- **State:** Remote state in S3 with `use_lockfile = true`. Workspace prefix is automatic — the backend `key` is the base path; Terraform prepends `env:/<workspace>/` per workspace.
- **Variables:** No hardcoded account IDs, regions, or secrets. Use `var.*` or `data.aws_caller_identity`.
- **Secrets:** Never commit secrets. Use AWS Secrets Manager or SSM Parameter Store references. Prefer `manage_master_user_password = true` on RDS/Aurora so AWS manages credentials natively.
- **SSM output publishing:** Every root module must have an `ssm.tf` that mirrors all outputs to SSM Parameter Store via a dedicated `aws.ssm` provider alias. Path convention: `/<project>/<environment>/<component>/<output-name>`. This allows any consumer (Terraform, CDK, scripts) to read outputs without access to the state backend. See the `/terraform` skill for the full pattern.
- **`ci.yaml`:** Every root module must have a `ci.yaml` that controls CI/CD behavior for that project. Schema:

```yaml
enabled: true              # false disables the project across all workflows
aws-credentials: true      # project-level default for OIDC AWS auth

workspaces:
  dev:
    enabled: true
    continuous-deploy: true   # auto-applied on merge to main
  staging:
    enabled: true
    continuous-deploy: true
  prod:
    enabled: true
    continuous-deploy: false  # prod requires a manual tf-release dispatch

project-dependencies: []   # other project names this one depends on (controls tf-release ordering)
```

### Adding a New Project

When creating a new `tf-<name>/` project, beyond the standard Terraform files you must also update the repo-wide CI/CD wiring:

1. Create `ci.yaml` using the schema above.
2. Add `tf-<name> / dev`, `tf-<name> / staging`, `tf-<name> / prod`, and `tf-<name> / all` to the `inputs.target.options` list in `.github/workflows/tf-plan.yaml`.
3. Add the same workspace entries to the `inputs.target.options` list in `.github/workflows/tf-unlock.yaml`.
4. Add a `deploy-tf-<name>:` job to `.github/workflows/tf-release.yaml`. Set `needs:` to match the `project-dependencies` declared in `ci.yaml` — if no dependencies, `needs: [setup]` only.

### Git

- **Commit messages:** Follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) — invoke the `/conventional-commits` skill for format, type selection, and breaking change markers.
- **Branch naming:** `<jira-ticket>/<slug>` (e.g., `INFRA-123/vpc-peering`, `INFRA-456/sg-egress-rule`). The slug should be a short, lowercase, hyphen-separated description of the change.
- PRs touching IAM, security groups, or KMS require human review before merge.
- **Confirm before committing:** Always surface the proposed commit message and staged changes, then wait for explicit human confirmation before running `git commit`.
- **Never commit to main:** All commits must be on a feature branch. If the current branch is `main` or `master`, stop and ask the human to create or switch to a feature branch before proceeding.

### Documentation

- All diagrams use Mermaid format (fenced `mermaid` blocks in `.md` files).
- Architecture diagrams: `docs/architecture/`.
- Runbooks: `docs/runbooks/`.
- Reference docs: `docs/reference/`.
- Docs must be updated in the same PR as the Terraform change they describe.

### File Layout

```
.
├── .claude/
│   ├── settings.json          # Hooks and permissions
│   ├── settings.local.json    # Local overrides (not committed)
│   ├── commands/              # Slash command definitions
│   ├── hooks/                 # Pre-tool hook scripts
│   ├── skills/                # Skill definitions
│   └── logs/                  # Tool activity logs
├── .github/
│   ├── actions/
│   │   ├── get-project-workspace-matrix/   # Discovers tf-* projects and workspaces
│   │   └── tf-summarize/                   # Writes plan/apply summary tables
│   └── workflows/
│       ├── tf-ci.yaml                      # PR validation (fmt + validate + plan)
│       ├── tf-plan.yaml                    # On-demand plan (workflow_dispatch)
│       ├── tf-release.yaml                 # Post-merge apply (push to main)
│       ├── tf-drift.yaml                   # Nightly drift detection
│       ├── tf-unlock.yaml                  # Emergency state unlock
│       └── _tf-project-*.yaml             # Reusable workflows (not triggered directly)
├── .mcp.json                  # MCP server configuration
├── raw/                       # Drop zone for unprocessed source material
├── wiki/                      # Organized knowledge base with wikilinks
│   ├── learnings.md           # Append-only log of what worked / didn't
│   ├── networking/
│   ├── iam/
│   ├── compute/
│   ├── storage/
│   ├── database/
│   ├── observability/
│   ├── security/
│   ├── cicd/
│   └── concepts/
├── docs/
│   ├── architecture/          # Mermaid architecture diagrams
│   ├── reference/             # Reference documents
│   └── runbooks/              # SRE operational runbooks
├── modules/                   # Reusable local Terraform modules
└── tf-<component>/            # e.g. tf-network-spoke/, tf-data/
    ├── main.tf                # Module calls — no env-specific values
    ├── variables.tf           # Variable declarations
    ├── outputs.tf
    ├── locals.tf              # environment = terraform.workspace
    ├── versions.tf
    ├── backend.tf
    ├── ssm.tf                 # Mirrors outputs to SSM Parameter Store
    ├── ci.yaml                # CI/CD config — required
    └── environments/
        ├── dev/
        │   └── terraform.tfvars
        ├── staging/
        │   └── terraform.tfvars
        └── prod/
            └── terraform.tfvars
```
