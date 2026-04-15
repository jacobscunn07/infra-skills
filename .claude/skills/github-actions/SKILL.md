---
name: github-actions
description: Use when writing, reviewing, or debugging GitHub Actions workflows or custom actions - triggers, jobs, steps, matrix builds, reusable workflows, composite/JS/Docker actions, secrets, OIDC, permissions, outputs, concurrency, or any GitHub Actions authoring and security decisions
---

# GitHub Actions Expert Skill

Comprehensive GitHub Actions guidance covering workflow authoring, custom action development, reusable workflows, security hardening, and production patterns. Based on the official GitHub Actions documentation.

## When to Use This Skill

**Activate this skill when:**
- Writing or modifying `.github/workflows/*.yml` files
- Authoring custom actions (`action.yml` — composite, JavaScript, or Docker)
- Setting up CI/CD pipelines (build, test, deploy)
- Configuring matrix builds, reusable workflows, or concurrency controls
- Passing data between steps or jobs
- Hardening workflows (pinning actions, OIDC, least-privilege tokens)
- Troubleshooting workflow failures, skipped jobs, or missing permissions

**Don't use this skill for:**
- GitLab CI, CircleCI, or other CI systems
- GitHub App development (different API surface)
- General git or repository management questions

---

## Workflow File Structure

Workflows live in `.github/workflows/` and are YAML files:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read       # Least-privilege default — elevate per job as needed

env:
  NODE_VERSION: "20"   # Workflow-level; available to all jobs

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Node
        uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: npm
      - run: npm ci
      - run: npm test
```

---

## Triggers (`on`)

### Common Triggers

```yaml
on:
  # Push to specific branches or tags
  push:
    branches: [main, "release/**"]
    tags: ["v*"]
    paths-ignore: ["docs/**", "*.md"]

  # Pull request events
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened]

  # Manual trigger with inputs
  workflow_dispatch:
    inputs:
      environment:
        description: Target environment
        required: true
        type: choice
        options: [dev, staging, prod]
      dry-run:
        description: Run without applying changes
        type: boolean
        default: false

  # Scheduled (POSIX cron — minimum 5-minute interval)
  schedule:
    - cron: "0 2 * * 1-5"   # Weekdays at 02:00 UTC

  # Triggered by another workflow completing
  workflow_run:
    workflows: ["Build"]
    types: [completed]
    branches: [main]

  # Called by other workflows (reusable)
  workflow_call:
    inputs:
      environment:
        type: string
        required: true
    secrets:
      deploy-token:
        required: true
    outputs:
      deploy-url:
        value: ${{ jobs.deploy.outputs.url }}
```

### Path Filtering Gotcha

When all changed files are excluded by `paths-ignore`, GitHub marks the workflow as **skipped** (not passed). If branch protection requires the check, use a fallback job:

```yaml
on:
  push:
    paths:
      - "src/**"

jobs:
  test:
    if: ${{ github.event_name != 'push' || contains(github.event.head_commit.modified, 'src/') }}
    runs-on: ubuntu-latest
    steps:
      - run: npm test
```

---

## Jobs

```yaml
jobs:
  build:
    name: Build Application        # Display name in UI
    runs-on: ubuntu-latest
    timeout-minutes: 30            # Prevent hung jobs (default is 6 hours)
    permissions:
      contents: read
      packages: write
    environment: production        # Requires reviewer approval if configured
    concurrency:
      group: deploy-${{ github.ref }}
      cancel-in-progress: true     # Cancel older runs on new push
    env:
      APP_ENV: production
    outputs:
      version: ${{ steps.tag.outputs.version }}
    steps:
      - uses: actions/checkout@v4
      - id: tag
        run: echo "version=$(git describe --tags)" >> "$GITHUB_OUTPUT"
```

### Job Dependencies with `needs`

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps: [...]

  test:
    needs: build                   # Runs after build completes
    runs-on: ubuntu-latest
    steps: [...]

  deploy:
    needs: [build, test]           # Waits for both
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps: [...]

  notify:
    needs: [deploy]
    if: always()                   # Runs even if deploy failed
    runs-on: ubuntu-latest
    steps:
      - run: echo "Deploy result: ${{ needs.deploy.result }}"
```

### `needs` Results

| Value | Meaning |
|---|---|
| `success` | All upstream jobs passed |
| `failure` | One or more upstream jobs failed |
| `cancelled` | One or more upstream jobs were cancelled |
| `skipped` | All upstream jobs were skipped |

---

## Steps

