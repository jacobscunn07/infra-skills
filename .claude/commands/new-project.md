Scaffold a new Terraform project. The project name is available as `$ARGUMENTS` (e.g., `/new-project tf-myapp` or `/new-project myapp`).

Follow these steps exactly:

## 1. Normalize the project name

- Strip a leading `tf-` if present, then re-add it. The canonical directory name is always `tf-<name>`.
- If `$ARGUMENTS` is empty, ask the user for the project name before proceeding.

## 2. Confirm the directory doesn't already exist

Run `ls tf-<name>/` — if it exists, stop and tell the user.

## 3. Ask for workspace names

Ask: "What workspaces does this project use? (e.g. `dev staging prod`)"

Save the response as `$WORKSPACES` (a space-separated list). The last workspace in the list is treated as the production workspace and gets `continuous-deploy: false`; all others get `continuous-deploy: true`.

## 4. Ask for project dependencies

Run `ls -d tf-*/` to list all existing tf-* projects in the repo. Use the `AskUserQuestion` tool with a multi-select (checkboxes) prompt listing each discovered project. Ask: "Which projects does tf-<name> read outputs from via SSM?"

Save the selected projects as `$DEPS` (empty list if none selected).

## 5. Query the Terraform registry for the latest AWS provider version

Use the `terraform-registry` MCP tool `get_latest_provider_version` with `provider_name = "aws"` and `namespace = "hashicorp"`. Save the version string as `$AWS_VERSION` (e.g., `6.2.0`). This version is used in `versions.tf`.

## 6. Create all project files

Create the directory structure and write each file below. Substitute `tf-<name>` and `<name>` throughout. Use the exact content shown — do not add extra resources or abstractions.

---

### `tf-<name>/ci.yaml`

Generate one entry per workspace in `$WORKSPACES`. The last workspace gets `continuous-deploy: false`; all others get `continuous-deploy: true`.

```yaml
enabled: true
aws-credentials: true

workspaces:
  <workspace1>:
    enabled: true
    continuous-deploy: true
  <workspace2>:
    enabled: true
    continuous-deploy: true
  <last-workspace>:
    enabled: true
    continuous-deploy: false

project-dependencies: []
```

If `$DEPS` is non-empty, replace `[]` with the list of dependency names:

```yaml
project-dependencies:
  - tf-network-spoke
```

---

### `tf-<name>/locals.tf`

```hcl
locals {
  environment = terraform.workspace
  name_prefix = "${var.project}-${local.environment}"

  common_tags = {
    Project     = var.project
    Environment = local.environment
    ManagedBy   = "terraform"
  }
}
```

---

### `tf-<name>/versions.tf`

