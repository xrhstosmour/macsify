---
name: test-quality
description: Test junk patterns and test authoring rules. Use when writing, reviewing, or flagging tests.
---

# Test Quality

## Test Junk Patterns

Before writing or flagging a test, check these, a match means rewrite or drop it when authoring, flag it when reviewing:

- Assertion-free: asserts nothing meaningful.
- Duplicate: another test covers the same contract on the same input, including one test repeated with different variable names instead of a table-driven case.
- Implementation-coupled: asserts internals or private state instead of the public interface, a behavior-preserving refactor would break it.
- Self-fulfilling mock: the mock implements the behavior the test asserts.
- Needs a fake seam: only passes because of a production-only export, flag, or hook no real caller needs. Test the real boundary.
- Trivial wiring: source or import greps, getter and setter round-trips with no logic.
- Wrong-reason pass: a negative-control or error test that would also pass for an unrelated failure.
- Overpromising name: claims more than the assertions check.

Test authoring rules, on top of the patterns above:

- A test with several assertions groups them with the framework's multiple-failure feature.
- Every new branch of production code has a test that reaches it.
- Tests are the source of truth for behavior, someone describing a scenario should be able to read the test names and tell whether it is covered or a blind spot. Names and descriptions use plain business words, not method or class names.
- Cover scenarios, branches, and complications, not lines, line coverage is automatic and proves little.
- Integration first, unit second. A few large scenarios for the big picture, then small tests for what they do not reach.
Don't flag a test just for looking similar, verify it protects a distinct contract first. A bug regression test must fail on the pre-fix code for the intended reason and pass after the fix, the author checks this, it is not verifiable from a diff, do not flag it in review.

## Mutation Check

Optional, run it when a test's value is in doubt, not by default. Break only the production code the test covers, in a scratch worktree per the Worktrees rule in `versioning.md`, never the user's checkout, run that single test, then remove the worktree. Label each test:

- PROVEN: it fails for the intended reason.
- VACUOUS: it still passes, treat it as a junk test.
- INCONCLUSIVE: it fails for an unrelated reason, or the covered code cannot be isolated.
