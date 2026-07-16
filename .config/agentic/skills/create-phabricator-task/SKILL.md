---
name: create-phabricator-task
description: >
  Create and edit Phabricator tasks via Curl Conduit API. Triggered only when
  the user explicitly mentions Phabricator or "phab": "create phab task/ticket/issue",
  "create Phabricator task/ticket/issue", or "/create-phabricator-task".
---

# Create Phabricator Task

## When to use

Use when the user asks to create, file, open, or submit a Phabricator task or ticket.

Do NOT use for reading existing tasks. Use `~/.config/agentic/tools/phabricator.md` for that.

## Prerequisites

Authenticate using the token discovery flow from `~/.config/agentic/tools/phabricator.md`. Store as `$PHAB` and `$TOKEN`. Verify with `user.whoami` before proceeding.

Derive `$PHAB` in order:
1. `$PHAB_URI` env var.
2. `~/.arcrc` host key — strip the `/api/` suffix: `jq -r '.hosts | to_entries[] | select(.key | test("phabricator")) | .key' ~/.arcrc | sed 's|/api/||'`
3. Ask the user.

## Task creation workflow

### 1. Gather required fields

- Tag (required): Phabricator project. Ask: "Which tag?"
- Title (required): Short imperative phrase, max ~60 characters. No priority prefix (priority is a separate field). Example: `Add dark mode toggle`.

### 2. Gather optional fields

Ask all at once in a single message:

> Description (auto-generate from git? y/n), Priority (P0–P4), Assignee (default: self-assign), Subscribers, Status (default: open), Parent task (TID), Reference links.

Resolve the current user's PHID for self-assignment:

```bash
curl -s -X POST "$PHAB/api/user.whoami" -d api.token="$TOKEN" | jq -r '.result.phid'
```

Use this PHID as the default assignee unless the user specifies someone else.

### 3. Description generation

If generating, gather git context:

```bash
BRANCH=$(git branch --show-current)
BASE_BRANCH="master"
git fetch origin "$BASE_BRANCH" 2>/dev/null || true
COMMITS=$(git log --oneline "${BASE_BRANCH}"..HEAD 2>/dev/null || git log --oneline HEAD~5..HEAD 2>/dev/null || echo "")
FILES=$(git diff --stat "${BASE_BRANCH}"..HEAD 2>/dev/null || git diff --stat HEAD~5 2>/dev/null || echo "")
CHANGES=$(git diff "${BASE_BRANCH}"..HEAD -- '*.swift' '*.md' 2>/dev/null | head -200 || echo "")
PR_JSON=$(gh pr view --json number,url 2>/dev/null || echo "")
PR_NUMBER=$(echo "$PR_JSON" | jq -r '.number // empty')
PR_URL=$(echo "$PR_JSON" | jq -r '.url // empty')
```

Tone rules:
- Conversational, direct. Rewrite if it sounds stiff when read aloud.
- No jargon or acronyms. Explain technical terms in one sentence if unavoidable.
- Short sentences. One idea each.
- Describe user-facing problem and impact, not code changes.

