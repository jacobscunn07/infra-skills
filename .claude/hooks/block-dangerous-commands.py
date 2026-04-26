#!/usr/bin/env python3
import json
import sys

BLOCKED_PATTERNS = [
    "terraform apply",
    "terraform destroy",
    "terraform force-unlock",
    "aws s3 rb",
    "aws iam delete",
    "aws ec2 terminate-instances",
    "rm -rf",
    "git push --force",
    "kubectl delete namespace",
]

data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "")

for pattern in BLOCKED_PATTERNS:
    if pattern in cmd:
        print(
            f'BLOCKED: "{pattern}" is a guard-railed command. '
            "Human approval required before this action can be taken. Aborting."
        )
        sys.exit(1)
