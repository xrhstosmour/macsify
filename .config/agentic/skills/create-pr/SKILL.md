---
name: create-pr
description: Create a GitHub pull request with structured description, split commits, feature branch, assignee, and labels. Triggered by "ship it", "create PR", "/create-pr".
---

# Create PR

## When to use

- Commands: `ship it`, `create PR`, `/create-pr`, `make a PR`, `open a pull request`

## 1. Validate Intent

Confirm with the user they want to create a PR. Ask for the change scope if the changes are unclear.

## 2. Safety Guardrails

Run all checks. Stop and ask on any failure.

### 2.1 Branch check

```bash
git branch --show-current
```

If on `main` or `master`, do NOT proceed. Create a feature branch first (see Phase 2). Never push commits to `main` or `master`.

### 2.2 Empty PR guard

```bash
git log --oneline <base>..HEAD 2>/dev/null | wc -l
git diff <base>..HEAD --stat
```

If no commits or no file changes, abort. Nothing to PR.

### 2.3 Uncommitted changes

```bash
git status --short
```

Warn if there are unstaged or untracked files. Ask the user what to do (stage, stash, ignore).

### 2.4 Base drift

```bash
git fetch origin <base>
git rev-list --count <base>..origin/<base>
```

If base branch has advanced, warn the user and suggest rebasing first.

### 2.5 Remote branch conflict

```bash
git ls-remote --heads origin <branch>
```

If the branch already exists on remote, warn the user. Only force-push with explicit approval.

### 2.6 Branch naming

Enforce pattern from `~/.config/agentic/instructions/versioning.md` at "Branch" section. Lowercase, kebab-case. Abort if name doesn't match.

### 2.7 Commit audit

```bash
git log --format="%H %an %s" <base>..HEAD
```

Reject or warn on:
- Agent co-authors (`Co-authored-by:`) — reject
- WIP markers (`WIP`, `wip`, `TODO`) — warn
- Placeholder messages (`fix`, `update`, `.`) — warn

### 2.8 Secrets scan

```bash
git diff <base>..HEAD | grep -iE 'api.?key|secret|token|password|credential|\.env' | grep -v 'grep\|example\|sample\|test\|mock\|fake'
```

If matches found, stop immediately. Warn the user that secrets may be staged.

### 2.9 Quality gate

Find and run lint, typecheck, and test commands:

```bash
# Lint (try common runners).
npm run lint 2>/dev/null || npx eslint . 2>/dev/null || true
# Typecheck.
npm run typecheck 2>/dev/null || npx tsc --noEmit 2>/dev/null || true
# Tests.
npm test 2>/dev/null || npx vitest run 2>/dev/null || go test ./... 2>/dev/null || cargo test 2>/dev/null || true
```

If any fail, stop and present the failure. Do not proceed without the user's approval.

### 2.10 Merge conflict preview

```bash
# Get the merge base and preview conflicts.
git merge-tree $(git merge-base HEAD origin/<base>) origin/<base> HEAD 2>/dev/null | grep -A5 'changed in both' || echo "No conflicts detected"
```

Warn about potential conflicts, but this is informational, not a blocker.

## 3. Branch Management

If on `main` or `master`:

```bash
git checkout -b feature/<short-description> <base>
```

Derive `<short-description>` from the changed paths or ask the user. Example: a change to `src/api/auth.ts` could become `feature/auth-refactor`.

If a branch name already exists locally or remotely, suffix with a number (`-2`, `-3`).

## 4. Commit Splitting

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

## 5. PR Body Generation

Use the template from `~/.config/agentic/tools/github.md` at "PR body format" section. Omit sections with no content.

Follow style in `~/.config/agentic/instructions/communication.md` for tone and formatting.

Derive each section:
- **What**: from commit messages and diffs. Each logical change gets one numbered item.
- **Why**: If the user provides a task or issue link, write only `Resolves [<id>](<url>).` nothing else. Use the tracker's native ID format (e.g. `T247574`, `PROJ-123`, `#42`). If no link is provided, write a short explanation of the problem the change solves.
- **Testing**: from how the user verified (commands, UI flows, expected outcomes).
- **Monitoring**: from relevant dashboards, Sentry boards, or observability queries.

For **PR title**, follow rules in `~/.config/agentic/tools/github.md` at "PR title" section.

## 6. Preview + Approval

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

## 7. Push

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

## 8. PR Creation

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

### Labels

Detect existing labels that match the change type. Never create new labels.

```bash
# Fetch existing labels.
gh label list --json name --jq '.[].name' > /tmp/labels.txt

# Apply matching labels by scanning the title and branch for keywords.
if echo "<title>" | grep -qiE 'fix|bug|hotfix'; then
  if grep -q 'bug' /tmp/labels.txt; then
    gh pr edit "$pr_number" --add-label bug
  fi
fi
if echo "<title>" | grep -qiE 'enhancement|feature|feat'; then
  if grep -q 'enhancement' /tmp/labels.txt; then
    gh pr edit "$pr_number" --add-label enhancement
  fi
fi
if echo "<title>" | grep -qiE 'refactor|cleanup|tech'; then
  if grep -q 'refactor' /tmp/labels.txt; then
    gh pr edit "$pr_number" --add-label refactor
  fi
fi

rm /tmp/labels.txt
```

Only apply labels that already exist in the repository. If no match found, skip labels.

## 9. Summary

```
PR created: <url>
Branch: feature/<name>
Commits: <N>
```

## 10. Trigger CI

After creating the PR, check if the project has CI/CD workflows that do not start automatically on PR creation. Look for:

- `.github/workflows/` files with `on: push: branches: ["tests/**"]` or `workflow_dispatch` triggers.
- Project docs (README, `copilot/dev-tools.md`, or equivalent) that mention manual CI trigger steps.

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
