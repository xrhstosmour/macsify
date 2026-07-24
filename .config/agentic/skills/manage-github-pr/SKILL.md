---
name: manage-github-pr
description: Use for GitHub pull requests, creating a new PR with a full safety-gated workflow, branch checks, commit splitting, structured description, or reviewing, commenting on, and editing an existing PR.
---

# Manage GitHub PR

## When to use

- `/manage-github-pr`, or user says "ship it", "create PR", "make a PR", "open a pull request", "push this", "I'm done", "edit PR data", "edit PR body", "edit PR title".
- After `/code` or `/test` complete and the user confirms they want to proceed.
- User asks to review, comment on, or edit an existing PR, its labels, assignees, reviewers, title, or body.
- Not for just reading/viewing a PR, see the `read-github-pr` skill for that.

## Reviewing, commenting, or editing an existing PR

```bash
gh pr review <number> --approve --body "<review>"
gh pr comment <number> --body "<comment>"

# Edit an existing PR, flags differ from create, note --add-assignee NOT --assignee.
gh pr edit <number> --title "<title>" --body "<body>"
gh pr edit <number> --add-assignee <login>
gh pr edit <number> --remove-assignee <login>
gh pr edit <number> --add-label <name> --remove-label <name>
gh pr edit <number> --add-reviewer <login>
gh pr edit <number> --base <branch>
```

## Creating a new PR

### 1. Validate Intent

Confirm with the user they want to create a PR. Ask for the change scope if the changes are unclear.

### 2. Safety Guardrails

Run all checks. Stop and ask on any failure.

#### 2.1 Branch check

```bash
git branch --show-current
```

If on `main` or `master`, do NOT proceed. Create a feature branch first, see Phase 3. Never push commits to `main` or `master`.

#### 2.2 Empty PR guard

```bash
git log --oneline <base>..HEAD 2>/dev/null | wc -l
git diff <base>..HEAD --stat
```

If no commits or no file changes, abort. Nothing to PR.

#### 2.3 Uncommitted changes

```bash
git status --short
```

Warn if there are unstaged or untracked files. Ask the user what to do, stage, stash, or ignore.

#### 2.4 Base drift

```bash
git fetch origin <base>
git rev-list --count <base>..origin/<base>
```

If base branch has advanced, warn the user and suggest rebasing first.

#### 2.5 Remote branch conflict

```bash
git ls-remote --heads origin <branch>
```

If the branch already exists on remote, warn the user. Only force-push with explicit approval.

#### 2.6 Branch naming

Enforce pattern from `~/.config/agentic/instructions/versioning.md` at "Branch" section. Lowercase, kebab-case. Abort if name doesn't match.

#### 2.7 Commit audit

```bash
git log --format="%H %an %s" <base>..HEAD
```

Reject or warn on:
- Agent co-authors, marked `Co-authored-by:`, reject
- WIP markers, `WIP`, `wip`, `TODO`, warn
- Placeholder messages, `fix`, `update`, `.`, warn

#### 2.8 Secrets scan

```bash
git diff <base>..HEAD | grep -iE 'api.?key|secret|token|password|credential|\.env' | grep -v 'grep\|example\|sample\|test\|mock\|fake'
```

If matches found, stop immediately. Warn the user that secrets may be staged.

#### 2.9 Quality gate

Find and run lint, typecheck, and test commands:

```bash
# Lint, try common runners.
npm run lint 2>/dev/null || npx eslint . 2>/dev/null || true
# Typecheck.
npm run typecheck 2>/dev/null || npx tsc --noEmit 2>/dev/null || true
# Tests.
npm test 2>/dev/null || npx vitest run 2>/dev/null || go test ./... 2>/dev/null || cargo test 2>/dev/null || true
```

If any fail, stop and present the failure. Do not proceed without the user's approval.

#### 2.10 Merge conflict preview

```bash
# Get the merge base and preview conflicts.
git merge-tree $(git merge-base HEAD origin/<base>) origin/<base> HEAD 2>/dev/null | grep -A5 'changed in both' || echo "No conflicts detected"
```

Warn about potential conflicts, but this is informational, not a blocker.

### 3. Branch Management

If on `main` or `master`:

```bash
git checkout -b feature/<short-description> <base>
```

Derive `<short-description>` from the changed paths or ask the user. Example: a change to `src/api/auth.ts` could become `feature/auth-refactor`.

If a branch name already exists locally or remotely, suffix with a number, `-2`, `-3`.

