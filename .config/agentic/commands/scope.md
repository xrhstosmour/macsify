---
description: Assess scope and define implementation approach
agent: leader
---

# Scope

Assess scope, present approach, and iterate based on feedback until user approves.

## Protocol

1. Context Discovery: read all relevant files, existing patterns, and constraints before proposing anything.
2. Multi-Approach Proposal: present 2-3 distinct conceptual approaches. Each needs a name, one-sentence description, and key trade-offs. Do not write code at this stage.
3. Human Sign-off: wait for explicit approval of one approach before proceeding to implementation.

## Large Implementations

When the task touches three or more files, or has several decisions the user must make, and the `html-plan` skill is available, invoke it for steps 2 and 3 instead of writing the approaches in chat. The user answers the decisions in the page and pastes the response back, which counts as the sign-off. Do not invoke it for small or single-file tasks, it costs extra tokens. If the skill is not available, present the approaches in chat as usual.

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
