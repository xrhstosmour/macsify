# Versioning

## Commits

### Format

- Single-line messages only with no body/description, no bullet lists in message.
- Descriptive, without agent co-authors.
- Use project-scoped prefixes or general descriptions.

### Style

- Use imperative mood: "Add feature" not "Added feature" or "Adds feature".
- Use present tense: "Fix bug" not "Fixed bug" or "Fixes bug".
- Avoid punctuation at the end of the message.
- Avoid generic messages like "Update README.md" or "Fix bug". Be specific about what was changed and why.
- Avoid using the same commit message for multiple commits. Each commit should have a unique message that clearly describes the change made.
- Wrap in backticks: technical identifiers, code elements, file names and paths, product/company/tool names. Use plain backtick characters, never escaped sequences. Verify with `git log -1 --format="%s"` after committing.
- Leave unformatted: natural language words, headings, `YAML` frontmatter fields.
- For commit messages and Git platform text such as PR titles, PR bodies, and review comments, use short, direct language per `~/.config/agentic/instructions/communication.md`.
- Use single-word project scopes followed by a colon, but only when the repo name does not already match that scope. Skip the prefix when committing inside the matching project's own repo. Keep backticks around sub-components, files, and tools within the project.

```text
Add `Sentry` integration
Fix `APIEndpoint` timeout
Rename `utils` file to `utilities`
Add tests for `User` model
Update `README.md` with setup instructions
`opencode`: Update `resolve-pr-comments` skill
`DHL`: Add new endpoint for courier pickup capabilities
`macsify`: Refactor `WindowManager` to use `NSScreen`
Add CI detection and direct database fallback to setup.sh
Delegate test job setup to Copier tasks via env block
Remove redundant `alembic` and `initial_data` from `prestart.sh`
```

### Structure

- One topic per commit. Never mix different contexts.
- Split by context, include tests in same commit as code.
- Target ~100 lines per commit. Split commits over ~300 lines.
- Use `fixup` commits for review comment fixes, typos, small oversights.
- Use `amend` for single-commit changes.

```bash
git add <file> && git commit --fixup <SHA>
git rebase -i --autosquash master
git commit --amend --no-edit
```

### Git safety

- Never force-push to `main` or `master`
- Never commit `.env`, secrets, credentials. Warn immediately if staged.
- Never commit, push, or open a PR unless explicitly asked by the user.

### Fixups

Target only original commits. NEVER fixup a fixup.

Rules:

- Target must be in `<base>..HEAD`
- One target per fixup. Never mix hunks from different `SHA`s
- Use `git add -p` to split hunks
- Uncertain mapping: stop and clarify
- New work (no valid target): use regular commit
- Push with `--force-with-lease`
- Resolve target `SHA` from current branch history by path: `git log --format="%H %s" <base>..HEAD -- <path>`
- Primary target is the latest original commit in range touching that path
- If ambiguous, use line-level tie-breaker: `git blame -L <line>,<line> <path>`
- Do not rely only on external metadata (e.g. PR `originalCommit.oid`)
- Do not infer target by comment order
- Exactly one fixup commit per target `SHA`
- Multiple comments can share one fixup if they map to the same target `SHA`
- Never mix files mapped to different target `SHA`s in one fixup commit
- Before commit, verify staged files belong to a single target group: `git diff --cached --name-only`

Wrong: `git commit --fixup <fixup_sha>`
Right: `git commit --fixup <original_sha>`

To fix a fixup: find original, fixup that directly, or `git rebase -i` to squash.

```bash
# Original.
abc123 feat: Add feature X
# Fixup (correct).
def456 fixup! feat: Add feature X
# Another fix -> fixup ORIGINAL, NOT def456.
git commit --fixup abc123
```

## Save-Point Pattern

Commit locally each tested increment per the increment cycle in rules.md. Commits are save points, if the next change breaks something, revert to the last known-good state.

## Commit Size

Target ~100 lines per commit. Split commits over ~300 lines.

## Change Summaries

After any modification, provide a structured summary:

``` text
CHANGES MADE:
- src/path/to/file: What was changed and why

THINGS I DIDN'T TOUCH (intentionally):
- src/other/file: Has a similar issue but out of scope

POTENTIAL CONCERNS:
- Any risks, trade-offs, or open questions
```

## Worktrees

For parallel agent work on multiple features:

```bash
git worktree add ../project-feature-a feature/task-creation
git worktree add ../project-feature-b feature/user-settings

# When done, merge and clean up.
git worktree remove ../project-feature-a
```

Each worktree is a separate directory with its own branch. Agents work in parallel without interfering.

## Branch

`feature/<name>` / `fix/<name>` / `refactor/<name>`
