#!/usr/bin/env python3
import json
import os
import sys

data = json.load(sys.stdin)

if data.get("tool_name") != "Write":
    sys.exit(0)

file_path = data.get("tool_input", {}).get("file_path", "")
parts = file_path.split(os.sep)

if "raw" not in parts:
    sys.exit(0)

filename = os.path.basename(file_path)

print(json.dumps({
    "hookSpecificOutput": (
        f"New file written to raw/: {filename}\n"
        "Process it now per the Knowledge Base section of CLAUDE.md:\n"
        "1. Read the file and extract key concepts, patterns, and gotchas.\n"
        "2. Determine the correct wiki/ category (networking, iam, compute, storage, database, observability, cicd, or concepts).\n"
        "3. Create or update wiki/<category>/<slug>.md using the wiki page schema.\n"
        "4. Add wikilinks in related pages.\n"
        "5. Append to wiki/learnings.md if the session produced new insights."
    )
}))
