---
name: terraform
description: Use when writing, reviewing, or debugging Terraform code - resource blocks, modules, variables, outputs, state management, backends, imports, refactoring with moved blocks, expressions, dynamic blocks, lifecycle rules, or any HCL authoring and architecture decisions
---

# Terraform Expert Skill

Comprehensive Terraform guidance covering HCL authoring, module design, state management, backends, expressions, and production patterns. Based on the official HashiCorp Terraform language documentation.

## When to Use This Skill

**Activate this skill when:**
- Writing or reviewing Terraform resource, data source, or provider blocks
- Designing module structure and composition
- Managing remote state (S3 backend, locking, workspaces)
- Using expressions, `for_each`, `count`, dynamic blocks, or splat expressions
- Writing lifecycle rules (`create_before_destroy`, `prevent_destroy`, `ignore_changes`)
- Importing existing infrastructure with `import` blocks
- Refactoring resources with `moved` blocks
- Debugging plan/apply failures or state drift
- Choosing between `count` vs `for_each`

**Don't use this skill for:**
- CDK, Pulumi, or CloudFormation (different IaC tools)
- Terraform Cloud / HCP Terraform UI workflows
- Provider-specific deep dives (use the relevant AWS/GCP/Azure skill alongside this one)

---

## Core Principle: Prefer Community Modules

**Always prefer public community modules over raw resource blocks.** The `terraform-aws-modules` ecosystem covers the vast majority of AWS infrastructure needs and is the default starting point.

Before writing any raw `resource` block, ask: does a `terraform-aws-modules/*` module exist for this? If so, use it.

### Module-First Decision Tree

1. Search the Terraform registry (via the `terraform-registry` MCP) for a matching `terraform-aws-modules/*` module.
2. If a module exists: use it, pin to `~> <major>.0`, and configure only the inputs you need.
3. If no module exists **or** the module doesn't support your use case: write raw resources.
4. **Never** write raw resources for VPCs, S3 buckets, KMS keys, RDS/Aurora, ECS clusters, IAM roles, or security groups when a `terraform-aws-modules` module covers the use case.

### Key Community Modules (Always Check Latest Version via MCP)

| AWS Service | Module |
|---|---|
| VPC, subnets, NAT, flow logs | `terraform-aws-modules/vpc/aws` |
| Aurora / RDS | `terraform-aws-modules/rds-aurora/aws` or `terraform-aws-modules/rds/aws` |
| S3 buckets | `terraform-aws-modules/s3-bucket/aws` |
| KMS keys | `terraform-aws-modules/kms/aws` |
| IAM roles and policies | `terraform-aws-modules/iam/aws` (submodules) |
| Security groups | `terraform-aws-modules/security-group/aws` |
| ECS cluster + services | `terraform-aws-modules/ecs/aws` |
| ECR repositories | `terraform-aws-modules/ecr/aws` |
| EKS clusters | `terraform-aws-modules/eks/aws` |
| Lambda functions | `terraform-aws-modules/lambda/aws` |
| ALB / NLB | `terraform-aws-modules/alb/aws` |
| CloudWatch alarms | `terraform-aws-modules/cloudwatch/aws` |

### Module Calling Pattern

```hcl
# Query the MCP for the latest version before writing this.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"   # Pin to major; allows patch/minor updates

  name = "${local.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs              = var.availability_zones
  public_subnets   = var.public_subnet_cidrs
  private_subnets  = var.private_subnet_cidrs
  database_subnets = var.isolated_subnet_cidrs

  enable_nat_gateway     = var.enable_nat_gateway
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_flow_log                                 = var.enable_flow_logs
  create_flow_log_cloudwatch_log_group            = var.enable_flow_logs
  create_flow_log_cloudwatch_iam_role             = var.enable_flow_logs
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_retention_days

  tags = local.common_tags
}

# Reference module outputs
output "vpc_id" {
  value = module.vpc.vpc_id
}
```

### Module Design Rules

- One responsibility per module — don't create a "mega-module" for an entire environment
- Pass in all IDs/ARNs as variables — never hardcode resource identifiers inside a module
- Always pin registry modules to a major version constraint (`~> 6.0`, not `>= 6.0`)
- Expose outputs for any resource attribute callers might need
- Mark outputs `sensitive = true` if they expose secrets
- **Always query the `terraform-registry` MCP for the latest version** before writing a `source` + `version` block

