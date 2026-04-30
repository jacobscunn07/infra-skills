Check raw/ for unprocessed files and process any that are found.

1. Run `python3 .claude/hooks/check-raw-files.py` to identify unprocessed files.
   - If output is empty, tell the user raw/ is empty and stop.

2. For each unprocessed file, follow the Knowledge Base processing steps in CLAUDE.md:
   - Read the file and extract key concepts, patterns, and gotchas. Discard filler.
   - Choose a category: networking, iam, compute, storage, database, observability, cicd, or concepts.
   - Create or update `wiki/<category>/<slug>.md` using the wiki page schema.
   - Update `related:` frontmatter in adjacent pages and add wikilinks.
   - Append to `wiki/learnings.md` if the session produced new insights.

3. After successfully processing each file, mark it as done in `raw/.processed`:
   - Compute the file's SHA-256 hash: `python3 -c "import hashlib; print(hashlib.sha256(open('raw/<filename>','rb').read()).hexdigest())"`
   - Append a tab-separated line `file\t<filename>\t<sha256>` to `raw/.processed` (create the file if it doesn't exist).

Never mark a file as processed until its wiki page has been written.
