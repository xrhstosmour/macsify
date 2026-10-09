# Rules

## Core

- Implement in small steps and validate incrementally.
- Before any user-facing operation, check for a matching skill (Claude Code: `available_skills`/`skill` tool, OpenCode: auto-discovered `SKILL.md`) and invoke it first. Do not hand-roll what a skill covers.
- Prefer existing patterns over new abstractions.
- Tests required for behavior changes.
- Prioritize security and performance risks.
- Keep communication concise and direct.
- Always read a file before editing it. Read multiple files in parallel.
- State your reasoning before executing any command, and always use non-interactive mode.
- Use absolute paths, or verify them, before destructive commands.
- Inform the user of long-running processes.
- Apply all explicit user-provided context (links, images, constraints), and don't skip it unless it conflicts with safety.
- Never fabricate. If you don't know, say so. Answer only with evidence you can point to, a file you read, a command output you saw, a source you cited. Read the source before quoting it, and if it doesn't support your answer, say so. If nothing is wrong, say so explicitly.
- Never claim work is done without the command output that proves it.
- Add only essential code comments, no fluff.

## Flagging Convention

Several rules here, and the Change Summaries rule in `versioning.md`, ask you to tell the user about something adjacent to the task: out of scope, dead, or risky. Use one shared format for all of them instead of a bespoke block per situation:

``` text
FLAGGED:
- [what]: [why it matters], [what you need, ok to remove? / fyi only / needs a decision]
```

Skip it entirely when there's nothing to flag. One line per item, no block at all for a trivial change with nothing adjacent worth noting.

## Code Style

### Comments

All code comments in every language must end with a period. Comments go above the code they describe, not inline to the right.

### Line Length / Rulers

Respect language-specific `editor.rulers` as the max line length: project `.vscode/settings.json` first, then user settings (macOS `~/Library/Application Support/Code/User/settings.json`, Linux `~/.config/Code/User/settings.json`, Windows `%APPDATA%\Code\User\settings.json`). If no rulers exist, fallback to 80 soft / 100 hard characters.

### Naming Conventions

Prefer single, whole words for variables, constants, functions, parameters, file names, and folder names, never abbreviate (`documents` not `docs`, `reference` not `ref`, `temporary` not `tmp`, `previous` not `prev`, `error` not `err`, `message` not `msg`, `maximum`/`minimum` not `max`/`min`, `index`/`count` not `idx`/`cnt`, `button` not `btn`, `configuration` not `config`). Common acronyms (`ID`, `URL`, `API`, `HTTP`) are fine.

## Self-Critique

After implementing code, pause and self-critique: re-read your work, question whether there's a better approach, and fix concerns before moving on. Max 3 iterations, then ask the user for help. If you realize you made a mistake or ignored a rule, acknowledge it immediately, revert, and explain.

## Implementation

### Increment Cycle

``` text
Implement → Test → Verify → Commit → Next slice
```

Build in vertical slices, one complete path through the stack at a time. After each slice the system must build and existing tests must pass.

### Scope Discipline

Touch only what the task requires. Do not clean up adjacent code, refactor unrelated imports, add non requested features, or remove comments you don't fully understand.

If you notice something worth improving outside scope, note it with the Flagging Convention, don't fix it.

### Simplicity

Before writing code, ask: "What is the simplest thing that could work?" Understand the problem and read the code the change touches first, then stop at the first rung that holds:

1. Does this need to exist at all? Speculative need, skip it and say so.
2. Already in this codebase? Reuse the existing helper, utility, type, or pattern instead of re-implementing it.
3. Does the standard library do it? Use it.
4. Does a native platform feature cover it? Prefer it over a dependency, for example `<input type="date">` over a picker library, or a database constraint over application code.
5. Does an already-installed dependency solve it? Use it. Never add a new one for what a few lines can do.
6. Can it be one line? One line.
7. Only then: the minimum code that works.

Never simplify away input validation at trust boundaries, error handling that prevents data loss, security, accessibility, or anything the user explicitly requested. The ladder shortens the solution, never the understanding of the problem.

Three similar lines of code is better than a premature abstraction. Implement the naive version first. Optimize after correctness is proven.

### Chesterton's Fence

Before changing or removing anything, understand why it exists. What calls it, what does it call, what are the edge cases? Check git blame if needed. If you can't answer these, read more context first. A function with tests can be refactored safely, a function with no tests is not deleted or renamed without asking.

### Dead Code Hygiene

After refactoring, identify code that became unreachable or unused. Flag it with the Flagging Convention and ask before deleting. Don't leave dead code lying around, and don't silently delete things you're not sure about.

### Comment and Test Hygiene

Comments go stale the same way code does, including at birth, when written near existing documentation. In the self-critique pass, reread the comments near the code you touched, not just the code. A comment that explained a shape which moved or disappeared is orphaned, still reading as true.

When two files explain the same fact or incident, only one should carry the full explanation. Point the other one at it by name instead of retelling it, two tellings drift apart.

Apply the same check to tests. A test that only reproves something an earlier test in the same file already guarantees adds no coverage and should be dropped.

### Test Junk Patterns

Before writing or flagging a test, check it against these patterns, a match means rewrite it or drop it when authoring, flag it when reviewing:

