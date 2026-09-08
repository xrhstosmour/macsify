# Rules

## Core

- Think first, then implement in small steps and validate incrementally.
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
- Never fabricate findings. If nothing is wrong, say so explicitly.
- Add only essential code comments, no fluff.

## Code Style

### Comments

All code comments in every language must end with a period. Comments go above the code they describe, not inline to the right.

### Line Length / Rulers

Respect language-specific `editor.rulers` as the max line length: project `.vscode/settings.json` first, then user settings (macOS `~/Library/Application Support/Code/User/settings.json`, Linux `~/.config/Code/User/settings.json`, Windows `%APPDATA%\Code\User\settings.json`). If no rulers exist, fallback to 80 soft / 100 hard characters.

### Naming Conventions

Prefer single, whole words for variables, constants, functions, parameters, file names, and folder names, never abbreviate (`documents` not `docs`, `reference` not `ref`, `temporary` not `tmp`, `previous` not `prev`, `error` not `err`, `message` not `msg`, `maximum`/`minimum` not `max`/`min`, `index`/`count` not `idx`/`cnt`, `button` not `btn`, `configuration` not `config`). Common acronyms (`ID`, `URL`, `API`, `HTTP`) are fine.

## Self-Critique

After implementing code, pause and self-critique: re-read your work, question whether there's a better approach, and fix concerns before moving on. Max 3 iterations, then ask the user for help. If you realize you made a mistake or ignored a rule, acknowledge it immediately, revert, and explain.

## Hallucination Prevention

### Know Your Limits

If you don't know something, say so explicitly, never invent an answer. Answer only when confident: you can point to specific evidence, a file you read, a command output you saw, a source you cited, that directly supports the claim. Below that bar, prefer silence or a clarifying question over a plausible-sounding guess.

### Think Before Answering

Reason through non-trivial questions step by step before writing the final response, showing your reasoning or a lightweight plan. If your reasoning reveals a gap, stop and address it rather than papering over it.

### Cite Your Sources

When answering from documents, files, or external data, find and read the relevant source material first, then quote or reference it directly, never paraphrase from memory what you can read from the source. If the source material doesn't support your intended answer, say so.

### Self-Check Before Output

Re-read your response before sending. Ask: is this factual, can I point to where I got it? If you realize you fabricated something, acknowledge it immediately and correct it.

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

One thing at a time, don't mix refactors with features in the same commit. Gate incomplete features behind a flag so you can merge increments safely. New code should be opt-in and conservative. Each increment should be independently revertable, prefer additive changes, and keep the project compilable, must build and tests must pass after each increment.

## Migrations

### Timestamps

Always use real, generated timestamps with millisecond precision when naming migration files. Never hardcode sequential or placeholder timestamps.

```bash
# Generate a real timestamp with milliseconds (UTC).
date -u +"%Y%m%d%H%M%S%3N"
```

Do not use timestamps that look hand-typed or sequential, like `20260706120000`, `20260706120001`, `20260707120000`. These lack sub-second precision and can collide when migrations are generated in rapid succession. Better use the framework's built-in migration generator if it exists, or generate a timestamp programmatically.

### Chain

Migration chains must stay linear with a single head. Concurrent PRs adding migrations from different ancestors create a multi-head state that blocks `upgrade head` and fails CI.

- **CI check**: Verify a single head in the lint step, no database connection required.
- **Generate from head**: Always run `upgrade head` first so new migrations chain off the current tip.
- **Merge heads immediately**: Resolve divergence via the framework's merge command in a dedicated PR before any new migration is added.
- **Down-revision from script**: Set `down_revision` to the output of `current`, after `upgrade head`, never an intermediate node.

## Planning Protocol

For any complex or multi-step task, follow this sequence before writing code:

1. Context Discovery: Read all relevant files and environment first.
2. Multi-Approach Proposal: Present 2-3 distinct conceptual approaches before writing a single line of code.
3. Human Sign-off: Wait for explicit approval before executing.

## Verification Before Code

Before writing any code: confirm you understand the requirement (ask if unsure), verify the target file exists and is the right one, check for existing patterns in the codebase, run lint/typecheck early to establish a baseline, and verify unfamiliar library APIs against official docs first rather than assuming they exist.