```yaml
steps:
  # Use a published action
  - name: Checkout
    uses: actions/checkout@v4     # Always pin to a version tag or SHA
    with:
      fetch-depth: 0              # Full history (needed for git describe)

  # Run a shell command
  - name: Build
    run: |
      npm ci
      npm run build
    working-directory: ./frontend
    shell: bash

  # Conditional step
  - name: Deploy
    if: github.ref == 'refs/heads/main' && success()
    run: ./deploy.sh
    env:
      DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}

  # Continue even if this step fails
  - name: Lint (non-blocking)
    run: npm run lint
    continue-on-error: true
```

---

## Passing Data Between Steps and Jobs

### Step Outputs (`GITHUB_OUTPUT`)

```yaml
steps:
  - name: Compute version
    id: version                    # id is required to reference outputs
    run: |
      VERSION=$(cat VERSION)
      echo "value=${VERSION}" >> "$GITHUB_OUTPUT"
      echo "tag=v${VERSION}" >> "$GITHUB_OUTPUT"

  - name: Use version
    run: echo "Building ${{ steps.version.outputs.tag }}"
```

### Set Environment Variables Mid-Job (`GITHUB_ENV`)

```yaml
steps:
  - name: Set variables
    run: |
      echo "BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$GITHUB_ENV"

  - name: Use variable
    run: echo "Built at $BUILD_TIME"   # Available as env var in subsequent steps
```

### Add to PATH (`GITHUB_PATH`)

```yaml
- run: echo "$HOME/.local/bin" >> "$GITHUB_PATH"
```

### Step Summary (`GITHUB_STEP_SUMMARY`)

```yaml
- name: Write summary
  run: |
    echo "## Deployment Results" >> "$GITHUB_STEP_SUMMARY"
    echo "| Env | Status |" >> "$GITHUB_STEP_SUMMARY"
    echo "|-----|--------|" >> "$GITHUB_STEP_SUMMARY"
    echo "| prod | ✅ |" >> "$GITHUB_STEP_SUMMARY"
```

### Job Outputs (passed via `needs`)

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image-tag: ${{ steps.tag.outputs.value }}
    steps:
      - id: tag
        run: echo "value=sha-${{ github.sha }}" >> "$GITHUB_OUTPUT"

  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - run: echo "Deploying ${{ needs.build.outputs.image-tag }}"
```

### File Artifacts (between jobs)

```yaml
jobs:
  build:
    steps:
      - run: npm run build
      - uses: actions/upload-artifact@v4
        with:
          name: dist
          path: dist/
          retention-days: 1

  deploy:
    needs: build
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: dist
          path: dist/
```

---

## Matrix Builds

```yaml
jobs:
  test:
    strategy:
      fail-fast: false             # Don't cancel other matrix jobs on failure
      max-parallel: 4
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
        node: ["18", "20", "22"]
        exclude:
          - os: windows-latest
            node: "18"
        include:
          - os: ubuntu-latest
            node: "20"
            experimental: true    # Add extra properties to a specific combo
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node }}
```

---

## Concurrency

```yaml
# Cancel in-progress runs for the same branch on new push
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

# For deployments: queue rather than cancel
concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: false       # Wait for previous deploy to finish
```

---

## Environment Variables and Contexts

### Context Objects

| Context | Use Case | Example |
|---|---|---|
| `github` | Event metadata, repo info, SHA | `${{ github.sha }}`, `${{ github.event_name }}` |
| `env` | Variables set via `env:` key | `${{ env.NODE_VERSION }}` |
| `vars` | Repo/org configuration variables (non-secret) | `${{ vars.DEPLOY_URL }}` |
| `secrets` | Encrypted secrets | `${{ secrets.API_KEY }}` |
| `steps` | Outputs from completed steps (requires `id:`) | `${{ steps.build.outputs.tag }}` |
| `needs` | Outputs/results from upstream jobs | `${{ needs.build.outputs.image }}` |
| `matrix` | Current matrix combination values | `${{ matrix.os }}` |
| `runner` | Runner info | `${{ runner.os }}`, `${{ runner.temp }}` |
| `inputs` | `workflow_dispatch` or `workflow_call` inputs | `${{ inputs.environment }}` |
| `job` | Current job status | `${{ job.status }}` |

### Useful `github` Context Properties

```
github.sha              Full commit SHA
github.ref              Branch/tag ref (refs/heads/main)
github.head_ref         Source branch (PR only)
github.base_ref         Target branch (PR only)
github.event_name       push | pull_request | workflow_dispatch | ...
github.actor            User who triggered the workflow
github.repository       owner/repo
github.run_id           Unique run ID
github.run_number       Sequential run counter
github.workspace        Runner checkout path
github.token            GITHUB_TOKEN (prefer secrets.GITHUB_TOKEN for clarity)
```

---

## Reusable Workflows

### Definition (`.github/workflows/deploy.yml`)

```yaml
on:
  workflow_call:
    inputs:
      environment:
        type: string
        required: true
      image-tag:
        type: string
        required: true
    secrets:
      deploy-token:
        required: true
    outputs:
      deploy-url:
        description: URL of the deployed environment
        value: ${{ jobs.deploy.outputs.url }}

