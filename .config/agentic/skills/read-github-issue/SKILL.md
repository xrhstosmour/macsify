---
name: read-github-issue
description: Use when reading or viewing a GitHub issue, its body or comments. Not for creating or commenting, see the `manage-github-issue` skill for that.
---

# Read GitHub Issue

## When to use

- User shares a GitHub issue URL, or asks to check/view/read an issue.
- About to `WebFetch` a `github.com` issue URL, use `gh`/`gh api` instead.
- Not for creating an issue or commenting on one, see the `manage-github-issue` skill for that.

Never use `WebFetch` for `GitHub` URLs. The `HTML` pages are too large and get truncated, losing content. Always use `gh` CLI or `gh api` instead.

```bash
gh issue view <number> --repo <owner>/<repo> --comments
gh api repos/<owner>/<repo>/issues/<number> --jq .body
```
