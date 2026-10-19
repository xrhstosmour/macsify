# Rules

## Core

- Implement in small steps, validate incrementally.
- Complex and multi-step tasks go through `/scope`, which owns discovery, approach, and sign-off.
- Before any user-facing operation, invoke a matching skill first (Claude Code: `skill` tool, OpenCode: `SKILL.md`), even in Plan Mode or when a command or subagent chain drives. Do not hand-roll what a skill covers.
- Tests required for behavior changes.
- Prioritize security and performance risks.
- Read a file before editing it, several in parallel.
- State your reasoning before executing any command, always non-interactive.
- Use absolute paths, or verify them, before destructive commands. Inform the user of long-running processes.
- Never fabricate. If you don't know, say so. Answer only with evidence you can point to, a file you read, a command output you saw, a source you cited, and if the source doesn't support your answer, say so. If nothing is wrong, say so.
- Never claim work is done without the command output that proves it.
- Add only essential code comments.

## Flagging Convention

Use this for anything adjacent, out of scope, dead, or risky. Skip it when there is nothing to flag, one line per item, no block for a trivial change:

``` text
FLAGGED:
- [what]: [why it matters], [what you need, ok to remove? / fyi only / needs a decision]
```

## Code Style

- Code comments end with a period, above the code they describe, not inline.
- Documentation comments on new methods match the neighbouring ones.
- Max line length is `editor.rulers`, project `.vscode/settings.json` first, then the user's VS Code settings. Without rulers, 80 soft and 100 hard.
- Single, whole-word names, never abbreviate, `documents` not `docs`, `reference` not `ref`, `temporary` not `tmp`, `error` not `err`, `message` not `msg`, `configuration` not `config`. Common acronyms, `ID`, `URL`, `API`, `HTTP`, are fine.

## Self-Critique

After implementing code, re-read it, question whether there is a better approach, fix concerns before moving on. Max 3 iterations, then ask the user. On a mistake or ignored rule, acknowledge it immediately, revert, and explain.

Before pushing, check the diff against this list:

- New tests follow the test authoring rules under Test Junk Patterns.
- Queries eager-load what they read in a loop, no N+1.
- A multi-step write sits in a transaction, a mid-way failure cannot leave half the change.
- An existing helper does not already do it, search before adding one.
- Null, empty, and ambiguous-match inputs are handled, an arbitrary pick among several matches has a tiebreak.
- A dependency outage on the new path is handled or surfaced, not swallowed.

## Verification

Before writing code, confirm the requirement, ask if unsure, check existing patterns, run lint and typecheck for a baseline, verify unfamiliar library APIs against official docs. After writing code, run lint and typecheck, review `git diff`, and run tests as follows:

- With a CI test pipeline, a test job on the branch or PR, not a deployment pipeline, run only a targeted test locally, the single file or spec for the change, one quick command, and leave the full suite to that pipeline after the push. No long or serial suite locally, no local datastore stack just to run it.
- Without a CI test pipeline, run the relevant tests locally before moving on.

## Implementation

- Vertical slices, one complete path through the stack at a time: Implement, Test, Verify, Commit, next slice. After each slice the project builds and tests pass, each increment independently revertable and additive where possible.
- Never mix a refactor with a feature in one commit. Gate incomplete features behind a flag.
- Touch only what the task requires, no cleanup of adjacent code, unrelated imports, unrequested features, or comments you don't fully understand. Flag improvements instead.
- Before changing or removing anything, understand why it exists, what calls it, what it calls, the edge cases, `git blame` if needed. A function with tests can be refactored, one without is not deleted or renamed without asking.
- After refactoring, flag code that became unused and ask before deleting.

### Simplicity

Understand the problem and read the code the change touches first, then stop at the first rung that holds:

1. Does it need to exist? Speculative need, skip it and say so.
2. Already in this codebase? Reuse the helper, type, or pattern, prefer existing patterns over new abstractions.
3. Standard library or native platform feature (`<input type="date">`, a database constraint) over a dependency.
4. An installed dependency over a new one, never add one for what a few lines can do.
5. Otherwise the minimum code that works, one line if it fits.

Never simplify away input validation at trust boundaries, error handling that prevents data loss, security, accessibility, or anything the user asked for. Three similar lines beat a premature abstraction.

### Comment and Test Hygiene

Reread comments near the code you touched, one explaining a shape that moved is orphaned but reads as true. When two files explain the same fact, one carries it and the other points at it by name. Drop a test that only reproves what an earlier test in the same file guarantees.

### Test Junk Patterns

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

Don't flag a test just for looking similar, verify it protects a distinct contract first. A bug regression test must fail on the pre-fix code for the intended reason and pass after the fix, the author checks this, it is not verifiable from a diff, do not flag it in review.

## Migrations

Naming and chain-linearity rules live in the `migrations` skill, it auto-triggers.

## Skills in Plans

In a plan step or subagent prompt for a skill-covered action, name the skill to invoke, never the raw command it wraps, even when the flags look right.

- Wrong: 'Push the branch and open a PR via `gh pr create` with a Summary/Test plan body.'
- Right: 'Push the branch, then invoke the `manage-github-pr` skill to open the PR.'

A project skill beats a same-topic plugin skill. When a skill defines a checklist, apply every item.

## Safety

- Confirm before destructive operations (`rm`, `DROP TABLE`, `DELETE FROM`), never skip safety checks for speed, provide a rollback plan for risky changes, stop and ask if unsure about consequences.
- Warn immediately if secrets or credentials are staged.

## Error Handling and Stop the Line

When a command fails, show the exact command and error output, then stop and ask, no fallback without approval. When code fails, report the root cause and failing output, propose a fix before implementing, re-test after. Empty logs do not mean it works, say the root state is unknown.

On an environment blocker, such as a signing, authentication, or container runtime problem, name the single blocker, then stop and wait for the user to say it is fixed, no retrying or polling. Never poll CI or a long-running job unless asked.

When anything unexpected happens, stop adding features, preserve evidence, diagnose with the `diagnose` skill, fix the root cause, guard it with a regression test, resume only after verification passes. Never push past a failing test or broken build.

When requirements or code conflict or are unclear, stop, name the confusion ("I see X in the spec but Y in the code"), present the tradeoff or ask, and wait. For a multi-step or ambiguous task, surface assumptions and plan before executing:

``` text
ASSUMPTIONS: [only if any]
PLAN:
1. [first step]
```

## Context Management

Cost is context size times turns. Autocompaction acts near the window limit and Claude Code also compacts after an idle gap, so cost keeps growing every turn until one of them fires.

- Never run `/handoff` or `/compact` yourself. Advise them only when a hook warning asks you to, compaction is otherwise left to the host.
- Split sessions at natural boundaries, after a PR merge or a phase change. Start fresh for unrelated work.
- Use the explore subagent for code discovery instead of reading large files in the main context.
- Use the Grep and Glob tools, not Bash `grep` or `find`. When a tool is missing, use `rg` through Bash with `-m` or `-c`, do not retry the missing tool. Read with `offset` and `limit` for files over about 15KB, don't re-read a file you already have.
- Pass a subagent the diff or file list it needs, not a rediscovery task.
- Make commands selective (`grep -c`, `jq` filters, `rg -m`, `sed -n` ranges). Keep only the salient lines of a large result and say how many were elided. Never drop information that changes the answer.
