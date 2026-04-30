#!/usr/bin/env python3
import json
import os
import re
import shutil
import subprocess
import sys

TRIGGER_PATTERNS = ["terraform plan", "terraform validate"]

data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "")

if not any(p in cmd for p in TRIGGER_PATTERNS):
    sys.exit(0)

if not shutil.which("checkov"):
    sys.exit(0)

project = None
chdir_match = re.search(r"-chdir=(\S+)", cmd)
if chdir_match:
    project = chdir_match.group(1)
else:
    cd_match = re.search(r"cd\s+(\S+)", cmd)
    if cd_match:
        project = cd_match.group(1)

if not project:
    sys.exit(0)

repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
config_file = os.path.join(repo_root, ".checkov.yaml")

print(f"Running checkov on {project}...")
result = subprocess.run(
    ["checkov", "--directory", project, "--config-file", config_file, "--output", "cli", "--quiet"],
)

if result.returncode != 0:
    print(f"\nBLOCKED: checkov found HIGH/CRITICAL security findings in {project}.")
    print("Fix the findings above or update .checkov.yaml skip-check before proceeding.")
    sys.exit(1)
