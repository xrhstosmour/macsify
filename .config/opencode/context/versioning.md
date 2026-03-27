# Versioning

## Commits

Conventional commits with backtick-wrapped technical terms.
Enclose all technical identifiers, code elements, file names, and paths in backticks, while leaving natural language words unformatted.

Example:

```text
feat(scope): short description
fix(scope): fix `APIEndpoint` timeout
refactor(scope): rename `UserService` to `AccountService`
test(scope): add tests for `AuthMiddleware`
```

Use fixup for fixing review comments, correcting typos, small oversights in earlier commits.
Use amend for single commit changes.

Example:

```bash
git add <file>
git commit --fixup <SHA>
git rebase -i --autosquash master
git add <file>
git commit --amend --no-edit
```

### Git safety

- Never force-push to `main`/`master`.
- Never commit `.env`, secrets, or credential files. Warn user immediately if such files are staged.

### Review fixups

When addressing review comments:

- Create fixup commits only for changes tied to existing commits.
- Target commits must be in current feature branch range: `<base_branch>..HEAD`.
- Keep one target per fixup commit. Never mix hunks from different target `SHA`s.
- Use `git add -p` to split hunks by target `SHA`.
- If mapping is uncertain, stop and clarify before committing.
- If change is genuinely new work (no valid fixup target), use a regular conventional commit.
- Never push review-fix commits to `main`/`master`; push feature branch with `--force-with-lease`.

Example:

```bash
git log --format="%H" <base_branch>..HEAD
git add -p <file_or_files>
git commit --fixup <target_sha_a>
git add -p <file_or_files>
git commit --fixup <target_sha_b>
git push origin <current_branch> --force-with-lease
```

## Branch

Employ branch naming conventions that reflect the type of work being done, using concise prefixes and descriptive names.

Examples:

```text
feature/<name>
fix/<name>
refactor/<name>
```
