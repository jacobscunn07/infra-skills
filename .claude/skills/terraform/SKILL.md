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

### Root Module (Deployment Config) Layout

```
environments/prod/
├── main.tf          # Module calls and top-level resources
├── variables.tf
├── outputs.tf
├── terraform.tfvars # Actual values (do not commit secrets)
└── backend.tf       # Remote backend configuration
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
variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod)"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

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
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  name_prefix = "${var.project}-${var.environment}"
}

resource "aws_instance" "web" {
  # ...
  tags = local.common_tags
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
  echo "Hello from ${var.environment}"
EOT
```

### Conditional Expression

```hcl
instance_type = var.environment == "prod" ? "t3.large" : "t3.micro"
```

### `for` Expressions

```hcl
# Transform a list
upper_names = [for name in var.names : upper(name)]

# Filter a list
prod_instances = [for i in var.instances : i if i.env == "prod"]

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

## Modules

### Calling a Module

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name_prefix}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
}

# Reference module outputs
resource "aws_instance" "app" {
  subnet_id = module.vpc.private_subnets[0]
}
```

### Local Module

```hcl
module "database" {
  source = "./modules/rds"

  name        = "${local.name_prefix}-db"
  environment = var.environment
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnets
}
```

### Module Design Rules

- One responsibility per module — don't create a "mega-module" for an entire environment
- Pass in all IDs/ARNs as variables — never hardcode resource identifiers inside a module
- Always pin registry modules to a version constraint (`~> 5.0`, not `>= 5.0`)
- Expose outputs for any resource attribute callers might need
- Mark outputs `sensitive = true` if they expose secrets

---

## Providers and Versions

### `versions.tf`

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

resource "aws_s3_bucket" "replica" {
  provider = aws.us_west
  bucket   = "my-replica-bucket"
}
```

---

## Remote State — S3 Backend

### `backend.tf`

```hcl
terraform {
  backend "s3" {
    bucket  = "my-terraform-state"
    key     = "prod/network/terraform.tfstate"
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
| Use separate state files per environment | Blast radius isolation — a bad `prod` apply can't touch `dev` state |

### State File Naming Convention

```
<account>/<region>/<environment>/<component>/terraform.tfstate
# e.g.: 123456789/us-east-1/prod/network/terraform.tfstate
```

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

resource "aws_instance" "app" {
  ami       = data.aws_ami.amazon_linux.id
  subnet_id = data.aws_vpc.selected.id
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

### Legacy CLI Import

```bash
# One-off import — does not add an import block to config
terraform import aws_instance.web i-1234567890abcdef0
```

Use the `import` block approach for new imports — it's repeatable and reviewable in PRs.

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

# Move a resource address within state (pre-1.5 refactor method)
terraform state mv aws_instance.old aws_instance.new

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
```

---

## Workspaces

Workspaces let you use the same configuration for multiple environments with isolated state:

```bash
terraform workspace new staging
terraform workspace select prod
terraform workspace list
```

Reference the current workspace in config:

```hcl
locals {
  env = terraform.workspace  # "default", "staging", "prod"

  instance_type = {
    default = "t3.micro"
    staging = "t3.small"
    prod    = "t3.large"
  }[terraform.workspace]
}
```

> Prefer separate root modules per environment over workspaces for large production setups — workspaces share the same code, which makes environment-specific config awkward and risky.

---

## Best Practices

### Naming and Tagging

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}-${var.region}"
  common_tags = {
    Project     = var.project
    Environment = var.environment
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
- Pin provider versions (`~> 5.0`, not `>= 5.0`) to avoid surprise breaking changes

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
