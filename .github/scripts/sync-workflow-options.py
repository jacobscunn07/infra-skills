#!/usr/bin/env python3
"""
Sync tf-plan.yaml and tf-unlock.yaml dropdown options with tf-* projects on disk.

Usage:
  python3 sync-workflow-options.py          # rewrite files in place
  python3 sync-workflow-options.py --check  # dry-run; exit 1 if files would change
"""

import re
import sys
from pathlib import Path

WORKSPACE_ORDER = {"dev": 0, "staging": 1, "prod": 2}

root = Path(__file__).resolve().parent.parent.parent


def workspace_sort_key(ws):
    return (WORKSPACE_ORDER.get(ws, 99), ws)


def get_projects_and_workspaces():
    result = {}
    for backend in sorted(root.glob("tf-*/backend.tf")):
        project = backend.parent.name
        envs_dir = backend.parent / "environments"
        if not envs_dir.is_dir():
            continue
        workspaces = sorted(
            (p.name for p in envs_dir.iterdir() if p.is_dir()),
            key=workspace_sort_key,
        )
        if workspaces:
            result[project] = workspaces
    return result


def build_options(projects, include_all):
    lines = []
    for project in sorted(projects):
        for ws in projects[project]:
            lines.append(f"{project} / {ws}")
        if include_all:
            lines.append(f"{project} / all")
    return lines


def rewrite_options(content, new_options):
    indent = "          "
    option_lines = "\n".join(f"{indent}- {o}" for o in new_options)
    pattern = r"(        options:\n)((?:          - .+\n)*)"
    replacement = r"\g<1>" + option_lines + "\n"
    new_content, count = re.subn(pattern, replacement, content)
    if count == 0:
        raise ValueError("Could not find options: block to replace")
    return new_content


def sync_file(path, new_options, check_mode):
    original = path.read_text()
    updated = rewrite_options(original, new_options)
    if original == updated:
        return False
    if not check_mode:
        path.write_text(updated)
    return True


check_mode = "--check" in sys.argv
projects = get_projects_and_workspaces()

plan_options = build_options(projects, include_all=True)
unlock_options = build_options(projects, include_all=False)

plan_path = root / ".github/workflows/tf-plan.yaml"
unlock_path = root / ".github/workflows/tf-unlock.yaml"

changed = []
for path, options in [(plan_path, plan_options), (unlock_path, unlock_options)]:
    if sync_file(path, options, check_mode):
        changed.append(str(path.relative_to(root)))

if changed:
    if check_mode:
        print("ERROR: workflow dropdowns are out of sync with projects on disk.")
        print("Run `python3 .github/scripts/sync-workflow-options.py` to fix.\n")
        for f in changed:
            print(f"  {f}")
        sys.exit(1)
    else:
        print("Updated:")
        for f in changed:
            print(f"  {f}")
else:
    print("OK: workflow dropdowns are in sync.")
