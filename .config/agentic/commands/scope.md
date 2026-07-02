---
description: Assess scope and define implementation approach
agent: leader
---

# Scope

Assess scope, present approach, and iterate based on feedback until user approves.

## Entry Criteria

- User has a task/feature/bug to address.
- Task is sufficiently complex to warrant planning (not one-liners).

## Exit Criteria

- User explicitly approves the plan (e.g. "yes", "go ahead", "proceed", "sounds good", "looks good", "ship it").
- Scope is bounded and clear.
- Implementation approach is agreed upon.
- Risks and constraints are documented (if any).

## Phase Transition

After approval → delegate to `implementor` via the Task tool with the approved scope, files, and acceptance criteria.
If a plan is not needed (simple tasks), use `/code` to invoke `implementor` directly without scoping.
If scope changes significantly during implementation → return to `/scope`.
