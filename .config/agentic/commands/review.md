---
description: Review code changes for quality, security, and best practices
agent: reviewer
---

# Review

Review code changes for quality, style consistency, security vulnerabilities, and performance concerns.

## Entry Criteria

- `/test` phase is complete.
- All tests pass.

## Exit Criteria

- Review is complete.
- User approves final changes.
- No blocking issues remain.

## Review Checklist

- Quality: Logic correct, error handling present.
- Style: Consistent with codebase conventions.
- Security: No vulnerabilities introduced.
- Performance: No obvious regressions.
- Tests: Coverage adequate for changes.

## Phase Transition

If blocking issues found → return to `/code`.
If approved → ready for commit.
