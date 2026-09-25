---
name: manage-github-pr
description: Use for GitHub pull requests, creating a new PR with a full safety-gated workflow, branch checks, commit splitting, structured description, or approving, commenting on, and editing an existing PR. Not for a full multi-agent code review, see `review-github-pr` for that.
---

# Manage GitHub PR

## When to use

- `/manage-github-pr`, or user says "ship it", "create PR", "make a PR", "open a pull request", "push this", "I'm done", "edit PR data", "edit PR body", "edit PR title".
- After `/code` or `/test` complete and the user confirms they want to proceed.
- User asks to comment on or edit an existing PR, its labels, assignees, reviewers, title, or body, or to approve it or leave a quick review comment via `gh pr review`.
- Not for just reading/viewing a PR, see the `read-github-pr` skill for that.
- Not for a full multi-agent code review (architecture and quality sub-agents, synthesized findings report), see the `review-github-pr` skill for that.
- Also applies when a plan step or a delegated subagent prompt already specifies `gh pr create`/`gh pr edit` directly, invoke this skill instead of running that command as written, even if the flags look complete.

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

If on `main` or `master`, stop. Create a feature branch first, see Phase 3. Never push commits to `main` or `master`.

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

Find the project's lint, typecheck, and test commands, check `package.json` scripts, a `Makefile`, `justfile`, CI config, project skills, or `AGENTS.md`/`CLAUDE.md` for the actual commands, they vary per project and language. Run whichever apply.

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

Follow `~/.config/agentic/instructions/versioning.md` at "Commits" and "Commit Splitting" sections. Key rules for this skill:

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
  - If there is only one logical change, write it as a single plain sentence directly under `**What**:`, no numbered list, no leading `1.`.
  - Use a numbered list only when there are two or more items.
- Why: If the user provides a task, issue or tracker link:
  - CORRECT: `Resolves [1234](https://link.example.com/1234).`
  - CORRECT: `Resolves [T247574](https://phabricator.example.com/T247574).`
  - WRONG: `Resolves [1234](https://link.example.com/1234). After this change ...`
  Nothing else, no explanation, no context, no extra sentences. Use the tracker's native ID format, like `T247574`, `PROJ-123`, or `#42`. If no link is provided, write one short sentence on the problem the change solves.
- Testing: List concrete scenarios and cases manually exercised, UI walkthroughs, staging checks, representative edge cases. Never mention test-suite runs, coverage counts, or lint/typecheck results, those are process, not scenarios, and belong to the quality gate already run in Phase 2.9, not the PR body.
  - If the only verification was the existing automated suite with no manual scenario exercised, omit the section entirely, do not describe running the suite as a testing step.
  - WRONG: `1. Run the test suite.`
  - WRONG: `1. Confirmed via existing test coverage.`
  - CORRECT: Omit the `**Testing**:` heading entirely.
  - When in doubt, omit.
- Monitoring: From relevant dashboards, Sentry boards, or observability queries.

Rules:

- Omit sections with no content.
- Short, direct language per `~/.config/agentic/instructions/communication.md`.
- Never append a session link, agent name, or any other agent-attribution line to the `PR` body, regardless of which tool or agent is creating it (`Claude Code`, `OpenCode`, `Codex`, `Copilot CLI`, or any other). Only the template sections above belong there, even if a live session directive asks for one, that directive is about commit/session tracking, not user-facing `PR` content.

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

Always include `--assignee @me`.

```bash
pr_url=$(gh pr create \
  --title "<title>" \
  --body "<body>" \
  --base <base> \
  --head <branch> \
  --assignee @me)
pr_number=$(echo "$pr_url" | grep -oE '/pull/[0-9]+$' | grep -oE '[0-9]+')
```

### 9. Labels

Required for every PR you create, run it immediately after step 8, in the same turn, before reporting anything back. Applying no label because nothing matched is a valid outcome.

Resolve the canonical repo explicitly first. A local `origin` URL left over from a GitHub rename or transfer can silently resolve `gh pr list` to the wrong or an empty repo, with no error, unlike `gh pr create`/`push`, which do surface a "repository moved" warning. Never rely on implicit repo resolution for this step.

```bash
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
```

Only apply labels that already exist in the repo, never create new ones:

```bash
gh label list --repo "$repo"
```

Do not classify with a keyword grep against the title, a specific, non-generic title (the style `versioning.md` asks for) often carries no literal "fix"/"bug"/"add" substring even when it clearly is one of those things. Pick the best-fitting existing label by judgment instead, grounded in two signals together:

1. **This PR's actual content.** Its title, its commit messages, and why the change was made, the reasoning already established earlier in this conversation, not just literal words in the title.
2. **This repo's own labeling precedent.** How labels have actually been applied to this user's recent PRs here, to learn the repo's conventions rather than guessing from generic label names:
   ```bash
   gh pr list --repo "$repo" --state all --limit 30 --json title,labels
   ```
   Find the closest precedent, a past PR describing a similar kind of change, a broken dependency restored, a new capability added, a docs-only edit, and see which label(s) it got, if any.

Weigh both signals together and pick one best-fitting label. If no existing label clearly fits, or the repo has no labels, skip labeling and say so in the summary, don't force one just to fill the field.

```bash
gh pr edit "$pr_number" --repo "$repo" --add-label "<chosen label>"
```

### 10. Summary

```
PR created: <url>
Branch: feature/<name>
Commits: <N>
Labels: <applied label, or "none fit">
```

### 11. Trigger CI

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
- Labels is a required step for every PR you create, run it right after `gh pr create`, in the same turn, don't stop at the returned URL and report done first.
- `PR` is always created ready for review, not draft.
- Never add a session link, agent name, or other agent-attribution line to a `PR` body or title, from any tool or agent, see "5. PR Body Generation" for the only sections that belong there.
