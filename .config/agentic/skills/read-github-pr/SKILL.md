---
name: read-github-pr
description: Use when reading or viewing a GitHub pull request, its description, diff, or files. Not for creating or editing, see the `manage-github-pr` skill for that.
---

# Read GitHub PR

## When to use

- User shares a GitHub PR URL, or asks to check/view/read a pull request's description, diff, or files.
- About to `WebFetch` a `github.com` PR URL, use `gh`/`gh api` instead.
- Not for creating, reviewing, commenting, or editing a PR, see the `manage-github-pr` skill for that.

Never use `WebFetch` for `GitHub` URLs. The `HTML` pages are too large and get truncated, losing content. Always use `gh` CLI or `gh api` instead.

```bash
gh pr view <number> --repo <owner>/<repo> --json title,body,files
gh pr diff <number> --repo <owner>/<repo>
gh api repos/<owner>/<repo>/pulls/<number> --jq .title
```