---

## Workspaces for Environment Management

**Use Terraform workspaces as the environment mechanism.** Each environment (`dev`, `staging`, `prod`) is a separate workspace. Environment-specific variable values live in `environments/<workspace>/terraform.tfvars`.

### Workspace Workflow

```bash
# Create and select a workspace
terraform workspace new dev
terraform workspace select dev
terraform workspace list

# Apply with workspace-specific vars
terraform apply -var-file=environments/dev/terraform.tfvars

# Plan with output file for safe apply
terraform plan -var-file=environments/dev/terraform.tfvars -out=plan.tfplan
terraform apply plan.tfplan
```

### Directory Layout with Workspaces

```
my-component/
├── main.tf           # Module calls — no environment-specific values
├── variables.tf      # Variable declarations — no environment defaults
├── outputs.tf
├── locals.tf         # environment = terraform.workspace
├── versions.tf
├── backend.tf        # Single backend config; workspace prefix is automatic
└── environments/
    ├── dev/
    │   └── terraform.tfvars
    ├── staging/
    │   └── terraform.tfvars
    └── prod/
        └── terraform.tfvars
```

### Derive Environment from Workspace

```hcl
# locals.tf
locals {
  # Valid workspaces: dev, staging, prod
  environment = terraform.workspace
  name_prefix = "${var.project}-${local.environment}"

  common_tags = {
    Project     = var.project
    Environment = local.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
    CostCenter  = var.cost_center
  }
}
```

- Remove `variable "environment"` from `variables.tf` — the workspace IS the environment.
- Reference `local.environment` everywhere instead of `var.environment`.
- Use `local.environment == "prod"` for environment-specific toggles (e.g., `deletion_protection`, `skip_final_snapshot`).

### Reading Another Component's Workspace State

When one component reads another's remote state, use the `workspace` parameter to automatically select the matching workspace's state:

```hcl
data "terraform_remote_state" "networking" {
  backend   = "s3"
  workspace = terraform.workspace   # reads env:/dev/networking/terraform.tfstate in dev, etc.

  config = {
    bucket = var.networking_state_bucket
    key    = "networking-spoke/terraform.tfstate"
    region = var.networking_state_region
  }
}
```

### S3 Backend with Workspaces

The S3 backend automatically namespaces state per workspace. The `key` in `backend.tf` is the base key; Terraform prepends `env:/<workspace>/` automatically.

```hcl
# backend.tf — single config, workspace-isolated state
terraform {
  backend "s3" {
    bucket       = "REPLACE_WITH_TERRAFORM_STATE_BUCKET"
    key          = "networking-spoke/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
# dev state:     env:/dev/networking-spoke/terraform.tfstate
# staging state: env:/staging/networking-spoke/terraform.tfstate
# prod state:    env:/prod/networking-spoke/terraform.tfstate
```

---

## File Structure

### Standard Module Layout

```
my-module/
├── main.tf          # Primary resource definitions
├── variables.tf     # Input variable declarations
├── outputs.tf       # Output value declarations
├── versions.tf      # Required providers and Terraform version constraint
├── README.md        # Usage, inputs, outputs
└── modules/         # Optional nested modules (only if complexity warrants it)
    └── submodule/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### Root Module (Deployment Config) with Workspaces

```
my-component/
├── main.tf
├── variables.tf
├── outputs.tf
├── locals.tf         # environment = terraform.workspace
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

---

## Resources

### Basic Syntax

```hcl
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"

  tags = {
    Name = "web-server"
  }
}
```

### Meta-Arguments

| Meta-Argument | Purpose | Notes |
|---|---|---|
| `count` | Create N identical resources | Access with `resource.name[index]`; avoid when items can be deleted mid-list |
| `for_each` | Create resources from a map or set | Access with `resource.name[key]`; preferred over `count` for named resources |
| `depends_on` | Explicit ordering dependency | Use only when the implicit dependency graph is insufficient |
| `provider` | Select an aliased provider | Use for multi-region or multi-account resources |
| `lifecycle` | Control create/destroy behavior | Must use literal values, not expressions |

### `count` vs `for_each`

Prefer `for_each` for anything with a meaningful identity (name, id). Use `count` only for truly identical replicas.

