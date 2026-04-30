---
title: GitHub Actions
tags: [github-actions, cicd, workflows, automation, oidc]
related: ["[[IAM/AWS IAM]]", "[[Concepts/Mermaid Diagrams]]"]
created: 2026-04-29
updated: 2026-04-29
---

## Overview

GitHub Actions automates software workflows directly in a GitHub repository. Workflows are YAML files in `.github/workflows/` that run on GitHub-hosted or self-hosted runners. This repo uses GitHub Actions for the full Terraform CI/CD lifecycle: fmt, validate, plan, apply, drift detection, and state unlock.

## Key Concepts

- **Workflow** — YAML file in `.github/workflows/`; one or more jobs triggered by events.
- **Job** — isolated unit of work; runs on a runner; jobs run in parallel by default unless `needs:` creates ordering.
- **Step** — single task inside a job; either `run:` (shell) or `uses:` (action).
- **Action** — reusable step unit from Marketplace or a local path (`uses: ./actions/my-action`).
- **Runner** — execution host; `ubuntu-latest`, `windows-latest`, `macos-latest` are GitHub-hosted. Self-hosted runners give full environment control.
- **Environment** — named deployment target (e.g., `prod`) with optional protection rules and required reviewers.
- **OIDC** — keyless cloud auth; workflows exchange a short-lived JWT for cloud credentials (AWS, GCP, Azure) — no long-lived secrets stored in GitHub. See [[IAM/AWS IAM]].

## Patterns

**Minimal workflow skeleton**
```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: make test
```

**OIDC authentication to AWS**
```yaml
permissions:
  id-token: write   # required for OIDC
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      aws-region: us-east-1
```
The IAM role's trust policy must allow `token.actions.githubusercontent.com` as the OIDC provider. No static AWS credentials needed.

**Matrix build**
```yaml
strategy:
  matrix:
    node: [18, 20, 22]
    os: [ubuntu-latest, macos-latest]
jobs:
  test:
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node }}
```

**Reusable workflow (caller)**
```yaml
jobs:
  deploy:
    uses: ./.github/workflows/_deploy.yaml
    with:
      environment: prod
    secrets: inherit
```

**Reusable workflow (definition)**
```yaml
on:
  workflow_call:
    inputs:
      environment:
        type: string
        required: true
    secrets:
      AWS_ROLE_ARN:
        required: true
```

**Concurrency — cancel stale runs**
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```
Use on PR workflows to avoid queuing multiple plans for rapid pushes.

**Dependency caching**
```yaml
- uses: actions/cache@v4
  with:
    path: ~/.terraform.d/plugin-cache
    key: ${{ runner.os }}-terraform-${{ hashFiles('**/.terraform.lock.hcl') }}
    restore-keys: ${{ runner.os }}-terraform-
```

**Manual approval via environment**
```yaml
jobs:
  deploy:
    environment: production   # triggers required reviewers gate
    runs-on: ubuntu-latest
```

**Composite action** (`action.yml` in a local directory)
```yaml
name: My Composite Action
runs:
  using: composite
  steps:
    - run: echo "step 1"
      shell: bash
    - uses: actions/checkout@v4
```

## Gotchas

- **Fork PRs don't get secrets** — workflows triggered by a fork's PR run without access to repository secrets by default; use `pull_request_target` carefully (it runs in the base repo context — script injection risk).
- **`GITHUB_TOKEN` scope is repo-only** — it can't push to other repos or call other repos' APIs; use a PAT or GitHub App token for cross-repo operations.
- **`workflow_dispatch` inputs are strings** — even `type: boolean` inputs arrive as the string `"true"`/`"false"`; compare with `== 'true'`, not `== true`.
- **`needs` context only sees direct dependencies** — to access outputs from a non-direct ancestor job, chain `needs` explicitly or pass outputs through intermediate jobs.
- **Concurrency group cancellation kills the runner mid-step** — ensure idempotent steps or use `cancel-in-progress: false` for apply/deploy jobs.
- **`secrets: inherit` only works for reusable workflows** — it does not work for composite actions; composite actions inherit the calling step's environment automatically.
- **Service container hostnames** — service containers (e.g., Postgres) are accessible at the service name as the hostname, not `localhost`, when running inside a job container.
- **Re-run window is 30 days** — after that, a run cannot be re-run and must be triggered fresh.
- **Script injection** — never interpolate `${{ github.event.issue.title }}` or other user-controlled values directly into `run:` scripts; assign to an env var first and reference via `$ENV_VAR`.

## References

- [[IAM/AWS IAM]]
- [[Concepts/Mermaid Diagrams]]