jobs:
  deploy:
    runs-on: ubuntu-latest
    outputs:
      url: ${{ steps.deploy.outputs.url }}
    steps:
      - id: deploy
        run: |
          URL=$(./deploy.sh ${{ inputs.environment }} ${{ inputs.image-tag }})
          echo "url=$URL" >> "$GITHUB_OUTPUT"
        env:
          TOKEN: ${{ secrets.deploy-token }}
```

### Caller

```yaml
jobs:
  call-deploy:
    uses: ./.github/workflows/deploy.yml      # Same repo
    # uses: myorg/infra/.github/workflows/deploy.yml@main  # External repo
    with:
      environment: production
      image-tag: ${{ needs.build.outputs.tag }}
    secrets:
      deploy-token: ${{ secrets.PROD_DEPLOY_TOKEN }}
    # Or inherit all secrets:
    # secrets: inherit
```

### Reusable Workflow Limits

- Max 10 levels of nesting (caller + 9 reusable levels)
- Permissions can only be maintained or reduced, never elevated in nested calls
- `secrets: inherit` does not pass environment-level secrets

---

## Custom Actions

### Composite Action (`action.yml`)

Best for: bundling multiple workflow steps into a reusable unit; works on all OS.

```yaml
name: Setup and Build
description: Install dependencies and build the project
inputs:
  node-version:
    description: Node.js version
    required: false
    default: "20"
  working-directory:
    description: Directory to run commands in
    required: false
    default: "."
outputs:
  build-path:
    description: Path to the build output
    value: ${{ steps.build.outputs.path }}

runs:
  using: composite
  steps:
    - uses: actions/setup-node@v4
      with:
        node-version: ${{ inputs.node-version }}
        cache: npm
        cache-dependency-path: ${{ inputs.working-directory }}/package-lock.json

    - id: build
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      run: |
        npm ci
        npm run build
        echo "path=${{ inputs.working-directory }}/dist" >> "$GITHUB_OUTPUT"
```

### JavaScript Action (`action.yml`)

Best for: complex logic, API calls, cross-platform. Runs directly on runner (fast).

```yaml
name: My JS Action
description: Does something useful
inputs:
  token:
    description: GitHub token
    required: true
outputs:
  result:
    description: The computed result

runs:
  using: node20
  main: dist/index.js     # Bundle with @vercel/ncc — commit dist/ to the repo
  post: dist/cleanup.js   # Optional cleanup step
  post-if: always()
```

### Docker Action (`action.yml`)

Best for: specific runtime dependencies, consistent environment. Linux runners only.

```yaml
name: My Docker Action
description: Runs in a container
inputs:
  input-file:
    description: File to process
    required: true

runs:
  using: docker
  image: Dockerfile
  args:
    - ${{ inputs.input-file }}
```

### Action Type Comparison

| Type | Speed | OS Support | Use When |
|---|---|---|---|
| Composite | Medium | All | Bundling workflow steps, shell scripts |
| JavaScript (node20) | Fast | All | Complex logic, GitHub API calls |
| Docker | Slow | Linux only | Specific runtime/tool versions required |

---

## Permissions

### Least-Privilege Pattern

```yaml
# Set restrictive default at workflow level
permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    # Inherits contents: read from workflow level

  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write        # Elevate only for the job that needs it
      packages: write

  comment-pr:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write   # Only what this job needs
```

### Common Permission Scopes

| Scope | Common Need |
|---|---|
| `contents: read` | Checkout code |
| `contents: write` | Create releases, push tags |
| `packages: write` | Push to GitHub Container Registry (GHCR) |
| `pull-requests: write` | Post PR comments |
| `issues: write` | Create/comment on issues |
| `id-token: write` | OIDC authentication to cloud providers |
| `checks: write` | Create check runs |
| `deployments: write` | Create deployment records |

---

## Security Best Practices

### Pin Third-Party Actions to a Full SHA

```yaml
# Vulnerable — a tag can be moved
- uses: actions/checkout@v4

