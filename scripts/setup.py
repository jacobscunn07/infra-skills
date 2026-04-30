#!/usr/bin/env python3
# Run once after cloning this template to fill in all placeholder values.
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent

OLD_ACCOUNTS_TABLE = (
    "| Account Name | Account ID | Primary Region | Secondary Regions |\n"
    "|---|---|---|---|\n"
    "| management | `REPLACE_ME` | us-east-1 | |\n"
    "| dev | `REPLACE_ME` | us-east-1 | |\n"
    "| staging | `REPLACE_ME` | us-east-1 | |\n"
    "| prod | `REPLACE_ME` | us-east-1 | |"
)


def prompt(label, example=None):
    hint = f" (e.g. {example})" if example else ""
    val = input(f"{label}{hint}: ").strip()
    if not val:
        print(f"ERROR: {label} is required.", file=sys.stderr)
        sys.exit(1)
    return val


def read_existing_arn(account_map_path):
    """Return the ARN already written to aws-account-map.md, or None if still a placeholder."""
    for line in account_map_path.read_text().splitlines():
        if "| Role ARN |" in line and "REPLACE_ME" not in line:
            # Extract the backtick-quoted value: | Role ARN | `arn:aws:iam::...` |
            parts = line.split("`")
            if len(parts) >= 2:
                return parts[1]
    return None


def replace_in_file(path, old, new):
    content = path.read_text()
    if old not in content:
        print(f"WARNING: '{old}' not found in {path}", file=sys.stderr)
        return
    path.write_text(content.replace(old, new))


def collect_accounts():
    accounts = []
    print("Enter AWS accounts (at least one required).")
    while True:
        print()
        name = input("  Account name (e.g. management, dev, prod): ").strip()
        if not name:
            print("  Account name is required.", file=sys.stderr)
            continue
        account_id = input(f"  Account ID for '{name}' (12 digits): ").strip()
        if not account_id:
            print(f"ERROR: account ID for '{name}' is required.", file=sys.stderr)
            sys.exit(1)
        accounts.append((name, account_id))
        another = input("  Add another account? [y/N]: ").strip().lower()
        if another != "y":
            break
    return accounts


def build_accounts_table(accounts, region):
    rows = "\n".join(f"| {name} | `{aid}` | {region} | |" for name, aid in accounts)
    return f"| Account Name | Account ID | Primary Region | Secondary Regions |\n|---|---|---|---|\n{rows}"


print()
print("=== infra-skills template setup ===")
print("Fill in each value below to configure this repository for your environment.")
print()

bucket = prompt("Terraform state S3 bucket name")
region = input("Primary AWS region [us-east-1]: ").strip() or "us-east-1"
accounts = collect_accounts()
print()
existing_arn = read_existing_arn(REPO_ROOT / ".claude" / "memory" / "aws-account-map.md")
if existing_arn:
    raw = input(f"OIDC role ARN [{existing_arn}]: ").strip()
    oidc_arn = raw or existing_arn
else:
    oidc_arn = prompt("OIDC role ARN", "arn:aws:iam::<account-id>:role/github-actions-oidc")
github_org = prompt("GitHub org or username", "myorg")

print()
print("Applying substitutions...")

# backend.tf files (tf-testA and tf-testB use local backends — no S3 placeholder)
for project in ("tf-data", "tf-network-spoke"):
    replace_in_file(
        REPO_ROOT / project / "backend.tf",
        "REPLACE_WITH_TERRAFORM_STATE_BUCKET",
        bucket,
    )

# aws-account-map.md
account_map = REPO_ROOT / ".claude" / "memory" / "aws-account-map.md"
replace_in_file(account_map, OLD_ACCOUNTS_TABLE, build_accounts_table(accounts, region))
replace_in_file(account_map, "| Role ARN | `REPLACE_ME`", f"| Role ARN | `{oidc_arn}`")
replace_in_file(account_map, "repo:REPLACE_ME/infra-skills", f"repo:{github_org}/infra-skills")

print()
print("Done. Changes applied:")
print(f'  tf-data/backend.tf          → bucket = "{bucket}"')
print(f'  tf-network-spoke/backend.tf → bucket = "{bucket}"')
print( "  .claude/memory/aws-account-map.md:")
for name, aid in accounts:
    print(f"    {name} → {aid}")
print(f"    OIDC role ARN → {oidc_arn}")
print(f"    GitHub trust policy → repo:{github_org}/infra-skills:*")

print()
print("Next step:")
print("  Run: python3 scripts/setup-github.py")
print("  Creates all terraform/<project>/<workspace> GitHub Environments, sets the")
print("  AWS_ROLE_ARN Actions variable, and optionally adds required reviewers.")
print("  Requires a GitHub personal access token with 'repo' scope.")