- Assertion-free: exercises the code but asserts nothing meaningful.
- Duplicate: another test already covers the same contract on the same input.
- Implementation-coupled: asserts internals or private state instead of the public interface, a behavior-preserving refactor would break it.
- Self-fulfilling mock: the mock implements the exact behavior the test then asserts, proving the mock, not the code.
- Needs a fake seam: only passes because of a production-only export, flag, or hook that no real caller needs. Test the real boundary instead.
- Copy-paste near-duplicate: the same test repeated with different variable names instead of one table-driven case.
- Trivial wiring: exact source/import greps, or getter/setter round-trips with no logic.
- Wrong-reason pass: a negative-control or error test that would also pass for an unrelated failure, not the guard under test.
- Overpromising name: the test name claims more than its assertions actually check.

Don't flag a test just because it looks similar to another, verify it protects a distinct contract or risk before calling it redundant. A bug regression test must fail on the pre-fix code for the intended reason and pass after the fix, if it never demonstrably failed, it proves nothing. Whether a regression test ever failed on the pre-fix code isn't verifiable from a diff though, that check belongs to the authoring gate, not review.

### Implementation Rules

One thing at a time, don't mix refactors with features in the same commit. Gate incomplete features behind a flag so you can merge increments safely. New code should be opt-in and conservative. Each increment should be independently revertable, prefer additive changes, and keep the project compilable, must build and tests must pass after each increment.

## Migrations

Naming and chain-linearity rules for database migration files live in the `migrations` skill, it auto-triggers when creating or reviewing a migration.

## Planning Protocol

Complex and multi-step tasks go through `/scope`, which owns the discovery, approach, and sign-off sequence.

## Verification Before Code

Before writing any code: confirm you understand the requirement (ask if unsure), verify the target file exists and is the right one, check for existing patterns in the codebase, run lint/typecheck early to establish a baseline, and verify unfamiliar library APIs against official docs first rather than assuming they exist.

After writing code: run lint/typecheck to catch style issues immediately, review changes with `git diff` before presenting, and run tests as follows.

- If the project runs its tests in a CI pipeline (a test job on the branch or PR, not a deployment pipeline), run only a targeted test locally (the single file or spec for the change, one quick command) and leave the full suite to that pipeline after the push. Do not run a long or serial suite locally, and do not start a local datastore stack just to run it.
- If the project has no CI test pipeline, run the relevant tests locally before moving on.

## Skills Priority

When a skill covers an operation, always invoke it first, never an ad-hoc command, and not only for the terminal step. Skills encode safety guardrails, consistency, and quality gates that ad-hoc tool usage lacks. This holds in Plan Mode (invoking a skill is read-only), and no matter which skill, command, or subagent chain is driving the session.

When a request could match more than one skill, for example a project skill in `~/.config/agentic/skills/` and a same-topic plugin/marketplace skill, prefer the project skill. When a skill defines a checklist, apply every item before finishing.

When writing a plan step or a subagent/delegation prompt for a skill-covered action, name the skill to invoke, never the raw command it wraps, even when the flags already look correct, knowing the flags is exactly what makes it tempting to skip the skill.

- Wrong: plan step 'Push the branch and open a PR via `gh pr create` with a Summary/Test plan body.'
- Right: plan step 'Push the branch, then invoke the `manage-github-pr` skill to open the PR.'
- Wrong: subagent prompt 'Open a PR with `gh pr create --title "..." --body "## Summary..."`.'
- Right: subagent prompt 'When your fix is committed, invoke the `manage-github-pr` skill to open the PR, do not run `gh pr create` directly.'

## Safety

- Confirm before destructive operations (`rm`, `DROP TABLE`, `DELETE FROM`, etc.).
- Never skip safety checks for speed.
- Always provide rollback plan for risky changes.
- Stop and ask if unsure about consequences.
- Warn immediately if secrets or credentials are staged.

## Error Handling

When commands fail: show the exact command that failed and the exact error output, then stop and ask the user for guidance. Do not continue with a fallback unless the user approves.

When code fails: report the failure with root cause, show the failing test output or stack trace, propose a fix approach before implementing, then re-test after the fix.

Empty logs or output do not mean it is working, state that the root state is unknown.

## Stop the Line

When anything unexpected happens, STOP adding features. Preserve evidence (error output, logs, repro steps). Diagnose using the `diagnose` skill. Fix the root cause, not the symptom. Guard with a regression test. Resume only after verification passes. Do not push past a failing test or broken build to work on the next feature.

When requirements or code conflict or are unclear, stop, don't proceed with a guess. Name the confusion ("I see X in the spec but Y in the existing code"), present the tradeoff or ask, and wait.

For a multi-step or ambiguous task, surface assumptions and the plan together before executing, so the user can correct either in one pass:

``` text
ASSUMPTIONS: [requirement/architecture/scope assumptions, only if any]
PLAN:
1. [first step]
2. [second step]
```

Skip this for a clear, single-step task.

## Context Management

Every API call re-sends the full conversation history, so long sessions burn tokens.

- Compact after every PR merge or major phase transition, and when the context health warning fires, immediately.
- After an idle gap past the prompt-cache TTL, or an overnight break, compact or `/handoff` and start fresh instead of resuming a 100K to 500K context, the whole history is re-cached at full price.
- Start a fresh session for unrelated work.
- Use the `explore` subagent for code discovery instead of reading large files in the main context.
- Read files with `offset`/`limit` when you only need a section, prefer `grep`/`glob` over `read` for searching, and don't re-read the same file across turns.
- Do not chain `grep`/`sed` into one compound shell command (semicolons, command substitution), multi-statement strings often fail the harness's read-only auto-approval parser and force a manual prompt.
- Shape commands to be selective before running them: `grep -c`, `jq` filters, `rg -m/-A/-B`, `sed -n` ranges. For a large repetitive result, keep only the unique or salient lines and say how many were elided, never silently drop information that changes the answer.