### 4. Commit Splitting

Follow `~/.config/agentic/instructions/versioning.md` at "Commit Size" and "Commits" sections. Key rules for this skill:

- No type prefixes like `feat:` or `perf:`. Natural language only.
- One topic per commit, never mix contexts.
- Use `git add -p` to split hunks across commits.

```bash
git add -p <file>
git commit -m "<message>"
```

Show the commit plan to the user before committing:

```bash
git log --oneline <base>..HEAD
```

Get user approval.

### 5. PR Body Generation

Use this template. Omit sections with no content.

```markdown
**What**:

1. **<item>**: <Description>
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

Follow style in `~/.config/agentic/instructions/communication.md` for tone and formatting.

Derive each section:
- What: From commit messages and diffs. Each logical change gets one plain-sentence item starting with the action verb, no `**Topic**:` label prefix. Fold migrations into the feature item they support, never list separately.
- Why: If the user provides a task, issue or tracker link:
  - CORRECT: `Resolves [1234](https://link.example.com/1234).`
  - WRONG: `Resolves [1234](https://link.example.com/1234). After this change ...`
  Nothing else, no explanation, no context, no extra sentences. Use the tracker's native ID format, like `T247574`, `PROJ-123`, or `#42`. If no link is provided, write one short sentence on the problem the change solves.
- Testing: Only include for manual verification flows on production or staging: UI walkthrough, SQL query, dashboard check, etc. Test commands, migration runs, and downstream synchronize steps do not belong here. When in doubt, omit.
- Monitoring: From relevant dashboards, Sentry boards, or observability queries.

Rules:

- Omit sections with no content.
- Short, direct language per `~/.config/agentic/instructions/communication.md`.

### PR title

- Short, descriptive, natural language.
- No type prefixes, `perf:`, `feat:`, `fix:`.
- No semicolons.
- Keep under 60 characters. And follow the style in `~/.config/agentic/instructions/communication.md`.
- Derive from the first commit message or branch name.
- Example: `Replace single-column indexes with compound indexes` not `perf: Replace...; add outbox...`

### 6. Preview + Approval

Show the user:

```
Branch: feature/<name>
Base: <base>

Commits:
<N> <message>

Title: <title>

Body:
**What**:
1. ...

**Why**:
...
```

Get explicit approval before proceeding. If the user wants changes, iterate on Phase 4.

### 7. Push

```bash
# First push.
git push origin <branch>

# If remote branch exists and user approved force-push.
git push origin <branch> --force-with-lease
```

Verify:

```bash
git fetch origin <branch>
git rev-parse HEAD
git rev-parse origin/<branch>
```

### 8. PR Creation

Always include `--assignee @me`. Never omit it.

```bash
pr_url=$(gh pr create \
  --title "<title>" \
  --body "<body>" \
  --base <base> \
  --head <branch> \
  --assignee @me)
pr_number=$(echo "$pr_url" | grep -oE '/pull/[0-9]+$' | grep -oE '[0-9]+')
```

#### Labels

Fetch labels from the last 10 PRs created by the current user and apply any that appear in at least 2 of them. Never create new labels.

```bash
# Find common labels across the last 10 PRs.
gh pr list --author @me --state all --limit 10 --json labels \
  --jq '.[].labels[].name' | sort | uniq -c | sort -rn | awk '$1 >= 2 {print $2}' | \
  while read label; do
    gh pr edit "$pr_number" --add-label "$label"
  done
```

If no labels appear in ≥ 2 recent PRs, skip labels entirely.

### 9. Summary

```
PR created: <url>
Branch: feature/<name>
Commits: <N>
```

### 10. Trigger CI

After creating the PR, check if the project has CI/CD workflows that do not start automatically on PR creation. Look for:

- `.github/workflows/` files with `on: push: branches: ["tests/**"]` or `workflow_dispatch` triggers.
- Project docs, README, `copilot/dev-tools.md`, or equivalent, that mention manual CI trigger steps.

If manual triggers exist, show the user the exact command and let them decide whether to run it. Do not trigger CI automatically. Example for projects using a `tests/` branch convention:

```bash
git push origin HEAD:tests/<branch-name>
```

## Rules

- Never push to `main` or `master`. Always create a feature branch.
- No remote actions without user approval.
- Show commit plan and `PR` body before pushing or creating the `PR`.
- On command failure: show the error, stop, and ask the user.
- Only apply labels that already exist in the repo. Never create new labels.
- `PR` is always created ready for review, not draft.