After writing code: run lint/typecheck to catch style issues immediately, run relevant tests before moving on, and review changes with `git diff` before presenting.

## Skills Priority

When a skill covers an operation, always invoke it. Never use ad-hoc commands for operations that have a skill. This is not limited to the terminal step. Skills encode safety guardrails, consistency, and quality gates that ad-hoc tool usage lacks.

When a request could match more than one skill, for example a project skill in `~/.config/agentic/skills/` and a same-topic plugin/marketplace skill, prefer the project skill. It encodes this repo's specific workflow and trigger phrasing.

When a skill defines a checklist, apply every item before finishing, never a subset.

This applies in Plan Mode too. Invoking a matching skill is a read-only action, do it directly before any codebase exploration, regardless of the Plan Mode phase you are in.

This applies no matter which skill or command is currently driving the session, `/scope`, `/code`, `/test`, another skill's workflow, or a subagent chain, none of these override or suppress a different skill's coverage.

When writing a plan step or a subagent/delegation prompt for a skill-covered action, name the skill to invoke, never the raw command it wraps. Spelling out the exact CLI flags in a plan or subagent prompt bypasses the skill, because whoever executes that step just runs the literal instruction instead of re-matching triggers. This holds even when the flags already look correct, knowing the flags is exactly what makes it tempting to skip the skill.

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

When writing rules for agents or yourself: pair every prohibition with a concrete "do/don't" example so the boundary is unambiguous.

## Confusion Management

When encountering inconsistencies, conflicting requirements, or unclear specifications: stop, don't proceed with a guess. Name the specific confusion ("I see X in the spec but Y in the existing code"), present the tradeoff or ask the clarifying question, and wait for resolution before continuing.

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

Manage context actively. Long sessions burn tokens because every API call re-sends the full conversation history, a session that runs for days with hundreds of messages will always balloon.

### Compaction Triggers

- Compact after every 2-3 completed subtasks. Do not batch more work into a bloated context.
- Compact after every PR merge or major phase transition.
- Compact before any idle gap longer than 30 minutes. Idle gaps force expensive cache rebuilds on the next turn.
- Never continue a session across calendar days. Start a fresh session instead. The previous session's summary carries forward.
- If the context health warning fires, compact immediately. Do not defer, do not start new work, do not rationalize one more small task first.

### Token-Saving Best Practices

- Use the `explore` subagent for code discovery instead of reading large files directly in the main context. The subagent returns only the answer, not the full file content.
- Read files with `offset`/`limit` when you only need a specific section, not the entire file.
- Prefer `grep`/`glob` over `read` for searching patterns. Read only the matching files/sections.
- Avoid re-reading the same files across turns. Cache findings in your mental model or notes.
- To view a match in context, grep for the line number first, then `Read` that file with `offset`/`limit`. Do not chain `grep`/`sed` into one compound shell command (semicolons, command substitution), it costs the same tool calls, and multi-statement shell strings often fail the harness's read-only auto-approval parser, forcing a manual permission prompt that a plain `grep` or `Read` would have skipped.

### Manual Output Compression

Compression happens at invocation time or in how you carry a result forward, never automatically.

- Shape the command to be selective before running it, not after: `grep -c` for a count, `jq` filters for specific fields, `rg` with `-m`/`-A`/`-B` bounds, `sed -n` ranges, instead of dumping everything and trimming afterward.
- When a result is still large and repetitive, long log dumps, big `JSON` arrays, wide diffs, do not paste it verbatim into your response or carry it forward untouched. Keep only the unique or salient lines, errors, matches, changed lines, and state how many lines were elided.
- Never silently drop information that changes the answer. If you elide repetitive lines, say so and note that the full output is one command away if truly needed.

## Context Anti-Patterns

| Anti-Pattern | Fix |
| --- | --- |
| Agent invents APIs, ignores conventions | Load rules file and relevant source files before each task |
| Agent loses focus with too much context | Include only what is relevant to the current task |
| Agent guesses when it should ask | Surface ambiguity explicitly |
| Agent invents new style instead of following yours | Include one example of the pattern to follow |
| Agent doesn't know project-specific rules | Write it down in rules files, if it's not written, it doesn't exist |
