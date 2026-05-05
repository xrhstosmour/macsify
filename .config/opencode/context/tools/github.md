# GitHub

When reading content from any GitHub URL, use `gh` CLI instead of `WebFetch`. Fallback to `WebFetch` only if `gh` is unavailable.

## Common commands

```bash
# Issues
gh issue create --title "<title>" --body "<body>" --label <label>
gh issue view <number>
gh issue comment <number> --body "<comment>"

# `PRs`.
gh pr create --title "<title>" --body "<body>" --base <branch> --head <branch>
gh pr view <number>
gh pr diff <number>
gh pr review <number> --approve --body "<review>"
gh pr comment <number> --body "<comment>"

# Commits.
gh api repos/<owner>/<repo>/commits/<sha>

# Releases.
gh release create <tag> --title "<title>" --notes "<notes>"
gh release view <tag>
gh release download <tag>

# Raw content (files, directories).
gh api repos/<owner>/<repo>/contents/<path> --raw
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
