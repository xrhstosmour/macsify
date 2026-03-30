# GitHub

Always use `gh` CLI for GitHub operations. Fallback to `WebFetch` only if `gh` unavailable.

## Common commands

```bash
gh api repos/<owner>/<repo>/contents/<path> --raw
gh pr create --title "..." --body-file <file>
gh issue create --title "..." --body "<body>"
gh release create <tag> --title "<title>" --notes "<notes>"
```

## PR body format

```markdown
## What

One-line change summary.

## Why

Problem being solved.

## Link

Resolves [issue_id](link/to/issue)

## Testing

Steps to verify (commands, UI flows, expected outcomes).
```

No placeholders in final PR bodies.
