---
name: manage-github-issue
description: Use when creating, commenting on, or editing a GitHub issue, its title, body, labels, or assignees. Not for reading an issue, see the `read-github-issue` skill for that.
---

# Manage GitHub Issue

## When to use

- User asks to create, file, or open a GitHub issue.
- User asks to comment on an existing GitHub issue.
- User asks to edit an existing issue, its title, body, labels, or assignees.
- Not for reading/viewing an issue, see the `read-github-issue` skill for that.

```bash
gh issue create --title "<title>" --body "<body>" --label <label>
gh issue comment <number> --body "<comment>"

# Edit an existing issue.
gh issue edit <number> --title "<title>" --body "<body>"
gh issue edit <number> --add-label <name> --remove-label <name>
gh issue edit <number> --add-assignee <login> --remove-assignee <login>
```
