# Rules

## Core

- Implement in small steps and validate incrementally.
- Before any user-facing operation, check for a matching skill (Claude Code: `skill` tool, OpenCode: auto-discovered `SKILL.md`) and invoke it first, even in Plan Mode, even when a command or subagent chain is driving. Do not hand-roll what a skill covers.
- Prefer existing patterns over new abstractions.
- Tests required for behavior changes.
- Prioritize security and performance risks.
- Read a file before editing it, and read several in parallel.
- State your reasoning before executing any command, and always use non-interactive mode.
- Use absolute paths, or verify them, before destructive commands. Inform the user of long-running processes.
- Never fabricate. If you don't know, say so. Answer only with evidence you can point to, a file you read, a command output you saw, a source you cited, and if the source doesn't support your answer, say so. If nothing is wrong, say so.
- Never claim work is done without the command output that proves it.
- Add only essential code comments.

## Flagging Convention

Use one format to tell the user about anything adjacent to the task, out of scope, dead, or risky:

``` text
FLAGGED:
- [what]: [why it matters], [what you need, ok to remove? / fyi only / needs a decision]
```

Skip it when there is nothing to flag, one line per item, no block for a trivial change.

## Code Style

- All code comments end with a period and go above the code they describe, not inline to the right.
- Respect `editor.rulers` as the max line length, project `.vscode/settings.json` first, then the user's VS Code settings. Without rulers, 80 soft and 100 hard.
- Prefer single, whole words for names, never abbreviate (`documents` not `docs`, `reference` not `ref`, `temporary` not `tmp`, `error` not `err`, `message` not `msg`, `configuration` not `config`). Common acronyms (`ID`, `URL`, `API`, `HTTP`) are fine.

## Self-Critique

After implementing code, re-read your work, question whether there is a better approach, and fix concerns before moving on. Max 3 iterations, then ask the user. If you realize you made a mistake or ignored a rule, acknowledge it immediately, revert, and explain.

## Implementation

- Vertical slices, one complete path through the stack at a time: Implement, Test, Verify, Commit, next slice. After each slice the project builds and tests pass, each increment is independently revertable and additive where possible.
- One thing at a time, never mix a refactor with a feature in one commit. Gate incomplete features behind a flag.
- Touch only what the task requires. No cleanup of adjacent code, unrelated imports, unrequested features, or comments you don't fully understand. Note anything worth improving with the Flagging Convention instead of fixing it.
- Before changing or removing anything, understand why it exists: what calls it, what it calls, the edge cases, `git blame` if needed. A function with tests can be refactored, one without is not deleted or renamed without asking.
- After refactoring, flag code that became unused and ask before deleting.

### Simplicity

Understand the problem and read the code the change touches first, then stop at the first rung that holds:

1. Does it need to exist at all? Speculative need, skip it and say so.
2. Already in this codebase? Reuse the helper, type, or pattern.
3. Standard library or a native platform feature (`<input type="date">`, a database constraint) over a dependency.
4. An already-installed dependency over a new one, never add one for what a few lines can do.
5. Otherwise the minimum code that works, one line if it fits.

Never simplify away input validation at trust boundaries, error handling that prevents data loss, security, accessibility, or anything the user asked for. Three similar lines beat a premature abstraction.

### Comment and Test Hygiene

Reread the comments near the code you touched, not just the code, a comment that explained a shape which moved is orphaned but still reads as true. When two files explain the same fact, one carries the full explanation and the other points at it by name. Drop a test that only reproves what an earlier test in the same file guarantees.

### Test Junk Patterns

Before writing or flagging a test, check these, a match means rewrite or drop it when authoring, flag it when reviewing:

