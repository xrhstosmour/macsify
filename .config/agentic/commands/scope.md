---
description: Assess scope and define implementation approach
agent: leader
---

# Scope

Assess scope, present approach, and iterate based on feedback until user approves.

## Protocol

1. Context Discovery: delegate discovery to an exploration subagent where the tool has one, otherwise read the files yourself within the same budget. Pass it the task and any known entry points, let it search, cap reads at about 15 files. Ask for relevant files with path:line references, existing helpers and patterns to reuse, callers the change affects, constraints, and a list of what it did not read.
2. Multi-Approach Proposal: delegate to `architect` with the exploration summary, not the raw files. It owns the discovery rules and the 2-3 approach format, see `agents/architect.md`.
3. Human Sign-off: wait for explicit approval of one approach before proceeding to implementation.

## Large Implementations

When the task touches three or more files, or has several decisions the user must make, and the `html-plan` skill is available, invoke it for steps 2 and 3 instead of writing the approaches in chat. The user answers the decisions in the page and pastes the response back, which counts as the sign-off. Do not invoke it for small or single-file tasks, it costs extra tokens. If the skill is not available, present the approaches in chat as usual.

## Big Tasks Tracked on a Board

When the approved plan has three or more discrete, orderable steps that will span several sessions or pull requests, offer once to track it on a `GitHub` project board. Invoke the `manage-github-project` skill to publish one issue per step, it owns the preview, the confirmation, and the status sync. Never create issues or a board without the user's approval, and skip the offer for work that fits one session or one pull request.

While the plan runs, each step's pull request closes its issue with a `Resolves` line, per `manage-github-pr`, and the `manage-github-project` skill moves the status as steps start and merge.

## Entry Criteria

- User has a task/feature/bug to address.
- Task is sufficiently complex to warrant planning (not one-liners).

## Exit Criteria

- User explicitly approves the plan (for example "yes", "go ahead", "proceed", "sounds good", "looks good", "ship it").
- Scope is bounded and clear.
- Implementation approach is agreed upon.
- Risks and constraints are documented (if any).

## Phase Transition

After approval → delegate to `implementor` via the Task tool with the approved scope, files, and acceptance criteria.
If a plan is not needed (simple tasks), use `/code` to invoke `implementor` directly without scoping.
If scope changes significantly during implementation → return to `/scope`.
