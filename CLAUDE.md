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

## Skills

Invoke these skills when the task touches their domain. Skills provide current best-practice guidance that should shape the implementation.

| Skill | When to invoke |
|---|---|
| `/terraform` | Writing, reviewing, or debugging any Terraform HCL — resources, modules, variables, state, backends, lifecycle rules |
| `/aws-networking` | VPCs, subnets, routing, security groups, NACLs, gateways, Transit Gateway, VPC endpoints, Direct Connect |
| `/aws-iam` | IAM policies, roles, trust policies, cross-account access, permission boundaries, SCPs, STS |
| `/aws-ec2` | Instance types, purchasing options, AMIs, EBS, Auto Scaling, launch templates, Spot |
| `/aws-autoscaling` | Auto Scaling Groups, scaling policies, instance refresh, lifecycle hooks, warm pools |
| `/aws-rds` | RDS and Aurora engine selection, Multi-AZ, read replicas, Aurora Serverless, RDS Proxy, backups |
| `/aws-s3` | Bucket architecture, storage classes, access control, encryption, lifecycle, replication, versioning |
| `/aws-ecs` | ECS clusters, task definitions, Fargate vs EC2 launch types, service networking, IAM roles |
| `/aws-ecr` | Container image repositories, lifecycle policies, image scanning, replication, pull-through cache |
| `/aws-efs` | EFS file systems, performance/throughput modes, access points, IAM and POSIX permissions, mounting |
| `/aws-cloudfront` | CDN distributions, cache behaviors, OAC for S3, signed URLs, WAF integration, Lambda@Edge |
| `/aws-cloudwatch` | Metrics, alarms, Logs Insights, dashboards, anomaly detection, cross-account monitoring |
| `/aws-kms` | Key policies, envelope encryption, key rotation, multi-region keys, cross-account usage |
| `/aws-global-accelerator` | Standard and custom routing accelerators, anycast IPs, traffic dials, endpoint weights |
| `/sre` | SLIs/SLOs, error budgets, HA/DR design, incident management, runbooks, four golden signals |
| `/technical-docs` | Writing or reviewing tutorials, how-to guides, reference docs, and runbooks |
| `/mermaid` | Architecture diagrams, sequence diagrams, flowcharts, and any other Mermaid chart type |
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

---

## Hooks

Defined in [.claude/settings.json](.claude/settings.json).

### PreToolUse
- **Block dangerous commands:** Intercepts `Bash` tool calls matching the guard rail patterns above and exits with an error before execution.
- **Log tool calls:** Appends a timestamped record to `.claude/logs/tool-activity.log` for all `Bash`, `Write`, and `Edit` tool calls.

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
- **Module structure:** Reusable local modules live in `modules/<module-name>/`. Each must have `main.tf`, `variables.tf`, `outputs.tf`, and `README.md`.
- **Naming:** `<project>-<env>-<resource-type>-<descriptor>` (e.g., `myapp-prod-sg-alb`).
- **Tagging:** Every resource must include: `Environment`, `Project`, `ManagedBy=terraform`, `Owner`, `CostCenter`. Use provider-level `default_tags` to apply common tags automatically.
- **State:** Remote state in S3 with `use_lockfile = true`. Workspace prefix is automatic — the backend `key` is the base path; Terraform prepends `env:/<workspace>/` per workspace.
- **Variables:** No hardcoded account IDs, regions, or secrets. Use `var.*` or `data.aws_caller_identity`.
- **Secrets:** Never commit secrets. Use AWS Secrets Manager or SSM Parameter Store references. Prefer `manage_master_user_password = true` on RDS/Aurora so AWS manages credentials natively.
- **SSM output publishing:** Every root module must have an `ssm.tf` that mirrors all outputs to SSM Parameter Store via a dedicated `aws.ssm` provider alias. Path convention: `/<project>/<environment>/<component>/<output-name>`. This allows any consumer (Terraform, CDK, scripts) to read outputs without access to the state backend. See the `/terraform` skill for the full pattern.

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
│   ├── skills/                # Skill definitions
│   └── logs/                  # Tool activity logs
├── .mcp.json                  # MCP server configuration
├── docs/
│   ├── architecture/          # Mermaid architecture diagrams
│   ├── reference/             # Reference documents
│   └── runbooks/              # SRE operational runbooks
├── modules/                   # Reusable local Terraform modules
└── <component>/               # e.g. networking-spoke/, data/
    ├── main.tf                # Module calls — no env-specific values
    ├── variables.tf           # Variable declarations
    ├── outputs.tf
    ├── locals.tf              # environment = terraform.workspace
    ├── versions.tf
    ├── backend.tf
    └── environments/
        ├── dev/
        │   └── terraform.tfvars
        ├── staging/
        │   └── terraform.tfvars
        └── prod/
            └── terraform.tfvars
```
