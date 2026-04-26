Commit all staged and unstaged changes, then push to origin. Follow this workflow exactly:

The command may be invoked with an optional ticket ID argument (e.g., `/git-commit-push INFRA-6`). The argument is available as `$ARGUMENTS`.

1. **Check the current branch.** Run `git branch --show-current`.
   - If the branch is `main` or `master`:
     - Inspect the working tree changes to derive the slug (short, lowercase, hyphen-separated description).
     - If `$ARGUMENTS` is non-empty, use it as the ticket ID without asking the user. Create and switch to the new branch: `git checkout -b <ARGUMENTS>/<slug>`.
     - If `$ARGUMENTS` is empty, ask the user for only the Jira ticket ID (e.g., `INFRA-42`), then create and switch to the new branch: `git checkout -b <TICKET>/<slug>`.
   - If already on a feature branch, proceed.

2. **Inspect the working tree.** Run `git status` and `git diff` to understand what has changed.

3. **Draft a commit message** following Conventional Commits (invoke the `/conventional-commits` skill for format guidance):
   - Type + optional scope: `feat(scope)`, `fix(scope)`, `chore`, `refactor`, etc.
   - Description **must be capitalized** (e.g., `Add ...` not `add ...`).

4. **Surface the proposed commit** — show the branch name, files to be staged, and the full commit message — then wait for explicit confirmation before proceeding.

5. **Stage and commit** once confirmed:
   - Stage relevant files by name (avoid `git add -A` unless all changes should be included).
   - Commit with the confirmed message.

6. **Push** with `git push -u origin <branch>`.
