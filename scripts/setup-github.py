#!/usr/bin/env python3
"""
Configure GitHub-side setup for this repository:
  1. Creates GitHub Environments for all enabled Terraform projects and workspaces.
  2. Sets the AWS_ROLE_ARN Actions variable (read from .claude/memory/aws-account-map.md).

Environment naming: terraform/<project>/<workspace>
Discovered from:    tf-*/ci.yaml files in the repository root

Run after python3 scripts/setup.py (which fills in the OIDC role ARN).

Usage:
    GITHUB_TOKEN=ghp_xxx python3 scripts/setup-github.py
    GITHUB_TOKEN=ghp_xxx DRY_RUN=1 python3 scripts/setup-github.py

Requires a GitHub personal access token with 'repo' scope (Settings → Developer settings →
Personal access tokens). The token is read from GITHUB_TOKEN env var or prompted interactively.

Safe to re-run: environments are upserted (PUT), variable is upserted (PATCH/POST).
"""

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
API_BASE = "https://api.github.com"


def get_owner_repo():
    try:
        url = subprocess.check_output(
            ["git", "remote", "get-url", "origin"],
            cwd=REPO_ROOT,
            text=True,
        ).strip()
    except subprocess.CalledProcessError:
        print("ERROR: Could not get git remote URL.", file=sys.stderr)
        sys.exit(1)

    m = re.match(r"https://github\.com/([^/]+)/([^/]+?)(?:\.git)?$", url)
    if m:
        return m.group(1), m.group(2)
    m = re.match(r"git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$", url)
    if m:
        return m.group(1), m.group(2)

    print(f"ERROR: Could not parse GitHub owner/repo from remote URL: {url}", file=sys.stderr)
    sys.exit(1)


def parse_ci_yaml(path):
    """
    Return list of enabled workspace names, or None if the project is disabled.
    Parses only the fields we need; avoids a PyYAML dependency.
    """
    content = path.read_text()

    m = re.search(r"^enabled:\s*(true|false)", content, re.MULTILINE)
    if m and m.group(1) == "false":
        return None

    workspaces = []
    in_workspaces = False
    current_ws = None
    ws_enabled = False

    for line in content.splitlines():
        if re.match(r"^workspaces:\s*$", line):
            in_workspaces = True
            continue

        if in_workspaces:
            if line and not line[0].isspace() and ":" in line:
                if current_ws and ws_enabled:
                    workspaces.append(current_ws)
                in_workspaces = False
                current_ws = None
                continue

            ws_match = re.match(r"^  ([\w][\w-]*):\s*$", line)
            if ws_match:
                if current_ws and ws_enabled:
                    workspaces.append(current_ws)
                current_ws = ws_match.group(1)
                ws_enabled = False
                continue

            enabled_match = re.match(r"^    enabled:\s*(true|false)", line)
            if enabled_match and current_ws:
                ws_enabled = enabled_match.group(1) == "true"

    if current_ws and ws_enabled:
        workspaces.append(current_ws)

    return workspaces


def discover_environments():
    envs = []
    for ci_path in sorted(REPO_ROOT.glob("tf-*/ci.yaml")):
        project = ci_path.parent.name
        workspaces = parse_ci_yaml(ci_path)
        if workspaces is None:
            continue
        for ws in workspaces:
            envs.append((project, ws))
    return envs


def github_request(method, path, token, body=None):
    url = f"{API_BASE}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body_text = e.read().decode()
        print(f"ERROR: GitHub API {method} {url} → {e.code}: {body_text}", file=sys.stderr)
        sys.exit(1)


def read_oidc_arn():
    """Read the OIDC role ARN from aws-account-map.md; return None if still a placeholder."""
    account_map = REPO_ROOT / ".claude" / "memory" / "aws-account-map.md"
    for line in account_map.read_text().splitlines():
        if "| Role ARN |" in line and "REPLACE_ME" not in line:
            parts = line.split("`")
            if len(parts) >= 2:
                return parts[1]
    return None