# Secure — immutable reference (audit the SHA before using)
- uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
```

### Prevent Script Injection

```yaml
# DANGEROUS — PR title injected directly into shell
- run: echo "PR title: ${{ github.event.pull_request.title }}"

# SAFE — pass through env var, shell treats as data not code
- run: echo "PR title: $TITLE"
  env:
    TITLE: ${{ github.event.pull_request.title }}
```

### `pull_request_target` Warning

`pull_request_target` runs in the context of the base repo with **write access**, even for PRs from forks. Never check out and run untrusted code in a `pull_request_target` workflow:

```yaml
# DANGEROUS — runs forked code with write token
on: pull_request_target
jobs:
  test:
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha }}
      - run: npm test   # Attacker controls this

# SAFE pattern — separate workflows for privileged and unprivileged work
on: pull_request_target
jobs:
  label:
    permissions:
      pull-requests: write   # Safe: no code checkout
    steps:
      - uses: actions/labeler@v5
```

### OIDC — Cloud Auth Without Long-Lived Credentials

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsRole
          aws-region: us-east-1
          # No long-lived AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY needed
```

### Secrets Handling

- Never log secrets — GitHub auto-redacts known secrets, but derived values are not masked
- Mask derived secrets explicitly: `echo "::add-mask::$DERIVED_VALUE"`
- Don't store structured data (JSON/YAML) as a single secret — split into individual secrets
- Use environment-level secrets for deployment credentials — they require reviewer approval

---

## Services (Integration Testing)

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: testpassword
          POSTGRES_DB: testdb
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432
      redis:
        image: redis:7
        options: --health-cmd "redis-cli ping" --health-interval 10s
        ports:
          - 6379:6379
    steps:
      - run: npm test
        env:
          DATABASE_URL: postgresql://postgres:testpassword@localhost:5432/testdb
          REDIS_URL: redis://localhost:6379
```

---

## Common Workflow Patterns

### CI — Build, Test, Lint

```yaml
on:
  pull_request:
  push:
    branches: [main]

jobs:
  ci:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: npm
      - run: npm ci
      - run: npm run lint
      - run: npm test -- --coverage
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: coverage
          path: coverage/
```

### Build and Push Container Image

```yaml
on:
  push:
    branches: [main]

permissions:
  contents: read
  packages: write

jobs:
  build-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=sha,format=long
            type=ref,event=branch
      - uses: docker/build-push-action@v6
        with:
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### Release with Changelog

```yaml
on:
  push:
    tags: ["v*"]

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
```

---

## Expressions and Functions

```yaml
# Status functions (use in if: conditions)
if: success()           # Previous steps all passed (default)
if: failure()           # At least one previous step failed
if: always()            # Always run (cancelled, failed, or passed)
if: cancelled()         # Workflow was cancelled

# Combining conditions
if: success() && github.ref == 'refs/heads/main'
if: failure() || cancelled()

# Context comparisons
if: github.event_name == 'push'
if: contains(github.ref, 'release')
if: startsWith(github.ref, 'refs/tags/v')
if: needs.build.result == 'success'

# String functions
${{ format('Hello {0}!', github.actor) }}
${{ join(matrix.os, ', ') }}
${{ toJSON(github.event) }}           # Debug: dump full event payload
${{ fromJSON(steps.meta.outputs.json).tags[0] }}
```

---

## Debugging

```yaml
# Enable debug logging — set secret ACTIONS_STEP_DEBUG=true
# Or add this step to dump context
- name: Dump context
  run: echo '${{ toJSON(github) }}'

# Re-run with debug logging from the UI:
# Actions tab → select failed run → Re-run jobs → Enable debug logging
```

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| Forgetting `id:` on a step whose output you need | Add `id: my-step` to the step |
| Using `${{ secrets.X }}` in `run:` directly | Pass through `env:` to prevent injection |
| Pinning to a tag (`@v4`) for security | Pin to a full SHA for third-party actions |
| Using `pull_request_target` + code checkout | Separate privileged and code-running jobs |
| `cancel-in-progress: true` on deployments | Use `false` for deployments to avoid partial deploys |
| No `timeout-minutes` on long-running jobs | Add `timeout-minutes: 30` to avoid 6-hour hangs |
| Exposing secrets in `GITHUB_STEP_SUMMARY` | Check output content before writing to summary |
| `paths-ignore` blocking required status check | Add a fallback always-passing job |
