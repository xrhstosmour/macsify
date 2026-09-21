#!/bin/bash

# Caps runaway Bash stdout+stderr, since PreToolUse is the only hook stage
# that can affect a tool call at all (via updatedInput), and only before
# execution. PostToolUse cannot rewrite or truncate a tool's result
# (code.claude.com/docs/en/hooks).
#
# Redirects the command's combined output to a temp file instead of piping
# it through `head` directly:
#   - `cmd | head` runs `cmd` as the left side of a pipeline, which bash
#     always executes in a subshell, so `cd`/`export`/`source` inside `cmd`
#     would silently stop persisting to the next Bash call, Claude Code's
#     Bash tool keeps the working directory across calls.
#   - Once `head -c N` has its bytes it exits, and the producer gets
#     SIGPIPE on its next write and dies mid-run, aborting anything with
#     side effects (an install, a build, a migration) that also logs past
#     the cap.
#   - Without `pipefail`, the pipeline's exit status is `head`'s, not the
#     wrapped command's, so a failing command would report success.
# `{ cmd ; } > file 2>&1` avoids all three: it's a brace group, not a
# subshell, so state-changing commands still take effect; nothing reads
# concurrently, so there's no SIGPIPE; and the real exit status is captured
# immediately after the group runs, before truncation happens.

max_bytes=20000

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

if [ -z "$command" ]; then
  exit 0
fi

# Multi-line commands (heredocs, or one with a trailing `#` comment) can't
# be safely wrapped by string concatenation, appending anything after a
# heredoc delimiter or a comment marker breaks or silently swallows it.
case "$command" in
  *$'\n'*|*"#"*)
    exit 0
    ;;
esac

# Already bounded, redirected, backgrounded, or interactive, leave untouched.
case "$command" in
  *"| head"*|*"| tail"*|*"| less"*|*"| wc"*|*"|head"*|*"|tail"*|*"|less"*|*"|wc"*)
    exit 0
    ;;
  *">"*|*"&"|*"| fzf"*|*"|fzf"*)
    exit 0
    ;;
esac

# Commands where the user explicitly wants the full, unbroken output.
case "$command" in
  git\ diff*|git\ log*|git\ show*|git\ blame*|diff\ *|cat\ *)
    exit 0
    ;;
esac

# Never rewrite anything this repo's own settings.json treats as dangerous.
# Some of its deny/ask patterns are anchored to the end of the original
# command (e.g. `git push *--force* main`), and appending our wrapper's
# suffix would defeat that anchor, letting a rewritten command slip past
# the permission check it was supposed to hit.
case "$command" in
  *"sudo "*|*"dd "*|*"mkfs"*|*"git push"*|*"git filter-branch"*|*"git reset --hard"*|*"git clean -f"*|*"git branch -D"*|*"gh pr merge"*)
    exit 0
    ;;
esac

capture_file="${TMPDIR:-/tmp}/bash-output-cap.$$"
wrapped_command="{ $command ; } > '$capture_file' 2>&1; __bash_output_cap_exit=\$?; head -c $max_bytes '$capture_file'; rm -f '$capture_file'; exit \$__bash_output_cap_exit"

# No permissionDecision: the rewritten command still goes through Claude
# Code's normal permission flow (allow/deny/ask rules, the interactive
# prompt), only the input changes here. Returning "allow" would bypass all
# of that for every command this hook rewrites.
jq -n --arg cmd "$wrapped_command" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: { command: $cmd }
  }
}'