def upsert_actions_variable(owner, repo, name, value, token, dry_run):
    path = f"/repos/{owner}/{repo}/actions/variables/{name}"
    if dry_run:
        print(f"  [dry-run] upsert variable {name}={value}")
        return
    # Try PATCH first (update); fall back to POST (create) on 404.
    req = urllib.request.Request(
        f"{API_BASE}{path}",
        data=json.dumps({"name": name, "value": value}).encode(),
        method="PATCH",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        },
    )
    try:
        urllib.request.urlopen(req)
        print(f"  updated  variable {name}")
    except urllib.error.HTTPError as e:
        if e.code != 404:
            print(f"ERROR: GitHub API PATCH {path} → {e.code}: {e.read().decode()}", file=sys.stderr)
            sys.exit(1)
        # Variable doesn't exist yet — create it.
        github_request("POST", f"/repos/{owner}/{repo}/actions/variables", token, {"name": name, "value": value})
        print(f"  created  variable {name}")


def get_user_id(username, token):
    result = github_request("GET", f"/users/{urllib.parse.quote(username)}", token)
    return result["id"]


def create_environment(owner, repo, env_name, reviewer_ids, token, dry_run):
    path = f"/repos/{owner}/{repo}/environments/{urllib.parse.quote(env_name, safe='')}"
    body = {}
    if reviewer_ids:
        body["reviewers"] = [{"type": "User", "id": uid} for uid in reviewer_ids]
    if dry_run:
        reviewers = f"reviewers={reviewer_ids}" if reviewer_ids else "no reviewers"
        print(f"  [dry-run] PUT {path}  ({reviewers})")
        return
    github_request("PUT", path, token, body)
    print(f"  created  terraform/{env_name.split('terraform/')[1]}")


def main():
    dry_run = os.environ.get("DRY_RUN", "").lower() in ("1", "true", "yes")

    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not token and not dry_run:
        token = input("GitHub token (repo scope): ").strip()
        if not token:
            print("ERROR: GITHUB_TOKEN is required.", file=sys.stderr)
            sys.exit(1)

    owner, repo = get_owner_repo()
    envs = discover_environments()

    if not envs:
        print("No enabled projects/workspaces found. Nothing to do.")
        return

    print()
    print(f"Repository : {owner}/{repo}")
    print(f"Environments to create ({len(envs)}):")
    for project, ws in envs:
        print(f"  terraform/{project}/{ws}")

    print()
    reviewer_ids = []
    if not dry_run:
        print("Required reviewers (optional).")
        print("Reviewers must approve before terraform apply runs. Press Enter to skip.")
        while True:
            username = input("  GitHub username (or Enter to finish): ").strip()
            if not username:
                break
            uid = get_user_id(username, token)
            reviewer_ids.append(uid)
            print(f"    resolved {username} → id {uid}")
        print()

    if dry_run:
        print("Dry-run mode — no API calls will be made:")
    else:
        print("Creating environments...")

    for project, ws in envs:
        env_name = f"terraform/{project}/{ws}"
        create_environment(owner, repo, env_name, reviewer_ids, token, dry_run)

    print()
    oidc_arn = read_oidc_arn()
    if oidc_arn:
        print("Setting AWS_ROLE_ARN Actions variable...")
        upsert_actions_variable(owner, repo, "AWS_ROLE_ARN", oidc_arn, token, dry_run)
    else:
        print("WARNING: OIDC role ARN not set in .claude/memory/aws-account-map.md.")
        print("         Run python3 scripts/setup.py first, then re-run this script.")

    print()
    if dry_run:
        print("Dry run complete. Remove DRY_RUN=1 to apply.")
    else:
        print(f"Done. {len(envs)} environment(s) created/updated.")
        if not reviewer_ids:
            print()
            print("Note: No required reviewers were set. Environments exist but terraform apply")
            print("      will not require approval until reviewers are added in:")
            print("      Repo Settings → Environments → <environment name> → Required reviewers")


if __name__ == "__main__":
    main()
