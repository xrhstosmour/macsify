---
name: review-pr
description: >
  Multi-agent PR code review orchestrator. Fetches a PR by URL or branch name,
  spawns specialist sub-agents for architecture and quality review, then
  synthesizes findings into a structured report. Activate with: "review my PR",
  "review this PR", "/review-pr `<url_or_branch>`".
---

# PR Review Orchestrator

## Purpose

Run a structured, multi-agent code review on a pull request by delegating
architecture and quality concerns to specialist sub-agents and synthesizing
their findings into a single actionable report.

## When to use

Activate when the user says any of:

- "review my PR" / "review this PR" / "review the PR"
- "review PR `<url>`" / "/review-pr `<url>`"
- "code review `<branch>`" / "review branch `<branch>`"

## Fetch the PR

If the user provides a GitHub PR URL, extract `owner`, `repo`, and `pr_number`:

```
# From URL: https://github.com/<owner>/<repo>/pull/<number>
```

If the user provides a branch name, fetch it:

```bash
gh pr view <branch> --json number,title,body,headRepository,url
```

If no URL or branch given, check if the current branch is a PR branch (not master/main):

```bash
git branch --show-current
```

If on master or main, abort and ask the user for a PR URL or branch name.
Otherwise, use the current branch:

```bash
gh pr view --json number,title,body,headRepository,url
```

Store the PR title, description, and `owner/repo/number`.

## Fetch changed files and diff

```bash
gh pr diff <pr_number> --repo <owner>/<repo>
gh pr view <pr_number> --repo <owner>/<repo> --json files --jq '.files[].path'
```

Store the full diff and file list to pass to each sub-agent.

## Classify the change

Scan the changed file paths for signals:

| Signal                                            | Implication                          |
| ------------------------------------------------- | ------------------------------------ |
| New database migrations, schema changes           | Architecture review is high priority |
| Auth, session, token, API key files               | Security review is high priority     |
| Hot-path code (controllers, handlers, middleware) | Performance review is high priority  |
| Config, routes, infrastructure                    | Architecture review is high priority |
| Tests only                                        | Light review, focus on test quality  |
| Docs only                                         | Light review, focus on clarity       |

If the PR is large (>50 files), warn the user and ask if they want a
focused review on specific files.

## Spawn sub-agents in parallel

Invoke two sub-agents via the Task tool, running them concurrently:

### Architect agent

Prompt the `architect` agent with:

```
Review the architecture of this PR. Focus on:
- Domain boundaries and separation of concerns
- Correct placement of business logic
- Coupling and dependency direction
- New patterns introduced vs existing conventions
- Background vs foreground work (heavy ops in request cycle?)

## PR Under Review
Title: {pr_title}
Description: {pr_description}

## Changed Files
{file_list}

## Full Diff
{diff_content}

## Classification Notes
{classification_signals}

## Output Format
Return findings as:
## Architecture Review
### Findings
For each issue: [SEVERITY] file:line — problem description. Fix suggestion.
Severity: CRITICAL | HIGH | MEDIUM | LOW | NIT
### Summary
One paragraph. If no issues, say so explicitly.
```

### Reviewer agent

Prompt the `reviewer` agent with:

```
Review this PR for quality, security, and performance. Follow your
built-in review framework (execution multiplier, N+1, injection, secrets).

## PR Under Review
Title: {pr_title}
Description: {pr_description}

## Changed Files
{file_list}

## Full Diff
{diff_content}

## Classification Notes
{classification_signals}
```

Both agents run in parallel. Wait for both to complete before proceeding.

## Synthesize findings

Produce a unified review. Write like a teammate giving feedback in a chat thread, direct, no fluff, no emojis, no decorative formatting:

```
## PR Review: {pr_title}

### Summary
One paragraph describing what the PR does and overall quality signal.

### CRITICAL
Findings rated CRITICAL or HIGH. Include sub-agent source, file path, and a concrete fix suggestion.

### MEDIUM
Findings rated MEDIUM. Same format.

### LOW
Findings rated LOW or NIT. Brief, not exhaustive.

### Coverage
- Architecture: found N issues
- Quality/Security/Performance: found N issues
```

## Prompt to post

After presenting the review, ask the user:

> Post review with inline comments to the PR?

If yes, write each finding as a natural comment like a teammate reviewing code. Do not use emojis or markdown flourishes. Do not open with preambles. Just state the issue and suggestion directly. Then post as a review with inline comments:

```bash
HEAD_SHA=$(gh pr view <pr_number> --repo <owner>/<repo> --json commits --jq '.commits[-1].oid')

gh api repos/<owner>/<repo>/pulls/<pr_number>/reviews \
  -f commit_id="$HEAD_SHA" \
  -f event="COMMENT" \
  -f body="<summary_paragraph>" \
  -f comments='[
    {"path":"<file>","line":<line>,"body":"<human-like comment with fix suggestion>"},
    {"path":"<file>","line":<line>,"body":"<human-like comment with fix suggestion>"}
  ]'
```

Use `event: "REQUEST_CHANGES"` if blockers exist, `"COMMENT"` otherwise.
Each comment references one finding, written conversationally in English.

## Guardrails

- Keep findings tied to specific files and line references.
- Do not suggest architectural rewrites unless the PR introduces a clear regression.
- For large PRs, ask the user if they want focused review on specific areas.
- No emojis, no markdown dividers, no decorative formatting anywhere in the review or inline comments.
- Write like a human teammate in a code review thread. Skip preambles and get to the point.
