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