Remarkup formatting rule (Phabricator's markup dialect, not GitHub-flavored Markdown): always leave a
blank line after a `##` header before its content, and a blank line after any line ending in `:` before
a following list. Remarkup does not reliably render headers or lists without that spacing, headers can
merge into the paragraph below them, and lists can render as plain text. Apply this to every description
you generate, not just the examples below.

Feature example:
```
## Why

Users could not find the settings they needed because options were scattered across multiple screens.

## What

Settings now live on a single page accessible from the sidebar with a search bar.

## References

- [[https://github.com/org/repo/pull/123 | PR #123]]
```

Bug example:
```
## How to reproduce

1. Open the app and go to the dashboard.
2. Click Export. Nothing happens.

## What we found

The export endpoint failed when the server session expired. Refreshing the session before export fixed it.

## References

- [[https://github.com/org/repo/pull/456 | PR #456]]
```

If no code context exists, ask: "What should the description say? I can help draft it."

Always end with a `## References` section, followed by a blank line and then the list. Format every URL
as a Remarkup hyperlink: `[[https://example.com | Label]]`. Never use bare URLs. Include:

- If a PR exists: `[[<pr_url> | PR #<number>]]` — omit the branch (the PR implies it)
- If no PR exists: Branch `` `<branch-name>` ``
- Any extra links the user provided

Show the generated description and ask for approval before proceeding.

### 4. Resolve PHIDs

Run all resolutions in parallel (`&` + `wait`) when multiple are needed.

```bash
# Project.
curl -s -X POST "$PHAB/api/project.search" -d api.token="$TOKEN" \
  -d "constraints[query]=<name>" -d limit=5 \
  | jq -r '.result.data[] | "\(.phid)  \(.fields.name)"'

# User: endpoint user.search, constraint constraints[usernames][0]=<username>, limit=1.
# Task (parent): endpoint maniphest.search, constraint constraints[ids][0]=<id>, limit=1.
# All return .phid or .result.data[0].phid. Show candidates on no exact match.
```

### 5. Preview and confirm

```
Tag:         <project-name>
Title:       <title>
Priority:    <priority>
Assignee:    <username> (default: self)
Subscribers: <usernames>
Status:      <status>
Parent:      T<id>

<description>
```

Ask: "Ready to create?" Do NOT execute without explicit confirmation.

### 6. Execute creation

```bash
RESULT=$(curl -s -X POST "$PHAB/api/maniphest.edit" \
  -d api.token="$TOKEN" \
  -d output=json \
  --data-urlencode "transactions[0][type]=title" \
  --data-urlencode "transactions[0][value]=<title>" \
  -d "transactions[1][type]=projects.set" \
  -d "transactions[1][value][0]=<project-phid>" \
  --data-urlencode "transactions[2][type]=description" \
  --data-urlencode "transactions[2][value]=<description>")

ERROR=$(echo "$RESULT" | jq -r '.error_code // empty')
if [ -n "$ERROR" ]; then
  echo "Error: $(echo "$RESULT" | jq -r '.error_info // ""')"
  exit 1
fi
TASK_ID=$(echo "$RESULT" | jq -r '.result.object.id')
echo "Task created: $PHAB/T$TASK_ID"
```

Add optional transactions by appending `--data-urlencode "transactions[N][type]=<type>"` etc., incrementing `N`:

| Field | type | value |
|-------|------|-------|
| Priority | `priority` | keyword (see table below) |
| Assignee | `owner` | `<assignee-phid>` |
| Subscribers | `subscribers.add` | `value[0]=<phid>`, `value[1]=<phid>`, ... |
| Status | `status` | `open`, `inprogress`, `resolved` |
| Parent task | `parents.add` | `value[0]=<parent-phid>` |

### 7. Error handling

| Code | Cause | Fix |
|------|-------|-----|
| `ERR-CONDUIT-CORE` | Invalid PHID | Re-resolve the PHID |
| `ERR-CONDUIT-ACCESS` | Token lacks permissions | Ask user for a different token |
| `ERR-CONDUIT-UNABLE-TO-SERIALIZE` | Malformed payload | Check quotes and encoding |
| Other | Unknown | Show full output, ask user how to proceed |

## Update existing task

```bash
curl -s -X POST "$PHAB/api/maniphest.edit" \
  -d api.token="$TOKEN" \
  -d "objectIdentifier=<task-id-or-phid>" \
  --data-urlencode "transactions[0][type]=<type>" \
  --data-urlencode "transactions[0][value]=<value>"
```

Common types: `status`, `title`, `description`, `owner`, `subscribers.add`, `subscribers.remove`.

## Priority keyword mapping

| Code | Name | Keyword |
|------|------|---------|
| P0 | Unbreak Now! | `unbreak` |
| P1 | High | `high` |
| P2 | Normal | `normal` |
| P3 | Low | `low` |
| P4 | Wishlist | `wish` |