```hcl
# Prefer this — stable keys, no index shifting on deletion
resource "aws_iam_user" "team" {
  for_each = toset(["alice", "bob", "carol"])
  name     = each.key
}

# Avoid for named resources — deleting "bob" shifts carol's index
resource "aws_iam_user" "team" {
  count = length(var.users)
  name  = var.users[count.index]
}
```

### Lifecycle Rules

```hcl
resource "aws_db_instance" "main" {
  # ...

  lifecycle {
    # Swap blue/green — create replacement before destroying original
    create_before_destroy = true

    # Block accidental destruction of critical resources
    prevent_destroy = true

    # Don't track changes made outside Terraform (e.g., auto-patching)
    ignore_changes = [engine_version]

    # Trigger replacement when a referenced object changes
    replace_triggered_by = [aws_launch_template.app.id]

    # Validate pre- and post-conditions
    precondition {
      condition     = var.instance_class != "db.t2.micro"
      error_message = "db.t2.micro is not supported in production."
    }
  }
}
```

---

## Variables and Outputs

### Variable Declaration (`variables.tf`)

```hcl
variable "instance_count" {
  type    = number
  default = 1
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "allowed_cidrs" {
  type = list(string)
}

variable "db_config" {
  type = object({
    engine  = string
    version = string
    class   = string
  })
}
```

### Sensitive Variables

```hcl
variable "db_password" {
  type      = string
  sensitive = true  # Redacted from plan/apply output and state display
}
```

### Outputs (`outputs.tf`)

```hcl
output "instance_id" {
  value       = aws_instance.web.id
  description = "The EC2 instance ID"
}

output "db_endpoint" {
  value     = aws_db_instance.main.endpoint
  sensitive = true  # Marks output as sensitive; still stored in state
}
```

---

## Locals

Use locals to name complex expressions once:

```hcl
locals {
  common_tags = merge(var.tags, {
    Environment = local.environment
    ManagedBy   = "terraform"
  })

  name_prefix = "${var.project}-${local.environment}"
}
```

---

## Expressions

### String Interpolation and Heredoc

```hcl
name = "${var.prefix}-web-server"

policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect   = "Allow"
    Action   = ["s3:GetObject"]
    Resource = "arn:aws:s3:::${var.bucket_name}/*"
  }]
})

user_data = <<-EOT
  #!/bin/bash
  echo "Hello from ${local.environment}"
EOT
```

### Conditional Expression

```hcl
instance_type = local.environment == "prod" ? "t3.large" : "t3.micro"
```

### `for` Expressions

```hcl
# Transform a list
upper_names = [for name in var.names : upper(name)]

# Build a map from a list
name_map = { for user in var.users : user.name => user.id }

# Filter a map
active_users = { for k, v in var.users : k => v if v.active }
```

### Splat Expressions

```hcl
# Equivalent to [for o in aws_instance.web : o.id]
instance_ids = aws_instance.web[*].id
```

### Dynamic Blocks

Use to generate repeated nested blocks from a collection — avoid when a `for` expression on a single attribute suffices:

```hcl
resource "aws_security_group" "web" {
  name = "web-sg"

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }
}
```

---

## Providers and Versions

