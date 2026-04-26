#!/usr/bin/env python3
import json
import subprocess
import sys

data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "")

if "git commit" not in cmd:
    sys.exit(0)

result = subprocess.run(
    ["git", "branch", "--show-current"],
    capture_output=True,
    text=True,
)
branch = result.stdout.strip()

if branch in ("main", "master"):
    print(
        f'BLOCKED: Cannot commit directly to the "{branch}" branch. '
        "Create a feature branch first (e.g., git checkout -b <feature-branch>)."
    )
    sys.exit(1)
