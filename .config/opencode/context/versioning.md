# Versioning

## Commits

Conventional commits, without agent co-authors.
Wrap in backticks:

- technical identifiers
- code elements
- file names and paths

while leaving unformatted:

- natural language words
- headings
- `YAML` frontmatter fields

```text
feat: Add `Sentry` integration
fix: Fix `APIEndpoint` timeout
refactor: Rename `utils` file to `utilities.py`
test: Add tests for `User` model
docs: Update `README.md` with setup instructions
```

- fixup: for review comment fixes, typos, small oversights
- amend: for single commit changes
- Split by context. Include tests in same commit as code.

```bash
git add <file> && git commit --fixup <SHA>
git rebase -i --autosquash master
git commit --amend --no-edit
```

### Git safety

- Never force-push to `main` or `master`
- Never commit `.env`, secrets, credentials. Warn immediately if staged.

### Fixups

Target only original commits. NEVER fixup a fixup.

Rules:

- Target must be in `<base>..HEAD`
- One target per fixup. Never mix hunks from different `SHA`s
- Use `git add -p` to split hunks
- Uncertain mapping: stop and clarify
- New work (no valid target): use regular commit
- Push with `--force-with-lease`

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

## Branch

`feature/<name>` / `fix/<name>` / `refactor/<name>`
