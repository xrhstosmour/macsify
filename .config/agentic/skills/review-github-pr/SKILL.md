---
name: review-github-pr
description: >
  Multi-agent GitHub PR code review orchestrator. Fetches a PR by URL or branch name,
  spawns specialist sub-agents for architecture and quality review, then
  synthesizes findings into a structured report. Activate with: "review my PR",
  "review this PR", "/review-github-pr `<url_or_branch>`".
---

# GitHub PR Review Orchestrator

Delegates architecture and quality review to sub-agents and synthesizes one report.

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

Check whether the PR already has a review, so the same PR is not reviewed twice from scratch:

```bash
gh pr view <pr_number> --repo <owner>/<repo> --json reviews --jq '.reviews[] | {author: .author.login, state}'
```

If a review by the user (`gh api user --jq .login`) already exists and commits were pushed after it, or the user says the fixups are done, tell the user and treat this as a re-review, see the re-review exception under "Post inline comments". Reviews by bots or other people do not count.

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

Append this rubric to the `reviewer` sub-agent prompt, plus the contents of
`REVIEW_GUIDELINES.md` if one was found, labeled as project-specific and
taking precedence over the rubric below where the two conflict. The `architect`
gets only the "Determining what to flag", "Severity calibration", and "Line
references" sections, the rest is outside its brief. The `reviewer` gets all
sections except "Severity calibration" and "Untrusted input", its own agent file
already carries both, and Test Quality is absent for the same reason.

```
## Determining what to flag
Only flag something if all of these hold:
- It was introduced by this change, not a pre-existing issue.
- It's discrete and actionable, not a vague or combined concern.
- It has provable impact you can point to, not speculation about what might break.
- It doesn't rely on unstated assumptions about the codebase or author's intent.
- The author would plausibly fix it if they knew about it.

## Severity calibration
Cap, never upgrade: an attacker who already holds elevated privileges or is already executing code caps at MEDIUM unless the finding crosses to a different trust boundary entirely, container escape to host, cross-tenant escalation. Impact limited to the acting user's own data caps at LOW unless it also breaks non-repudiation or has side effects on other users or system stability. A pattern that looks bad but has no traceable exploit path is NIT or LOW, never higher. CRITICAL is reserved for a concretely-traced, no-privilege, no-interaction path to RCE, full auth bypass, or full data breach, anything needing privileges or user interaction is HIGH at most.

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

Invoke two sub-agents via the Task tool, running them concurrently. Skip the `architect` and run only the `reviewer` when the diff is under about 150 changed lines and touches no migrations, config, or routes, the two re-read the same files and the architect adds little on a small diff.

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
{review_rubric_determining_what_to_flag_and_line_references_only}

## Project Review Guidelines, override the rubric above where more specific
{review_guidelines_or_omit_if_none}

## Output Format
Return findings as:
## Architecture Review
### Findings
For each issue: [SEVERITY] file:line, problem description. Fix suggestion.
Severity: CRITICAL | HIGH | MEDIUM | LOW | NIT
### Summary
One paragraph. If no issues, say so explicitly.
```

### Reviewer agent

Prompt the `reviewer` agent with:

```
Review this PR for quality, security, and performance. Follow your
built-in review framework. Work from the diff below, do not re-run
`gh pr diff` or sweep the repo with `git log` or recursive greps, read a
file only for context the diff lacks, and stop within about 25 tool calls.

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
applicable callouts, each bolded exactly as below. Write "- None" if none apply. These are informational for the human reviewer, not fix items, they must not themselves change the Verdict:
- **This change adds a database migration:** <files/details>
- **This change introduces a new dependency:** <package(s)/details>
- **This change changes a dependency, or the lockfile:** <files/package(s)/details>
- **This change modifies auth/permission behavior:** <what changed and where>
- **This change introduces backwards-incompatible public API/schema/contract changes:** <what changed and where>
- **This change includes irreversible or destructive operations:** <operation and scope>
- **This change adds or removes feature flags:** <flags changed>, call out re-use of dormant flags
- **This change changes configuration defaults:** <config var changed>
```

## Next steps

After presenting the review, ask the user what they want to do with it:

1. Post review with inline comments to the PR.
2. Export the findings to a markdown file.
3. Fix the findings directly in the working tree.

