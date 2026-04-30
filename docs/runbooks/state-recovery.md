# State Recovery Runbook

| Field | Value |
|-------|-------|
| **Trigger** | Terraform error: `Error acquiring the state lock` — or corrupted/diverged state discovered in a workspace |
| **Goal** | Release a stuck state lock or restore a known-good state file without data loss, then verify the workspace is plannable again |

---

## Scenario A — Stuck State Lock

### Step A1 — Confirm the Lock is Stuck

A lock is stuck when a previous Terraform operation (plan, apply, or init) was interrupted and did not release it. Do not unlock if you cannot confirm the previous operation finished or failed.

1. Copy the lock ID from the Terraform error message:

   ```
   Error acquiring the state lock

   Lock Info:
     ID:        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
     Path:      env:/prod/tf-network-spoke/terraform.tfstate.tflock
     Operation: OperationTypeApply
     Who:       github-actions@runner-name
     Version:   1.x.x
     Created:   2026-04-29T02:00:00.000000000Z
   ```

2. Check whether the operation that acquired the lock is still running:
   - Go to the **Actions** tab in GitHub and look for a running workflow on the same project/workspace.
   - If a workflow is actively running, **do not unlock** — wait for it to finish or cancel it first.

3. If no workflow is running and the lock age is more than 15 minutes, the lock is stale and safe to release.

---

### Step A2 — Release the Lock via Workflow

> `terraform force-unlock` is blocked by a pre-tool hook in this repo. Use the workflow below — never run it from the terminal.

1. Go to **Actions → Terraform Force Unlock** (`tf-unlock.yaml`) → **Run workflow**.
2. Select the **project** (e.g., `tf-network-spoke`) and **workspace** (e.g., `prod`).
3. Paste the **lock ID** copied in Step A1.
4. Click **Run workflow** and wait for it to complete.

The workflow runs `terraform force-unlock -force <lock-id>` in the correct working directory with proper AWS credentials via OIDC. A successful run prints `Lock released successfully!`.

---

### Step A3 — Verify the Workspace is Plannable

1. Go to **Actions → Terraform Plan** (`tf-plan.yaml`) → **Run workflow**.
2. Select the same project and workspace.
3. Confirm the plan completes without a lock error.

If the plan fails with a new lock error, a second operation may have acquired a lock between steps. Repeat from Step A1.

---

## Scenario B — State File Backup and Restore

Use this when state has diverged from reality (e.g., a partial apply that left resources in an unknown state) or when you need to roll back the state file to a prior version.

> The S3 backend has versioning enabled. Every `terraform apply` writes a new state version. You can restore any previous version without modifying AWS resources.

---

### Step B1 — Identify the Target Version

1. Open the AWS Console → **S3** → navigate to the state bucket.
2. Find the state file for the affected workspace. The path follows the backend `key` with a workspace prefix:

   ```
   env:/<workspace>/<backend-key>
   ```

   Example: `env:/prod/tf-network-spoke/terraform.tfstate`

3. Click **Show versions** (requires S3 Versioning to be enabled on the bucket).
4. Identify the version to restore — use the **Last modified** timestamp to correlate with the known-good apply. Copy the **Version ID**.

---

### Step B2 — Back Up the Current (Broken) State

Before restoring, save the current state in case you need it.

```bash
aws s3 cp \
  "s3://<bucket>/env:/<workspace>/<key>/terraform.tfstate" \
  "./terraform.tfstate.broken-$(date +%Y%m%d%H%M%S)" \
  --region <region>
```

Store this locally. Do not commit it to git — state files contain sensitive resource metadata.

---

### Step B3 — Restore the Prior Version

#### Option 1 — Copy a prior S3 version back as the current version (recommended)

```bash
aws s3api copy-object \
  --bucket <bucket> \
  --copy-source "<bucket>/env:/<workspace>/<key>/terraform.tfstate?versionId=<version-id>" \
  --key "env:/<workspace>/<key>/terraform.tfstate" \
  --region <region>
```

This creates a new version of the object whose content is the prior state — no data is deleted.

#### Option 2 — Upload a local state file

If you have a trusted local copy:

```bash
aws s3 cp \
  ./terraform.tfstate.known-good \
  "s3://<bucket>/env:/<workspace>/<key>/terraform.tfstate" \
  --region <region>
```

---

### Step B4 — Reconcile State with Reality

After restoring, the state may reference resources that were created or destroyed during the failed apply. Run a plan immediately to assess the gap:

1. Go to **Actions → Terraform Plan** (`tf-plan.yaml`) → **Run workflow**.
2. Select the project and workspace.
3. Read the plan diff:

   ```mermaid
   flowchart TD
       A[Plan after restore] --> B{Plan diff?}
       B -- No changes --> C[State is consistent\nNo further action]
       B -- Resources to add/change --> D[Drift from partial apply\nProcedure: drift-remediation.md]
       B -- Resources to destroy --> E[Stop — investigate before applying\nSee Step B5]
   ```

4. If the plan shows only adds/changes, follow [Drift Remediation](drift-remediation.md) — Procedure B.
5. If the plan shows unexpected destroys, do not apply. Escalate before proceeding.

---

### Step B5 — Investigate Unexpected Destroys

A plan showing resource destroys after a state restore means the state file and the real AWS environment have diverged significantly.

1. Check what resources exist in AWS for the affected project (Console or `aws <service> describe-*`).
2. Compare against what the restored state believes exists (`terraform state list` in a local checkout).
3. If a resource exists in AWS but not in state, import it:

   ```bash
   terraform import <resource_address> <aws_resource_id>
   ```

4. If a resource is in state but was already destroyed in AWS, remove the stale state entry:

   ```bash
   terraform state rm <resource_address>
   ```

5. Re-run the plan. Repeat until the plan shows zero unexpected destroys.

---

## Reference

| Item | Location |
|------|----------|
| Force-unlock workflow | [`.github/workflows/tf-unlock.yaml`](../../.github/workflows/tf-unlock.yaml) |
| State bucket | Defined in `backend.tf` for each project |
| Backend key pattern | `env:/<workspace>/<project>/terraform.tfstate` |
| Blocked commands | [`.claude/settings.json`](../../.claude/settings.json) — `hooks.PreToolUse` |
| Drift after restore | [drift-remediation.md](drift-remediation.md) |
