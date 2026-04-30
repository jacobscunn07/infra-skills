Fetch and process a web URL into the wiki knowledge base.

Usage: /process-url [--force] <url>

1. Parse arguments. Extract `--force` flag if present; the remaining token is `<url>`.

2. Read `raw/.processed` and check for an existing `url` entry matching `<url>`.
   - Found and no `--force`: report "Already ingested on <date>. Use --force to re-process." and stop.
   - Found with `--force`: proceed; the existing entry will be updated.
   - Not found: proceed.

3. Fetch `<url>` with WebFetch. If the fetch fails, report the error and stop.

4. Extract key concepts, patterns, and gotchas from the fetched content. Discard navigation chrome, ads, boilerplate, and repeated sidebar content.

5. Choose a category from the taxonomy: networking, iam, compute, storage, database, observability, cicd, or concepts.

6. Find or create `wiki/<category>/<slug>.md` and write or merge content using the wiki page schema from CLAUDE.md.

7. Update `related:` frontmatter in adjacent wiki pages and add wikilinks where appropriate.

8. Append to `wiki/learnings.md` if the session produced new insights.

9. Record the URL in `raw/.processed`:
   - If no existing entry: append `url\t<url>\t<YYYY-MM-DD>` (today's date).
   - If updating (--force): replace the existing `url\t<url>\t<old-date>` line with `url\t<url>\t<YYYY-MM-DD>`.

Never record the URL as processed until its wiki page has been written.
