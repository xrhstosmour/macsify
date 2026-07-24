---
name: review-github-pr
description: >
  Multi-agent GitHub PR code review orchestrator. Fetches a PR by URL or branch name,
  spawns specialist sub-agents for architecture and quality review, then
  synthesizes findings into a structured report. Activate with: "review my PR",
  "review this PR", "/review-github-pr `<url_or_branch>`".
---

# GitHub PR Review Orchestrator

## Purpose

Run a structured, multi-agent code review on a GitHub pull request by delegating
architecture and quality concerns to specialist sub-agents and synthesizing
their findings into a single actionable report.

## When to use

- `/review-github-pr <url_or_branch>`
- User says "review my PR", "review this PR", "review the PR", or "code review `<branch>`".
- A PR has been created and the user wants quality feedback before merging.
- The user asks "is this ready to merge?" or "is this PR good?".
- After `/manage-github-pr` completes and the user wants a review pass.

## Fetch the PR

If the user provides a GitHub PR URL, extract `owner`, `repo`, and `pr_number`:

```
# From URL: https://github.com/<owner>/<repo>/pull/<number>
```

If the user provides a branch name, fetch it:

```bash
gh pr view <branch> --json number,title,body,headRepository,url
```

If no URL or branch given, check if the current branch is a PR branch, not master/main:

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

## Load project-specific review guidelines

Check the repo root for project-specific review rules that should override the
general rubric where more specific:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
test -f "$REPO_ROOT/REVIEW_GUIDELINES.md" && cat "$REPO_ROOT/REVIEW_GUIDELINES.md"
```

If the file exists, store its contents and append them to both sub-agent
prompts, see "Spawn sub-agents in parallel" below, labeled as project rules
that take precedence over the general rubric when they conflict. If the file
doesn't exist, skip this silently, it's optional.

## Classify the change

Scan the changed file paths and diff for signals:

| Signal                                            | Implication                          |
| ------------------------------------------------- | ------------------------------------ |
| New database migrations, schema changes           | Architecture review is high priority |
| Auth, session, token, API key files               | Security review is high priority     |
| Hot-path code, controllers, handlers, middleware  | Performance review is high priority  |
| Config, routes, infrastructure                    | Architecture review is high priority |
| Tests only                                        | Light review, focus on test quality  |
| Docs only                                         | Light review, focus on clarity       |

If the PR is large (>50 files), warn the user and ask if they want a
focused review on specific files.

Separately, scan for the mandatory human-callout triggers, used later in "Synthesize findings", not tied to a severity:

| Trigger                                                        | Callout                                    |
| --------------------------------------------------------------- | ------------------------------------------ |
| New migration files, schema changes                              | Database migration                         |
| New entry in a dependency manifest                               | New dependency                             |
| Version bump in a dependency manifest or lockfile-only diff      | Dependency change                          |
| Auth, session, permission, or access-control code touched        | Auth/permission behavior change            |
| Removed/renamed public API, changed response shape, schema field | Backwards-incompatible contract change     |
| `DROP`, bulk `DELETE`, `rm`, force-push, or other irreversible op | Irreversible/destructive operation         |
| Feature flag added, removed, or a dormant one reused             | Feature flag change                        |
| Changed default value in a config file                           | Configuration default change               |

Collect which of these apply and to which files, you'll need this for the "Human Reviewer Callouts" section later. Not finding any is a normal, common outcome, don't force a match.

## Review rubric

Append this rubric to both sub-agent prompts, plus the contents of
`REVIEW_GUIDELINES.md` if one was found, labeled as project-specific and
taking precedence over the rubric below where the two conflict.

```
## Determining what to flag
Only flag something if all of these hold:
- It was introduced by this change, not a pre-existing issue.
- It's discrete and actionable, not a vague or combined concern.
- It has provable impact you can point to, not speculation about what might break.
- It doesn't rely on unstated assumptions about the codebase or author's intent.
- The author would plausibly fix it if they knew about it.

## Clean code
- Check whether a newly added function duplicates existing functionality elsewhere in the codebase. If it does, name the existing implementation.
- Flag one-off helper functions that add indirection without improving clarity or reuse.
- Flag abstractions introduced without a concrete need in this change, including wrappers built only for hypothetical future use.
- Flag defensive checks or fallback behavior that mask programming errors, especially when callers already guarantee the relevant invariant.

