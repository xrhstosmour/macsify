# GitHub

Always use `gh` `CLI` for `GitHub` operations. Fallback to `WebFetch` only if `gh` is not available or cannot perform the required action.

## Common commands

```bash
gh api repos/<owner>/<repo>/contents/<path> --raw
gh pr create --title "..." --body-file <file>
gh issue create --title "..." --body "<body>"
gh pr review <pr> --approve
gh release create <tag> --title "<title>" --notes "<notes>"
gh search repos <query> --limit 10
gh search issues <query> --limit 10
```

## PR body

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

## Review replies and resolution

When updating `PR` review comments:

- Always reply to the specific review comment, not as a new top-level `PR` comment.
- For fixes, reply with commit link(s) only.
- If multiple commit links are needed, join with ` & `.
- Resolve the review thread only after posting the reply.

Examples:

```bash
gh api "repos/<owner>/<repo>/pulls/<pr_number>/comments/<comment_id>/replies" -X POST -F body="https://github.com/<owner>/<repo>/commit/<sha>"
gh api "repos/<owner>/<repo>/pulls/<pr_number>/comments/<comment_id>/replies" -X POST -F body="https://github.com/<owner>/<repo>/commit/<sha_1> & https://github.com/<owner>/<repo>/commit/<sha_2>"
```
