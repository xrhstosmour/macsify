# GitHub

Never use `WebFetch` for `GitHub` URLs. The `HTML` pages are too large and get truncated, losing content. Always use `gh` CLI or `gh api` instead.

## Reading issues and PRs

```bash
# Read an issue (body + comments).
gh issue view <number> --repo <owner>/<repo> --comments

# Read a PR (description + diff + files).
gh pr view <number> --repo <owner>/<repo> --json title,body,files
gh pr diff <number> --repo <owner>/<repo>

# Raw API access for anything else.
gh api repos/<owner>/<repo>/issues/<number> --jq .body
gh api repos/<owner>/<repo>/pulls/<number> --jq .title
```

## Common commands

```bash
# Issues
gh issue create --title "<title>" --body "<body>" --label <label>
gh issue view <number>
gh issue comment <number> --body "<comment>"

# PRs.
gh pr create --title "<title>" --body "<body>" --base <branch> --head <branch> --assignee @me
gh pr view <number>
gh pr diff <number>
gh pr review <number> --approve --body "<review>"
gh pr comment <number> --body "<comment>"

# Edit an existing PR (flags differ from create — note --add-assignee NOT --assignee).
gh pr edit <number> --title "<title>" --body "<body>"
gh pr edit <number> --add-assignee <login>
gh pr edit <number> --remove-assignee <login>
gh pr edit <number> --add-label <name> --remove-label <name>
gh pr edit <number> --add-reviewer <login>
gh pr edit <number> --base <branch>

# Commits.
gh api repos/<owner>/<repo>/commits/<sha>

# Releases.
gh release create <tag> --title "<title>" --notes "<notes>"
gh release view <tag>
gh release download <tag>

# Raw content (files, directories).
gh api repos/<owner>/<repo>/contents/<path> --raw
```

## PR title

- Short, descriptive, natural language.
- No type prefixes (`perf:`, `feat:`, `fix:`).
- No semicolons.
- Derive from the first commit message or branch name.
- Example: `Replace single-column indexes with compound indexes` not `perf: Replace...; add outbox...`

## PR body format

```markdown
**What**:

1. **<item>**: <Description with capital letter, no dashes>
2. **<item>**: <Description>

**Why**:

Resolves [<issue_or_task_id>](<url>). The link can point to a Sentry, Phabricator, Jira, or other task manager, ticketing system or monitoring tool.

**Testing**:

1. <step>
2. <step>

**Monitoring**:

Visit the following boards:

1. <board>
2. <board>

Or use the above queries:

<query block>
```

Rules:

- Omit sections with no content.
- Short, direct language per `~/.config/agentic/instructions/communication.md`.