## Fail-fast error handling
- For every new or changed try/catch, identify what can fail and why handling it locally, at this exact layer, is correct.
- Prefer propagation over local recovery: if this scope can't fully recover while preserving correctness, rethrow, with context, instead of returning a fallback.
- Flag catches that hide failure signals: returning null/[]/false, swallowing JSON parse errors, logging-and-continuing, or other silent "best effort" recovery.
- JSON parsing/decoding should fail loudly by default. Quiet fallback parsing is only acceptable with an explicit, tested compatibility requirement.
- Boundary handlers, HTTP routes, CLI entrypoints, supervisors may translate errors, but must not fake success or silently degrade.

## Untrusted input
- Open redirects must be checked against an allowlist of trusted destinations.
- SQL must always be parametrized, never string-concatenated.
- Server-side fetches of user-supplied URLs need protection against internal/
  local resource access, including DNS-rebinding.
- Prefer escaping over sanitizing when either option is available.

## Line references
- Keep line ranges short, avoid ranges over 5-10 lines, pick the tightest sub-range that shows the issue.
```

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
- Background vs foreground work, heavy ops in request cycle?

## PR Under Review
Title: {pr_title}
Description: {pr_description}

## Changed Files
{file_list}

## Full Diff
{diff_content}

## Classification Notes
{classification_signals}

## Review Rubric
{review_rubric}

## Project Review Guidelines, override the rubric above where more specific
{review_guidelines_or_omit_if_none}

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
built-in review framework, execution multiplier, N+1, injection, secrets.

## PR Under Review
Title: {pr_title}
Description: {pr_description}

## Changed Files
{file_list}

## Full Diff
{diff_content}

## Review Rubric
{review_rubric}

## Project Review Guidelines, override the rubric above where more specific
{review_guidelines_or_omit_if_none}

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

### Verdict
`correct`, no blocking issues, or `needs attention`, has blocking issues.

### CRITICAL
Findings rated CRITICAL or HIGH. Include sub-agent source, file path, and a concrete fix suggestion.

### MEDIUM
Findings rated MEDIUM. Same format.

### LOW
Findings rated LOW or NIT. Brief, not exhaustive.

### Coverage
- Architecture: found N issues
- Quality/Security/Performance: found N issues

### Human Reviewer Callouts
Populate from the callout scan in "Classify the change". Include only
applicable callouts, each bolded exactly as below; write "- None" if none apply. These are informational for the human reviewer, not fix items, they must not themselves change the Verdict:
- **This change adds a database migration:** <files/details>
- **This change introduces a new dependency:** <package(s)/details>
- **This change changes a dependency, or the lockfile:** <files/package(s)/details>
- **This change modifies auth/permission behavior:** <what changed and where>
- **This change introduces backwards-incompatible public API/schema/contract changes:** <what changed and where>
- **This change includes irreversible or destructive operations:** <operation and scope>
- **This change adds or removes feature flags:** <flags changed>, call out re-use of dormant flags
- **This change changes configuration defaults:** <config var changed>
```

## Prompt to post

After presenting the review, ask the user:

> Post review with inline comments to the PR?

If yes, write each finding as a natural comment like a teammate reviewing code. Do not use emojis or markdown flourishes. Do not open with preambles. Just state the issue and suggestion directly. Keep each comment to at most one paragraph, and keep any inline code under 3 lines. When you're confident in a concrete, minimal fix, add a ```suggestion block containing only the replacement code, no commentary inside it, and preserve the exact leading whitespace of the lines it replaces. Skip the suggestion block for anything speculative or multi-part. Then post as a review with inline comments:

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

- Keep findings tied to specific files and short line ranges, 5-10 lines max.
- Only flag issues introduced by this change, not pre-existing code, unprovable/speculative impact, or things that rely on unstated assumptions about intent.
- Do not suggest architectural rewrites unless the PR introduces a clear regression.
- For large PRs, ask the user if they want focused review on specific areas.
- No emojis, no markdown dividers, no decorative formatting anywhere in the review or inline comments.
- Write like a human teammate in a code review thread. Skip preambles and get to the point.
- Keep comments brief and matter-of-fact, no flattery, no exaggerated severity. State the concrete scenario where the issue arises.
- The Human Reviewer Callouts section is informational only, never let it change the Verdict or get restated as a Finding.
