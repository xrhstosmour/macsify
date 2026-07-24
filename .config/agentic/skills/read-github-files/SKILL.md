---
name: read-github-files
description: Use when reading GitHub commits, releases, or raw repo file/directory content via the API. Also covers creating a release, since releases have no dedicated manage skill of their own.
---

# Read GitHub Files

## When to use

- User asks to view a commit, a release, or raw file/directory content from a GitHub repo.
- User asks to create a release.
- About to `WebFetch` a `github.com` URL for a commit, release, or file, use `gh api` instead.

```bash
# Commits.
gh api repos/<owner>/<repo>/commits/<sha>

# Releases.
gh release create <tag> --title "<title>" --notes "<notes>"
gh release view <tag>
gh release download <tag>

# Raw content, files and directories.
gh api repos/<owner>/<repo>/contents/<path> --raw
```
