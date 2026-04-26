#!/usr/bin/env python3
import datetime
import json
import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LOG_FILE = os.path.join(REPO_ROOT, ".claude", "logs", "tool-activity.log")

data = json.load(sys.stdin)
tool_name = data.get("tool_name", "Unknown")
tool_input = data.get("tool_input", {})
ts = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

if tool_name == "Bash":
    cmd = tool_input.get("command", "?")
    parts = cmd.split()
    proj = next(
        (os.path.basename(parts[i + 1].rstrip("/")) for i, p in enumerate(parts[:-1]) if p == "cd"),
        "unknown",
    )
    chdir = next((p.split("=", 1)[1].rstrip("/") for p in parts if p.startswith("-chdir=")), "")
    if chdir:
        proj = os.path.basename(chdir)
    tf_flag = f" [project:{proj}]" if any(t in cmd for t in ["terraform", "tofu"]) else ""
    line = f"{ts} [TOOL:Bash]{tf_flag} {cmd[:200]}\n"
else:
    fp = tool_input.get("file_path", "?")
    rel = fp.replace(REPO_ROOT + "/", "")
    proj = rel.split("/")[0] if "/" in rel else "root"
    line = f"{ts} [TOOL:{tool_name}] [project:{proj}] {fp}\n"

with open(LOG_FILE, "a") as f:
    f.write(line)