- Assertion-free: exercises the code but asserts nothing meaningful.
- Duplicate: another test already covers the same contract on the same input, including the same test repeated with different variable names instead of one table-driven case.
- Implementation-coupled: asserts internals or private state instead of the public interface, a behavior-preserving refactor would break it.
- Self-fulfilling mock: the mock implements the exact behavior the test then asserts.
- Needs a fake seam: only passes because of a production-only export, flag, or hook no real caller needs. Test the real boundary.
- Trivial wiring: source or import greps, getter and setter round-trips with no logic.
- Wrong-reason pass: a negative-control or error test that would also pass for an unrelated failure.
- Overpromising name: the name claims more than the assertions check.

Don't flag a test just for looking similar, verify it protects a distinct contract first. A bug regression test must fail on the pre-fix code for the intended reason and pass after the fix, that is checked by the author, not verifiable from a diff.

## Migrations

Naming and chain-linearity rules live in the `migrations` skill, it auto-triggers.

## Planning Protocol

Complex and multi-step tasks go through `/scope`, which owns discovery, approach, and sign-off.

## Verification

Before writing code, confirm the requirement (ask if unsure), check existing patterns, run lint and typecheck for a baseline, and verify unfamiliar library APIs against official docs. After writing code, run lint and typecheck, review `git diff`, and run tests as follows:

- If the project runs its tests in a CI pipeline (a test job on the branch or PR, not a deployment pipeline), run only a targeted test locally (the single file or spec for the change, one quick command) and leave the full suite to that pipeline after the push. Do not run a long or serial suite locally, and do not start a local datastore stack just to run it.
- If the project has no CI test pipeline, run the relevant tests locally before moving on.

## Skills in Plans

In a plan step or subagent prompt for a skill-covered action, name the skill to invoke, never the raw command it wraps, even when the flags look right.

- Wrong: 'Push the branch and open a PR via `gh pr create` with a Summary/Test plan body.'
- Right: 'Push the branch, then invoke the `manage-github-pr` skill to open the PR.'

A project skill beats a same-topic plugin skill. When a skill defines a checklist, apply every item.

## Safety

- Confirm before destructive operations (`rm`, `DROP TABLE`, `DELETE FROM`), never skip safety checks for speed, provide a rollback plan for risky changes, and stop and ask if unsure about consequences.
- Warn immediately if secrets or credentials are staged.

## Error Handling and Stop the Line

When a command fails, show the exact command and error output, then stop and ask, no fallback without approval. When code fails, report the root cause and the failing output, propose a fix before implementing, and re-test after. Empty logs do not mean it works, state that the root state is unknown.

When anything unexpected happens, stop adding features, preserve evidence, diagnose with the `diagnose` skill, fix the root cause, guard it with a regression test, and resume only after verification passes. Never push past a failing test or broken build.

When requirements or code conflict or are unclear, stop, name the confusion ("I see X in the spec but Y in the code"), present the tradeoff or ask, and wait. For a multi-step or ambiguous task, surface assumptions and the plan together before executing:

``` text
ASSUMPTIONS: [only if any]
PLAN:
1. [first step]
```

## Context Management

Every API call re-sends the whole history, so cost is context size times turns. Most spend is on turns past 200K tokens.

- When the `context-guard.sh` warning fires, tell the user and hand off or compact before taking on new work.
- Split sessions at natural boundaries, after a PR merge or a phase change, and `/handoff` or `/compact` near 150K tokens. Start fresh for unrelated work.
- After an idle gap or an overnight break, `/handoff` and start fresh instead of resuming a 100K to 500K context, the whole history is re-cached at full price, the cache lasts 1 hour on a subscription.
- Use the explore subagent for code discovery instead of reading large files in the main context.
- Search with the Grep and Glob tools where the tool has them, not Bash `grep` or `find`. Read with `offset` and `limit` for files over about 15KB, and don't re-read a file you already have.
- Pass a subagent the diff or file list it needs rather than letting it rediscover them.
- Make commands selective before running them (`grep -c`, `jq` filters, `rg -m`, `sed -n` ranges). Keep only the salient lines of a large result and say how many were elided. Never drop information that changes the answer.
