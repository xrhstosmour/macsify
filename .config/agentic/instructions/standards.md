# Rules

## Core

- Think first, then implement in small steps and validate incrementally.
- Before any user-facing operation, check the skills your harness exposes (Claude Code lists them as `available_skills` and loads them via the `skill` tool, OpenCode auto-discovers `SKILL.md` files and surfaces them the same way). If a matching skill exists, invoke it as your first action. Do not hand-roll what a skill covers.
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
- Add only essential code comments, no fluff.

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

### Naming Conventions

Prefer single, whole words for variables, constants, functions, parameters, file names, and folder names. Never abbreviate or shorten words.

Common acronyms and initialisms are fine (`ID`, `URL`, `API`, `HTTP`), but do not shorten regular words.

- `documents` not `docs`
- `reference` not `ref`
- `temporary` not `tmp`
- `previous` not `prev`
- `error` not `err`
- `message` not `msg`
- `maximum` not `max`, `minimum` not `min`
- `index` not `idx`, `count` not `cnt`
- `button` not `btn`
- `configuration` not `config`

## Self-Critique

After implementing code, pause and self-critique:

1. Re-read your work.
2. Question your approach: "Did I do this right? Is there a better way?".
3. If concerns arise, fix them before moving on.
4. Max 3 iterations, then ask user for help.
5. If you realize you made a mistake or ignored a rule, acknowledge it immediately, revert, and explain.

## Hallucination Prevention

### Know Your Limits

- If you don't know something, say "I don't know" explicitly. Never invent an answer.
- Answer only when you are confident in your response. If confidence is below the threshold, state your uncertainty and ask for clarification instead.
- Prefer silence or a clarifying question over a plausible-sounding guess.
- The bar for "confident" is: you can point to specific evidence (a file you read, a command output you saw, a source you cited) that directly supports your claim.

### Think Before Answering

- Reason through the problem step-by-step before writing the final response.
- For non-trivial questions, show your reasoning or emit a lightweight plan before acting.
- If your reasoning reveals a gap, stop and address it rather than papering over it.

### Cite Your Sources

- When answering from documents, files, or external data, find and read the relevant source material first, then answer based on what you read.
- Quote or reference the source directly. Never paraphrase from memory what you can read from the source file.
- If the source material does not support your intended answer, say so.

### Self-Check Before Output

- Re-read your response before sending. Ask: "Is this factual? Can I point to where I got this from?"
- If you realize you fabricated something, acknowledge it immediately and correct it.
- Never fabricate findings. If nothing is wrong, say so explicitly.

### Contrastive Boundaries

| Scenario | Do | Don't |
| -------- | -- | ----- |
| Asked about an API you have not read the docs for | "I haven't checked the docs for that API yet. Let me look it up." | Invent method signatures or parameter names from memory. |
| Asked about a file you have not opened | "I haven't read that file. Let me open it first." | Describe the file's contents based on its name or path. |
| Asked if a bug exists | Read the code and run relevant tests, then answer with evidence. | "Probably not" without checking. |
| Asked to summarize a document | Read the document first, cite relevant sections. | Summarize from the title or general knowledge. |
| You are uncertain about the answer | "I'm not confident about this. Here's what I'd need to verify:" | Give a confident-sounding answer with no evidence. |

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

Before changing or removing anything, understand why it exists. What calls it, what does it call, what are the edge cases? Check git blame if needed. If you can't answer these, read more context first.

### Dead Code Hygiene

After refactoring, identify code that became unreachable or unused. List it explicitly and ask before deleting:

``` text
DEAD CODE IDENTIFIED:
- formatLegacyDate() in src/utils/date: replaced by formatDate()
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

### Migration Timestamps

Always use real, generated timestamps with millisecond precision when naming migration files. Never hardcode sequential or placeholder timestamps.

```bash
# Generate a real timestamp with milliseconds (UTC).
date -u +"%Y%m%d%H%M%S%3N"
```

Do not use timestamps that look hand-typed or sequential, like `20260706120000`, `20260706120001`, `20260707120000`. These lack sub-second precision and can collide when migrations are generated in rapid succession. Better use the framework's built-in migration generator if it exists, or generate a timestamp programmatically.

## Planning Protocol

For any complex or multi-step task, follow this sequence before writing code:

1. Context Discovery: Read all relevant files and environment first.
2. Multi-Approach Proposal: Present 2-3 distinct conceptual approaches before writing a single line of code.
3. Human Sign-off: Wait for explicit approval before executing.

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

## Skills Priority

When a skill covers an operation, always invoke it. Never use ad-hoc commands for operations that have a skill. Skills encode safety guardrails, consistency, and quality gates that ad-hoc tool usage lacks.

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

## Boundary Definition

Vague "do not" rules fail under complex instructions. Use contrastive binary examples to define sharp, unbreakable boundaries:

- If the error shows `Connection Refused` → infer a network configuration problem.
- If the logs are entirely empty → do NOT assume it is working. Output that the root state is unknown.
- If a function has tests → refactor safely.
- If a function has no tests → do NOT delete or rename it without asking first.

When writing rules for agents or yourself: Pair every prohibition with a concrete "do/don't" example so the boundary is unambiguous.

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

## Context Management

Manage context actively. Long sessions burn tokens because every API call
re-sends the full conversation history. A session that runs for days with
hundreds of messages will always balloon.

### Compaction Triggers

- Compact after every 2-3 completed subtasks. Do not batch more work into a bloated context.
- Compact after every PR merge or major phase transition.
- Compact before any idle gap longer than 30 minutes. Idle gaps force expensive cache rebuilds on the next turn.
- Never continue a session across calendar days. Start a fresh session instead. The previous session's summary carries forward.
- If the context health warning fires, compact immediately. Do not defer, do not start new work, do not rationalize one more small task first.

### Token-Saving Best Practices

- Use the `explore` subagent for code discovery instead of reading large files
directly in the main context. The subagent returns only the answer, not the full file content.
- Read files with `offset`/`limit` when you only need a specific section, not the entire file.
- Prefer `grep`/`glob` over `read` for searching patterns. Read only the matching files/sections.
- Avoid re-reading the same files across turns. Cache findings in your mental model or notes.

## Context Anti-Patterns

| Anti-Pattern | Fix |
| --- | --- |
| Agent invents APIs, ignores conventions | Load rules file and relevant source files before each task |
| Agent loses focus with too much context | Include only what is relevant to the current task |
| Agent guesses when it should ask | Surface ambiguity explicitly |
| Agent invents new style instead of following yours | Include one example of the pattern to follow |
| Agent doesn't know project-specific rules | Write it down in rules files, if it's not written, it doesn't exist |
