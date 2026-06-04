# Rules

## Core

- Think first, then implement in small steps and validate incrementally.
- Prefer existing patterns over new abstractions.
- Tests required for behavior changes.
- Prioritize security and performance risks.
- Keep communication concise and direct.
- Always read file before editing.
- Read multiple files in parallel.
- Before executing any command, state your reasoning.
- Always use non-interactive mode.
- Use absolute paths or verify them before destructive commands.
- Inform user of long-running processes.
- Apply all explicit user-provided context (links, images, constraints) in the next actions.
- Do not skip user-provided context unless it directly conflicts with safety.
- Never fabricate findings. If nothing is wrong, say so explicitly.

## Code Style

### Comments

All code comments in every language must end with a period. Comments go above the code they describe, not inline to the right.

### Line Length / Rulers

New code changes should respect language-specific ruler settings from the editor configuration:

- Check VS Code settings for language-specific `editor.rulers` values:
  - Project settings: `.vscode/settings.json`
  - User settings:
    - macOS: `~/Library/Application Support/Code/User/settings.json`
    - Linux: `~/.config/Code/User/settings.json`
    - Windows: `%APPDATA%\Code\User\settings.json`
- If language-specific rulers are found, use them as the maximum line length guide.
- If no language-specific rulers exist, fallback to 80-100 characters as the horizontal limit.
  - Soft limit: 80 characters
  - Hard limit: 100 characters

## Self-Critique

After implementing code, pause and self-critique:

1. Re-read your work.
2. Question your approach: "Did I do this right? Is there a better way?".
3. If concerns arise, fix them before moving on.
4. Max 3 iterations, then ask user for help.
5. If you realize you made a mistake or ignored a rule, acknowledge it immediately, revert, and explain.

## Implementation

### Increment Cycle

``` text
Implement → Test → Verify → Commit → Next slice
```

Build in vertical slices, one complete path through the stack at a time. After each slice the system must build and existing tests must pass.

### Scope Discipline

Touch only what the task requires. Do not clean up adjacent code, refactor unrelated imports, add non requested features, or remove comments you don't fully understand.

If you notice something worth improving outside scope, note it, don't fix it:

``` text
NOTICED BUT NOT TOUCHING:
- src/utils/format has an unused import (unrelated)
- The auth middleware could use better error messages (separate task)
```

### Simplicity

Before writing code, ask: "What is the simplest thing that could work?" After writing, review: can this be done in fewer lines? Are these abstractions earning their complexity? Am I building for hypothetical future requirements?

Three similar lines of code is better than a premature abstraction. Implement the naive version first. Optimize after correctness is proven.

### Chesterton's Fence

Before changing or removing anything, understand why it exists. What calls it, what does it call, what are the edge cases? Check git blame if needed. If you can't answer these, read more context first.

### Dead Code Hygiene

After refactoring, identify code that became unreachable or unused. List it explicitly and ask before deleting:

``` text
DEAD CODE IDENTIFIED:
- formatLegacyDate() in src/utils/date — replaced by formatDate()
- OldWidget in src/widgets/ replaced by Widget
-> Safe to remove these?
```

Don't leave dead code lying around, it confuses future readers and agents. Don't silently delete things you're not sure about.

### Implementation Rules

- One thing at a time, don't mix refactors with features in the same commit.
- Feature flags: Gate incomplete features behind a flag so you can merge increments safely.
- Safe defaults: New code should be opt-in, conservative.
- Rollback-friendly: Each increment should be independently revertable. Prefer additive changes.
- Keep it compilable: Project must build and tests pass after each increment.

## Verification Before Code

Before writing any code:

- Confirm you understand the requirement (ask if unsure).
- Verify the file you need to edit exists and is the right one.
- Check for existing patterns in the codebase.
- Run lint/typecheck early to establish baseline.
- If using unfamiliar library APIs, verify against official docs first, never assume an API exists.

After writing code:

- Run lint/typecheck to catch style issues immediately.
- Run relevant tests before moving on.
- Review changes with `git diff` before presenting.

## Tool Usage

Hard rules, not suggestions:

- `WebFetch`: NEVER use for `GitHub`, `Phabricator`, or `Sentry` URLs. Instead, use their respective CLIs or APIs as shown in their context files:
  - `GitHub` URLs: Use `gh` CLI or `gh api`. See `~/.config/opencode/context/tools/github.md`.
  - `Phabricator` URLs: Use the Phabricator API. See `~/.config/opencode/context/tools/phabricator.md`.
  - `Sentry` URLs: Use `sentry-cli` or the Sentry API. See `~/.config/opencode/context/tools/sentry.md`.

## Safety

- Confirm before destructive operations (`rm`, `DROP TABLE`, `DELETE FROM`, etc.).
- Never skip safety checks for speed.
- Always provide rollback plan for risky changes.
- Stop and ask if unsure about consequences.
- Warn immediately if secrets or credentials are staged.

## Error Handling

When commands fail:

1. Show exact command that failed.
2. Show exact error output.
3. Stop and ask user for guidance.
4. Do not continue with fallback unless user approves.

When code fails:

1. Report the failure with root cause.
2. Show the failing test output or stack trace.
3. Propose fix approach before implementing.
4. Re-test after fix.

## Stop the Line

When anything unexpected happens, STOP adding features. Preserve evidence (error output, logs, repro steps). Diagnose using the triage below. Fix the root cause, not the symptom. Guard with a regression test. Resume only after verification passes.

Do not push past a failing test or broken build to work on the next feature.

## Debugging

Follow this triage checklist in order:

### 1. Reproduce

Make the failure happen reliably. For test failures:

```bash
<test command> --filter "test name"
<test command> --path "specific-file" --isolated
```

### 2. Localize

Narrow down which layer fails: UI, API, database, build, external service, or the test itself. For regressions, find the commit:

```bash
git bisect start
git bisect bad HEAD
git bisect good <known-good-commit>
git bisect run <test command> --filter "failing test"
```

### 3. Reduce

Create the minimal failing case, remove unrelated code until only the bug remains.

### 4. Fix the Root Cause

Fix the underlying issue, not the symptom. Ask "why does this happen?" until you reach the actual cause. Example: duplicate entries in UI. Symptom fix is de-dup in component, root cause fix is correcting the query.

### 5. Guard Against Recurrence

Write a regression test that fails without the fix and passes with it.

### 6. Verify End-to-End

```bash
<test command> # Full suite or specific test.
<build command> # Type/compilation.
```

## Confusion Management

When encountering inconsistencies, conflicting requirements, or unclear specifications:

1. STOP. Do not proceed with a guess.
2. Name the specific confusion: "I see X in the spec but Y in the existing code."
3. Present the tradeoff or ask the clarifying question.
4. Wait for resolution before continuing.

Surface assumptions before implementing:

``` text
ASSUMPTIONS I'M MAKING:
1. [assumption about requirements]
2. [assumption about architecture]
3. [assumption about scope]
```

For multi-step tasks, emit a lightweight plan before executing:

``` text
PLAN:
1. [first step]
2. [second step]
3. [third step]
```

## Context Anti-Patterns

| Anti-Pattern | Fix |
| --- | --- |
| Agent invents APIs, ignores conventions | Load rules file and relevant source files before each task |
| Agent loses focus with too much context | Include only what is relevant to the current task |
| Agent guesses when it should ask | Surface ambiguity explicitly |
| Agent invents new style instead of following yours | Include one example of the pattern to follow |
| Agent doesn't know project-specific rules | Write it down in rules files, if it's not written, it doesn't exist |
