---
description: Structured debugging loop for hard bugs and performance regressions
---

# Diagnose

Run a disciplined 6-phase diagnosis loop against the reported bug or performance regression.

## Entry Criteria

- User reports a bug, failure, or performance regression.
- Bug is not trivially obvious (skip for one-line fixes).

## Process

Follow the diagnose skill phases:

1. Build a feedback loop: Create a fast, deterministic, agent-runnable pass/fail signal.
2. Reproduce: Confirm the failure mode matches what the user described.
3. Hypothesise: Generate 3-5 ranked, falsifiable hypotheses.
4. Instrument: Test each hypothesis one variable at a time.
5. Fix + regression test: Fix the root cause and guard against recurrence.
6. Cleanup + post-mortem: Remove debug instrumentation, ask what would have prevented this.

Do not skip phases without explicit justification. Do not proceed past Phase 1 without a reliable feedback loop.
