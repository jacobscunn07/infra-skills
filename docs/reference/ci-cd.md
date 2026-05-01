# CI/CD Reference

Detailed reference for all GitHub Actions workflows, composite actions, and GitHub Environments in this repo.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [How Project Discovery Works](#how-project-discovery-works)
- [tf-ci — PR Validation](#tf-ci--pr-validation)
- [tf-plan — On-Demand Plan](#tf-plan--on-demand-plan)
- [tf-release — Post-Merge Apply](#tf-release--post-merge-apply)
- [tf-drift — Nightly Drift Detection](#tf-drift--nightly-drift-detection)
- [tf-unlock — Emergency State Unlock](#tf-unlock--emergency-state-unlock)
- [Composite Actions](#composite-actions)
- [GitHub Environments](#github-environments)
- [Secrets & Variables](#secrets--variables)
- [Adding a Project to the Pipeline](#adding-a-project-to-the-pipeline)

---

## Architecture Overview

The CI/CD system has five public workflows, two composite actions, and five reusable `_tf-project-*` workflows.

```
Public workflows (triggered externally)        Reusable workflows (called internally)
─────────────────────────────────────         ──────────────────────────────────────
tf-ci.yaml          PR → main            →    _tf-project-ci.yaml
tf-plan.yaml        workflow_dispatch    →    _tf-project-plan.yaml
tf-release.yaml     push to main         →    _tf-project-release.yaml
tf-drift.yaml       schedule + manual    →    _tf-project-drift.yaml
tf-unlock.yaml      workflow_dispatch         (inline — no reusable wrapper)

Composite actions (called by all workflows)
───────────────────────────────────────────
get-project-workspace-matrix    discovers projects and workspaces
tf-summarize                    writes plan/apply/drift summary tables to job summary
```

Projects and workspaces are discovered at runtime, not hardcoded. The `get-project-workspace-matrix` composite action inspects the repo on each run and emits a GitHub Actions matrix.

The exception is `tf-plan.yaml` and `tf-unlock.yaml`, which have static dropdowns listing each project/workspace combination. These stay in sync via the `sync-workflow-options-on-change` hook when using Claude Code, or manually by running `python3 .github/scripts/sync-workflow-options.py`.

---

## How Project Discovery Works

`get-project-workspace-matrix` is called by every workflow to build the list of projects and workspaces to process.

The action scans the repo root for directories with a `backend.tf` at depth-1. Each is a Terraform project. For each project, workspace names come from subdirectories under `environments/`. The project's `ci.yaml` controls filtering:

- `enabled: false` at the project level skips the entire project
- `enabled: false` at the workspace level skips that workspace
- `continuous-deploy: true/false` controls inclusion in release-only runs
- `aws-credentials: true/false` controls whether OIDC AWS auth is configured for that workspace

### Filtering by changed files

- In `tf-ci` (PR), `base_ref: github.base_ref` is passed, so only projects with files changed relative to the PR's base branch are included
- In `tf-release` (push), `base_sha: github.event.before` is passed, so only projects with files changed since the last commit are included
- In `tf-drift` and `tf-plan`, no base is passed, so all projects run unconditionally

### The `release_only` flag

When `release_only: 'true'` is passed (used by `tf-release`), only workspaces with both `enabled: true` and `continuous-deploy: true` are included. Projects without a `ci.yaml` are skipped.

### Outputs

| Output | Type | Description |
|---|---|---|
| `matrix` | JSON | Array of `{ project, workspace, aws_credentials }` entries |
| `has_changes` | string `"true"/"false"` | Whether the matrix is non-empty; use this to guard dependent jobs — an empty matrix causes a job error rather than a clean skip |

---

## tf-ci — PR Validation

[`.github/workflows/tf-ci.yaml`](../../.github/workflows/tf-ci.yaml) triggers on any PR opened, synchronized, or reopened against `main`.

On each run it:

1. Runs `validate-dropdowns` to check that `tf-plan.yaml` and `tf-unlock.yaml` dropdowns list every project/workspace on disk. Fails the PR if they're out of sync.
2. Runs `setup` to build a matrix of changed projects, grouped by project with all affected workspaces.
3. Calls `_tf-project-ci.yaml` once per changed project (matrix). Each call fans out per-workspace jobs for Checkov security scan (SARIF uploaded to GitHub Advanced Security), `terraform fmt -check`, `terraform validate`, and `terraform plan -lock=false`. Results land in a summary table via `tf-summarize`.

New commits to the PR cancel any in-progress run for the same PR number, avoiding stale plan output and wasted runner minutes.

`fail-fast: false` means all changed projects are validated even when one fails, so all errors surface in a single pass.

Permissions the calling job needs: `id-token: write` (OIDC), `contents: read`, `actions: read`, `checks: read`, `security-events: write` (Checkov SARIF).

---

## tf-plan — On-Demand Plan

[`.github/workflows/tf-plan.yaml`](../../.github/workflows/tf-plan.yaml) triggers via `workflow_dispatch`.

Use it to plan a specific project and workspace without opening a PR. It's useful for spot-checking a workspace or validating a config change before you start.

Select a `project / workspace` from the dropdown. Selecting `/ all` plans every workspace under that project. The dropdown is kept in sync by the `sync-workflow-options-on-change` hook and verified by `validate-dropdowns` in `tf-ci`.

Plans run with `-lock=false` to avoid leaving dangling state locks. No `base_ref`/`base_sha` is passed; this is an unconditional plan, not a diff. The `get-project-workspace-matrix` action fails fast with a clear message if the selected project or workspace doesn't exist on disk.

Permissions needed: `id-token: write`, `contents: read`.

---

## tf-release — Post-Merge Apply

[`.github/workflows/tf-release.yaml`](../../.github/workflows/tf-release.yaml) triggers on every push to `main`.

The `setup` job builds a deploy map: a per-project boolean indicating whether that project has changes to deploy. It uses `release_only: 'true'`, so only `continuous-deploy: true` workspaces are considered. Per-project deploy jobs then call `_tf-project-release.yaml`, which plans the workspace, waits for any required GitHub Environment approval, and applies.

### Dependency ordering

Project jobs express dependencies via `needs:`. If project B depends on project A (declared in `project-dependencies` in `ci.yaml`), B's job lists A's job in `needs:`.

When A has no changes and is skipped, B still needs to run. This is handled with:

```yaml
if: |
  always() &&
  fromJSON(needs.setup.outputs.deploy)['tf-b'] &&
  needs.deploy-tf-a.result != 'failure'
```

`always()` prevents GitHub from auto-skipping B when A was skipped. `!= 'failure'` allows both `success` and `skipped` upstream results while still blocking B if A errored.

### Prod workspaces

Workspaces with `continuous-deploy: false` (prod by default) are excluded from the deploy map and never auto-applied. To deploy prod, trigger `tf-release` manually via `workflow_dispatch` targeting the specific project and workspace.

`cancel-in-progress: false` prevents GitHub from cancelling a release that is already running. Cancelling a partially-applied run risks leaving infrastructure in an inconsistent state.

Permissions needed: `id-token: write`, `contents: read`, `actions: read`, `checks: read`.

---

## tf-drift — Nightly Drift Detection

[`.github/workflows/tf-drift.yaml`](../../.github/workflows/tf-drift.yaml) runs nightly at 02:00 UTC and is also triggerable manually.

The `setup` job discovers all projects and workspaces with no change filter. The `drift` matrix job calls `_tf-project-drift.yaml` per project; each workspace is planned with `-lock=false`. When the plan is non-empty (drift found), a `drift-meta.json` artifact is uploaded.

The `report` job downloads all drift artifacts, builds a summary table, and sends notifications. It runs with `if: always()` so it fires even when matrix jobs fail.

Notification integrations are opt-in via secrets:

- Slack (requires `SLACK_WEBHOOK_URL`): sends a rich block message when drift is found, and a simple all-clear when everything is clean
- Email (requires all six `MAIL_*` secrets): sends an HTML email when drift is found; no all-clear email

If neither is configured, the report job writes the summary to the GitHub Actions job summary page and exits silently.

---

## tf-unlock — Emergency State Unlock

[`.github/workflows/tf-unlock.yaml`](../../.github/workflows/tf-unlock.yaml) triggers via `workflow_dispatch`.

Use it when Terraform refuses to run because the state is locked:

```
Error: Error acquiring the state lock
...
Lock Info:
  ID: <lock-id>
```

Before triggering, confirm no other process is legitimately holding the lock (a plan or apply still in progress). Releasing an active lock while another operation is running can corrupt the state file.

To use it:

1. Copy the lock ID from the Terraform error message
2. Go to Actions → Terraform Force Unlock → Run workflow
3. Select the project/workspace from the dropdown
4. Paste the lock ID and run

Do not run `terraform force-unlock` locally. This workflow uses `dflook/terraform-unlock-state` to release the lock through the same OIDC-authenticated path as all other operations.

See the [State Recovery runbook](../runbooks/state-recovery.md) for the full incident procedure.

---

## Composite Actions

### `get-project-workspace-matrix`

Location: [`.github/actions/get-project-workspace-matrix/`](../../.github/actions/get-project-workspace-matrix/)

Discovers Terraform projects and workspaces and emits a GitHub Actions matrix.

**Inputs:**

| Input | Required | Description |
|---|---|---|
| `base_ref` | no | Base branch ref (e.g. `main`). When set, only projects with changed files relative to this ref are included. Mutually exclusive with `base_sha`. |
| `base_sha` | no | Exact commit SHA to diff against. Takes precedence over `base_ref`. Used by push events where `github.event.before` is available. |
| `project` | no | When set, only this project is included. Fails if the project is not found. |
| `workspace` | no | When set (requires `project`), only this workspace is included. Fails if not found. |
| `release_only` | no | When `"true"`, only `continuous-deploy: true` workspaces are included. Projects without `ci.yaml` are skipped. Default: `"false"`. |

**Outputs:**

| Output | Description |
|---|---|
| `matrix` | JSON matrix: `{ include: [{ project, workspace, aws_credentials }, ...] }` |
| `has_changes` | `"true"` when at least one entry exists; `"false"` otherwise. Guard dependent jobs with this — an empty matrix causes a job error rather than a clean skip. |

---

### `tf-summarize`

Location: [`.github/actions/tf-summarize/`](../../.github/actions/tf-summarize/)

Downloads per-workspace result artifacts and writes a formatted Markdown table to the GitHub Actions job summary.

**Result types:**

| Type | Columns | Notes |
|---|---|---|
| `plan` | workspace, result, add/change/destroy counts | Fetches check-run annotations for error details (truncated to 150 chars) |
| `drift` | workspace, status | Shows "✅ No drift" or "❌ Drift detected" |
| `release` | workspace, result | Shows "✅ Applied" for successful applies |

Skipped jobs (workspace had no changes) appear as "skipped" in the table, not as errors.

---

## GitHub Environments

Every Terraform workspace that needs AWS access is backed by a GitHub Environment named:

```
terraform/<project>/<workspace>
```

For example: `terraform/tf-data/prod`, `terraform/tf-network-spoke/dev`.

The OIDC token subject claim includes the environment name, so the AWS OIDC trust policy must permit it for authentication to succeed. GitHub Environments also support required reviewers. Add reviewers to prod environments to gate applies behind human approval.

Run `python3 scripts/setup-github.py` to create all environments and set `AWS_ROLE_ARN`. Re-run after adding new projects.

To add required reviewers: Repo Settings → Environments → `terraform/<project>/prod` → Required reviewers. Without reviewers, the environment provides the OIDC scope but skips the approval step.

---

## Secrets & Variables

**GitHub Actions secrets**

| Secret | Required | Used by | Purpose |
|---|---|---|---|
| `SLACK_WEBHOOK_URL` | optional | `tf-drift` | Incoming webhook for Slack notifications |
| `MAIL_SERVER` | optional | `tf-drift` | SMTP server hostname |
| `MAIL_PORT` | optional | `tf-drift` | SMTP port (typically 587 or 465) |
| `MAIL_USERNAME` | optional | `tf-drift` | SMTP auth username |
| `MAIL_PASSWORD` | optional | `tf-drift` | SMTP auth password |
| `MAIL_TO` | optional | `tf-drift` | Recipient email address |
| `MAIL_FROM` | optional | `tf-drift` | Sender email address |

Email notifications require all six `MAIL_*` secrets. If any are absent, email is silently skipped.

**GitHub Actions variables**

| Variable | Set by | Used by | Value |
|---|---|---|---|
| `AWS_ROLE_ARN` | `scripts/setup-github.py` | All AWS-authenticated jobs | OIDC role ARN (e.g. `arn:aws:iam::<account-id>:role/github-actions-oidc`) |

---

## Adding a Project to the Pipeline

Claude handles steps 1 and 2 automatically when using Claude Code. Steps 3 and 4 are yours.

**1. Create `ci.yaml`**

Every project needs a `ci.yaml`:

```yaml
enabled: true
aws-credentials: true  # project-level default

workspaces:
  dev:
    enabled: true
    continuous-deploy: true
  staging:
    enabled: true
    continuous-deploy: true
  prod:
    enabled: true
    continuous-deploy: false  # prod never auto-applies

project-dependencies: []  # list other project names this one depends on
```

**2. Sync workflow dropdowns**

The `sync-workflow-options-on-change` hook updates `tf-plan.yaml` and `tf-unlock.yaml` automatically when Claude writes `backend.tf` or `environments/`. To sync manually:

```bash
python3 .github/scripts/sync-workflow-options.py
```

The `validate-dropdowns` job in `tf-ci` will fail any PR where the dropdowns are out of sync.

**3. Add a deploy job to `tf-release.yaml`**

Add a job for the new project in [`.github/workflows/tf-release.yaml`](../../.github/workflows/tf-release.yaml). If the project has no dependencies:

```yaml
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
    actions: read
    checks: read
```

If the project depends on another (e.g., `tf-upstream`), add it to `needs:` and include the `always()` guard:

```yaml
deploy-tf-<name>:
  name: Deploy tf-<name>
  needs: [setup, deploy-tf-upstream]
  if: |
    always() &&
    fromJSON(needs.setup.outputs.deploy)['tf-<name>'] &&
    needs.deploy-tf-upstream.result != 'failure'
  ...
```

**4. Create GitHub Environments**

```bash
GITHUB_TOKEN=ghp_xxx python3 scripts/setup-github.py
```

This creates `terraform/tf-<name>/dev`, `terraform/tf-<name>/staging`, and `terraform/tf-<name>/prod` and updates `AWS_ROLE_ARN`.
