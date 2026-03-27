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

## GitHub

Always use `gh` `CLI` for `GitHub` operations. Never use `WebFetch` for `GitHub` `URLs`.

```bash
gh api repos/<owner>/<repo>/contents/<path> --raw
gh pr create --title "..." --body-file <file>
gh issue create --title "..." --body "<body>"
gh pr review <pr> --approve
gh release create <tag> --title "<title>" --notes "<notes>"
gh search repos <query> --limit 10
gh search issues <query> --limit 10
```

## PR

```markdown
## What

One-line change summary.

## Why

Problem being solved.

## Link

Resolves [issue_id](link/to/issue)

## Testing

1. Open <page>
2. Perform <action>
3. Confirm <result>

or

1. Run `<command>`
2. Verify <output>
```

No placeholders in final PR bodies.
