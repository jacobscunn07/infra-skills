#!/usr/bin/env python3
"""Check raw/ for unprocessed files and inject a processing reminder.

Processed entries are tracked in raw/.processed (tab-separated):
  file  <filename>  <sha256>   — local files tracked by content hash
  url   <url>       <date>     — web URLs tracked by last-ingested date

Backward-compat: lines without a tab are parsed as legacy 'name:sha256' format.
"""
import hashlib
import json
import os

repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
raw_dir = os.path.join(repo_root, "raw")
manifest_path = os.path.join(raw_dir, ".processed")

if not os.path.isdir(raw_dir):
    raise SystemExit(0)

processed_hashes = set()
processed_urls = []

if os.path.isfile(manifest_path):
    with open(manifest_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if "\t" in line:
                parts = line.split("\t", 2)
                if len(parts) == 3:
                    kind, identifier, value = parts
                    if kind == "file":
                        processed_hashes.add(value)
                    elif kind == "url":
                        processed_urls.append((identifier, value))
            else:
                # Legacy format: filename:sha256
                parts = line.split(":", 1)
                if len(parts) == 2:
                    processed_hashes.add(parts[1])


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


unprocessed = []
for name in sorted(os.listdir(raw_dir)):
    if name.startswith("."):
        continue
    path = os.path.join(raw_dir, name)
    if not os.path.isfile(path):
        continue
    if sha256(path) not in processed_hashes:
        unprocessed.append(name)

output_parts = []

if unprocessed:
    file_list = "\n".join(f"  - {f}" for f in unprocessed)
    output_parts.append(
        f"Unprocessed files found in raw/:\n{file_list}\n"
        "Process them now by running /process-raw."
    )

if processed_urls:
    url_list = "\n".join(f"  - {url} (ingested {date})" for url, date in processed_urls)
    output_parts.append(f"Previously ingested URLs:\n{url_list}")

if not output_parts:
    raise SystemExit(0)

print(json.dumps({"hookSpecificOutput": "\n\n".join(output_parts)}))
