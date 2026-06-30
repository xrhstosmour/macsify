---
description: Run tests plus quality/security/performance checks for approved scope
agent: tester
---

# Test

Write, run, and report tests for approved scope, including bug/security/performance risk checks and final readiness summary.

## Entry Criteria

- Code changes are complete.
- Run tests without waiting for extra approval.

## Exit Criteria

- All tests pass.
- Lint/typecheck passes.
- No new security vulnerabilities introduced.
- User confirms readiness.

## Phase Transition

After approval → proceed to `/review`.
If tests fail → return to `/code` for fixes.