Use `$AWS_VERSION` from step 5. Set `~> X.Y` using the major and minor components.

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> $AWS_MAJOR.$AWS_MINOR"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "ssm"
  region = var.ssm_region

  default_tags {
    tags = local.common_tags
  }
}
```

---

### `tf-<name>/backend.tf`

```hcl
terraform {
  backend "s3" {
    bucket       = "REPLACE_WITH_TERRAFORM_STATE_BUCKET"
    key          = "tf-<name>/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

---

### `tf-<name>/variables.tf`

```hcl
variable "project" {
  description = "Project name used in resource naming and tagging."
  type        = string
}

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "ssm_region" {
  description = "AWS region for SSM Parameter Store outputs."
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# Project-specific variables — add below
# -----------------------------------------------------------------------------
```

---

### `tf-<name>/main.tf`

If `$DEPS` is non-empty, add one `data "aws_ssm_parameter"` block per output needed from each dependency. The SSM path convention is `/<project>/<environment>/<component>/<output-name>`, and values are JSON-encoded with a `value` key.

Example for a dependency on `tf-network-spoke` that exposes a `vpc_id` output:

```hcl
# Outputs from tf-network-spoke read via SSM
data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.project}/${local.environment}/network-spoke/vpc_id"
}

locals {
  vpc_id = jsondecode(data.aws_ssm_parameter.vpc_id.value)["value"]
}
```

Generate one `data` block and one `locals` entry for each specific output this project needs from its dependencies. Ask the user which outputs are needed if unclear.

Always append this stub comment at the end of main.tf:

```hcl
# TODO: Replace the stub below with module calls. Query the terraform-registry
# MCP (search_modules / get_module_details) for the latest community module
# before writing any raw resource blocks.
```

If `$DEPS` is empty, write only the TODO comment.

---

### `tf-<name>/outputs.tf`

```hcl
# TODO: Add outputs here. Mirror each output to SSM in ssm.tf using the pattern:
#
#   resource "aws_ssm_parameter" "<output_name>" {
#     provider = aws.ssm
#     name     = "${local.ssm_prefix}/<output_name>"
#     type     = "String"
#     value    = jsonencode({ value = <module_or_resource>.<output_name> })
#   }
#
# For sensitive values (ARNs, secrets), use type = "SecureString".
```

---

### `tf-<name>/ssm.tf`

```hcl
locals {
  ssm_prefix = "/${var.project}/${local.environment}/<name>"
}

# TODO: Add one aws_ssm_parameter resource per output. See outputs.tf for the pattern.
```

---

### Environment tfvars files

Create `tf-<name>/environments/<workspace>/terraform.tfvars` for each workspace in `$WORKSPACES`:

```hcl
project    = "REPLACE_WITH_PROJECT_NAME"
aws_region = "us-east-1"

# TODO: Add project-specific variable values for <workspace>.
```

---

## 7. Wire the release workflow

Open `.github/workflows/tf-release.yaml` and add a new job block **at the end of the `jobs:` section**, following the exact style of the existing jobs (preserve the separator comment and spacing).

**If `$DEPS` is empty** (no project dependencies):

```yaml
  # ─────────────────────────────────────────────────────────────────────────────
  # tf-<name> has no project-dependencies so it runs as soon as setup completes.
  # Skipped entirely when its deploy flag is false.
  # ─────────────────────────────────────────────────────────────────────────────
  deploy-tf-<name>:
    name: Deploy tf-<name>
    needs: [setup]
    if: fromJSON(needs.setup.outputs.deploy)['tf-<name>']
    uses: ./.github/workflows/_tf-project-release.yaml
    with:
      project: tf-<name>
    secrets: inherit
    permissions:
      id-token: write
      contents: read
      actions: read  # report job needs listJobsForWorkflowRun to resolve job URLs
      checks: read   # summarize job needs listAnnotations for error annotations
```

**If `$DEPS` has exactly one entry** (`$DEP`):

```yaml
  # ─────────────────────────────────────────────────────────────────────────────
  # tf-<name> depends on $DEP (declared in tf-<name>/ci.yaml).  This job
  # waits for deploy-$DEP to finish before starting.
  #
  # always() is required so GitHub does not auto-skip this job when
  # deploy-$DEP is skipped (i.e. when only tf-<name>/ files changed).
  # != 'failure' permits both the success and skipped results while still
  # blocking tf-<name> from deploying if $DEP errored.
  # ─────────────────────────────────────────────────────────────────────────────
  deploy-tf-<name>:
    name: Deploy tf-<name>
    needs: [setup, deploy-$DEP]
    if: |
      always() &&
      fromJSON(needs.setup.outputs.deploy)['tf-<name>'] &&
      needs.deploy-$DEP.result != 'failure'
    uses: ./.github/workflows/_tf-project-release.yaml
    with:
      project: tf-<name>
    secrets: inherit
    permissions:
      id-token: write
      contents: read
      actions: read  # report job needs listJobsForWorkflowRun to resolve job URLs
      checks: read   # summarize job needs listAnnotations for error annotations
```

If `$DEPS` has multiple entries, extend `needs:` and add one `needs.<dep-job-name>.result != 'failure'` clause per dependency.

## 8. Print a completion summary

Output a summary table of what was created:

```
## tf-<name> scaffolded

Files created:
  tf-<name>/ci.yaml
  tf-<name>/locals.tf
  tf-<name>/versions.tf  (hashicorp/aws ~> $AWS_VERSION)
  tf-<name>/backend.tf
  tf-<name>/variables.tf
  tf-<name>/main.tf
  tf-<name>/outputs.tf
  tf-<name>/ssm.tf
  tf-<name>/environments/<workspace>/terraform.tfvars  (one per workspace)

Workflow updated:
  .github/workflows/tf-release.yaml  (added deploy-tf-<name> job)

## Next steps (manual)

1. Fill in all REPLACE_WITH_* placeholders in the tfvars files and backend.tf.
2. Replace the stub in main.tf with real module calls. Query the registry
   first: "Search for a Terraform module for <what this project provisions>."
3. Add outputs to outputs.tf and mirror each one to ssm.tf.
4. Run `python3 scripts/setup-github.py` to create the
   terraform/tf-<name>/<workspace> environments in GitHub.
5. Open a PR — CI will run fmt, validate, and plan automatically.
```
