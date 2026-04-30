#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import sys
import tempfile

data = json.load(sys.stdin)
tool_name = data.get("tool_name")
tool_input = data.get("tool_input", {})

if tool_name == "Write":
    file_path = tool_input.get("file_path", "")
    content = tool_input.get("content", "")
elif tool_name == "Edit":
    file_path = tool_input.get("file_path", "")
    content = tool_input.get("new_string", "")
else:
    sys.exit(0)

if not content:
    sys.exit(0)

if not shutil.which("gitleaks"):
    sys.exit(0)

# Skip internal tooling paths (.claude/hooks, .claude/logs, settings, etc.)
repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
try:
    rel_path = os.path.relpath(file_path, repo_root)
except ValueError:
    sys.exit(0)

if rel_path == ".claude" or rel_path.startswith(".claude" + os.sep):
    sys.exit(0)

# Preserve the original file extension so gitleaks applies file-type rules
_, ext = os.path.splitext(file_path)
with tempfile.TemporaryDirectory() as tmp_dir:
    tmp_file = os.path.join(tmp_dir, os.path.basename(file_path) or "content" + ext)
    with open(tmp_file, "w", encoding="utf-8") as f:
        f.write(content)

    result = subprocess.run(
        ["gitleaks", "detect", "--source", tmp_dir, "--no-git"],
        capture_output=True,
        text=True,
    )

if result.returncode != 0:
    print(f"BLOCKED: gitleaks detected potential secrets in {file_path}:")
    print(result.stdout or result.stderr)
    sys.exit(1)
