---
description: Review code changes for quality, security, and best practices
agent: reviewer
---

# Review

Review code changes for quality, correctness, security vulnerabilities, and performance concerns.

## Inputs

Gather the diff and the changed-file list up front, for example `git diff <base>...HEAD` and `git diff --name-only <base>...HEAD`, and pass both to the reviewer so it does not rediscover them. Findings use the Finding format and Output from `agents/reviewer.md`.

## Entry Criteria

- `/test` phase is complete.
- All tests pass.

## Exit Criteria

- Review is complete.
- User approves final changes.
- No blocking issues remain.

## Phase Transition

If blocking issues found → return to `/code`.
If approved → ready for commit.