### Option 1: Post inline comments

Keep each comment to at most one paragraph, and keep any inline code under 3 lines. When you're confident in a concrete, minimal fix, add a ```suggestion block containing only the replacement code, no commentary inside it, and preserve the exact leading whitespace of the lines it replaces. Skip the suggestion block for anything speculative or multi-part.

Determine the review event from the findings buckets in "Synthesize findings", this mapping is final, not a suggestion to confirm:

- CRITICAL section has entries -> event = `REQUEST_CHANGES`
- CRITICAL is empty, MEDIUM has entries -> event = `COMMENT`
- CRITICAL and MEDIUM both empty -> event = `APPROVE`

Re-review exception: when the user already reviewed the PR and the author pushed fixups since, or the user says the fixups are done, do not be strict. If CRITICAL (which includes HIGH) is empty, the event is `APPROVE` even with MEDIUM entries, and the MEDIUM findings go up as minor comments. Only a HIGH or CRITICAL finding blocks a re-review.

State the event and a one-line reason, e.g. "Recommending APPROVE, no CRITICAL/HIGH/MEDIUM findings." then proceed to post, findings always go up together as inline comments in the same review call regardless of event, LOW/NIT findings included as minor comments on an `APPROVE`.

The top-level review body posted to GitHub is a short headline, not the full Summary paragraph from "Synthesize findings". One short line, like a human reviewer signing off, no restating findings, no emojis, no bullet list. Match tone to the event and how much there is to flag, be creative rather than reusing the same phrase every time:

- APPROVE, nothing flagged at all -> something like "Great job, nothing to flag" or "Looks great, LGTM."
- APPROVE, only LOW/NIT findings -> something like "Nice work, a couple of small nits below."
- COMMENT, only MEDIUM findings -> something like "Some minor comments." or "A few small things worth a look."
- REQUEST_CHANGES -> something like "Think we should fix these first." or "A couple of blockers before this merges."

Then post as a review with inline comments:

```bash
HEAD_SHA=$(gh pr view <pr_number> --repo <owner>/<repo> --json commits --jq '.commits[-1].oid')

gh api repos/<owner>/<repo>/pulls/<pr_number>/reviews \
  -f commit_id="$HEAD_SHA" \
  -f event="<confirmed_event>" \
  -f body="<short_headline>" \
  -f comments='[
    {"path":"<file>","line":<line>,"body":"<human-like comment with fix suggestion>"},
    {"path":"<file>","line":<line>,"body":"<human-like comment with fix suggestion>"}
  ]'
```

Each comment references one finding, written conversationally in English.

### Option 2: Export to markdown

Write the synthesized review, Summary, Verdict, CRITICAL/MEDIUM/LOW, Coverage, Human Reviewer Callouts, to a markdown file. Default path `pr-<number>-review.md` in the repo root, confirm the path with the user before writing. Report the path when done, do not open it or take further action.

### Option 3: Fix the findings directly

Checkout the PR branch locally if not already on it:

```bash
git fetch origin <branch>
git checkout <branch>
```

Delegate each CRITICAL/HIGH and MEDIUM finding to the `implementor` agent with the finding's file, line range, problem, and fix suggestion. Skip LOW/NIT findings unless the user asks for them too. After fixes land, show `git diff` for the user to confirm, then split and commit following `~/.config/agentic/instructions/versioning.md`, use `fixup` commits targeting the original commit that introduced each finding where the PR already has commits, otherwise regular commits. Do not push without explicit approval, follow the push guardrails in `manage-github-pr` skill.

## Guardrails

- Keep findings tied to specific files and short line ranges, 5-10 lines max.
- Only flag issues introduced by this change, not pre-existing code, unprovable/speculative impact, or things that rely on unstated assumptions about intent.
- Do not suggest architectural rewrites unless the PR introduces a clear regression.
- For large PRs, ask the user if they want focused review on specific areas.
- Follow `~/.config/agentic/instructions/communication.md` for tone in the review and inline comments: no emojis, no markdown dividers, no decorative formatting, no preambles, no flattery, no exaggerated severity.
- State the concrete scenario where the issue arises.
- The Human Reviewer Callouts section is informational only, never let it change the Verdict or get restated as a Finding.