### `versions.tf`

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Multi-region with alias
provider "aws" {
  alias  = "us_west"
  region = "us-west-2"
}
```

---

## Remote State — S3 Backend

### `backend.tf`

```hcl
terraform {
  backend "s3" {
    bucket  = "my-terraform-state"
    key     = "networking-spoke/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true

    # Modern locking (preferred over DynamoDB — no extra table needed)
    use_lockfile = true
  }
}
```

### S3 Backend Checklist

| Requirement | Why |
|---|---|
| Enable S3 bucket versioning | Disaster recovery — roll back corrupt state |
| Enable encryption (`encrypt = true`) | State contains sensitive values in plaintext |
| Use `use_lockfile = true` | Prevents concurrent applies from corrupting state |
| Never hardcode AWS credentials in backend block | They end up in `.terraform/` which may be committed |
| Use workspaces for per-environment state isolation | Blast radius isolation — a bad `prod` apply can't touch `dev` state |

---

## Data Sources

Fetch information about existing infrastructure without managing it:

```hcl
data "aws_vpc" "selected" {
  tags = {
    Name = "production"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
```

---

## Importing Existing Infrastructure

### `import` Block (Terraform 1.5+) — Preferred

```hcl
import {
  id = "i-1234567890abcdef0"
  to = aws_instance.web
}

resource "aws_instance" "web" {
  # Write config matching the existing resource,
  # or use -generate-config-out to scaffold it:
  # terraform plan -generate-config-out=generated.tf
}
```

Generate a resource config scaffold automatically:

```bash
terraform plan -generate-config-out=generated.tf
# Review generated.tf, clean it up, then run terraform apply
```

---

## Refactoring with `moved` Blocks

Rename or restructure resources without destroying and recreating them:

```hcl
# Rename a resource
moved {
  from = aws_instance.web
  to   = aws_instance.app_server
}

# Move a resource into a module
moved {
  from = aws_s3_bucket.logs
  to   = module.logging.aws_s3_bucket.logs
}

# Move count resource to for_each
moved {
  from = aws_iam_user.team[0]
  to   = aws_iam_user.team["alice"]
}
```

Keep `moved` blocks in your codebase until all consumers have applied the change, then remove them.

---

## State Commands

```bash
# List all resources in state
terraform state list

# Show details of a specific resource
terraform state show aws_instance.web

# Remove a resource from state without destroying the real resource
terraform state rm aws_instance.web

# Pull remote state to stdout
terraform state pull

# Refresh state to match real-world infrastructure
terraform apply -refresh-only
```

---

## Workflow Commands

```bash
terraform init          # Initialize, download providers and modules
terraform validate      # Check HCL syntax and internal consistency
terraform fmt           # Format all .tf files in place (run in CI)
terraform plan          # Preview changes; use -out=plan.tfplan for apply
terraform apply         # Apply changes (prompts for confirmation)
terraform apply -auto-approve  # Skip prompt (CI only)
terraform destroy       # Destroy all managed resources
terraform console       # Interactive expression evaluator — great for debugging
terraform output        # Print output values
terraform output -json  # Machine-readable outputs

# Workspace commands
terraform workspace new staging
terraform workspace select prod
terraform workspace list
terraform workspace show    # Show current workspace
```

---

## Best Practices

### Naming and Tagging

```hcl
locals {
  environment = terraform.workspace
  name_prefix = "${var.project}-${local.environment}"
  common_tags = {
    Project     = var.project
    Environment = local.environment
    ManagedBy   = "terraform"
    Repository  = "github.com/myorg/infra"
  }
}
```

### Security

- Never store secrets in `.tfvars` files committed to git — use environment variables (`TF_VAR_db_password`) or a secrets manager
- Mark all secret variables and outputs `sensitive = true`
- Enable S3 bucket versioning and encryption for state
- Use `prevent_destroy = true` on stateful resources (databases, S3 buckets with data)
- Pin provider versions (`~> 6.0`, not `>= 6.0`) to avoid surprise breaking changes

### Code Quality

- Run `terraform fmt` and `terraform validate` in CI
- Use `terraform plan -out=plan.tfplan` then `terraform apply plan.tfplan` in CI/CD pipelines to prevent plan/apply drift
- Keep modules focused — if a module exceeds ~5 resource types, consider splitting it
- Use `moved` blocks instead of manual `terraform state mv` when refactoring
- Use `import` blocks instead of CLI `terraform import` for traceability

### Performance

- Use `for_each` over `count` for resources that might be individually modified or deleted
- Split large configs into smaller state files by component (network, compute, data) to reduce blast radius and plan time
- Use `depends_on` sparingly — prefer implicit dependencies through references

---

## Common Errors

| Error | Cause | Fix |
|---|---|---|
| `Error acquiring the state lock` | Another apply is running, or a previous run crashed | Verify no other apply is running; run `terraform force-unlock <ID>` if stale |
| `Resource already exists` | Resource in cloud but not in state | Use `import` block to bring it under management |
| `Index value required` | Using `for_each` resource but referencing with `[0]` | Use `resource.name["key"]` not `resource.name[0]` |
| `count.index` out of range | List shrank but state still has old instances | Use `terraform state rm` to clean up, or switch to `for_each` |
| `cycle` error | Circular dependency between resources | Introduce an intermediate data source or break the cycle with explicit outputs |
| Backend config changed | Backend config differs from initialized state | Run `terraform init -reconfigure` |
| `│ Error: Unsupported argument` | Provider version doesn't support an attribute | Update provider version or remove the unsupported attribute |
| Module input uses computed value in `toset()` | Some module inputs (e.g. `kms` `aliases`) can't accept computed values | Use the `computed_aliases` (or similar) alternative input instead |
