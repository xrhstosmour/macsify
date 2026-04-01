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

## Model Selection

- Start using free models, upgrade to premium only when needed and approved by user.

## Self-Critique

After implementing code, pause and self-critique:

1. Re-read your work.
2. Question your approach: "Did I do this right? Is there a better way?".
3. If concerns arise, fix them before moving on.
4. Max 3 iterations, then ask user for help.
5. If you realize you made a mistake or ignored a rule, acknowledge it immediately, revert, and explain.

## Verification Before Code

Before writing any code:

- Confirm you understand the requirement (ask if unsure).
- Verify the file you need to edit exists and is the right one.
- Check for existing patterns in the codebase.
- Run lint/typecheck early to establish baseline.

After writing code:

- Run lint/typecheck to catch style issues immediately.
- Run relevant tests before moving on.
- Review changes with `git diff` before presenting.

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

## Debugging

When investigating issues:

1. Reproduce the issue first (if possible).
2. Isolate the cause by narrowing scope.
3. Check logs, error messages, and stack traces.
4. Look for recent changes that could have caused it.
5. Test hypothesis before proposing fix.
