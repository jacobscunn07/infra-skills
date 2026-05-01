#!/usr/bin/env python3
"""
PostToolUse hook: re-sync workflow dropdown options whenever a backend.tf or
environments/ file is written inside a tf-* project.
"""

import json
import os
import re
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

data = json.load(sys.stdin)
file_path = data.get("tool_input", {}).get("file_path", "")

try:
    rel = os.path.relpath(file_path, REPO_ROOT)
except ValueError:
    sys.exit(0)

if not (
    re.match(r"tf-[^/]+/backend\.tf$", rel)
    or re.match(r"tf-[^/]+/environments/", rel)
):
    sys.exit(0)

script = os.path.join(REPO_ROOT, ".github", "scripts", "sync-workflow-options.py")
result = subprocess.run(["python3", script], capture_output=True, text=True, cwd=REPO_ROOT)
output = (result.stdout + result.stderr).strip()
if output:
    print(output)
