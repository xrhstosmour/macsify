#!/bin/bash
# Blocks stray .md file creation, hard-enforcing the "don't create
# documentation files unless explicitly requested" rule that otherwise only
# lives as text in CLAUDE.md. Only guards actual creation, an overwrite of an
# already-existing file is a normal edit, not stray doc creation. Scoped to
# .md, not .txt: .txt covers too many legitimate non-doc files (requirements.txt,
# robots.txt, etc.) for a static extension check to tell apart. Fails open on
# any doubt: a false-positive block on real skill/agent/memory/plan authoring
# is worse than an occasional stray file, so the allowlist below is
# deliberately generous.
input=$(cat)
[ "$(echo "$input" | jq -r '.tool_name // empty')" = "Write" ] || exit 0
path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[ -n "$path" ] || exit 0
echo "$path" | grep -qiE '\.md$' || exit 0
[ -f "$path" ] && exit 0

basename=$(basename "$path")
case "$basename" in
  README.md|CLAUDE.md|AGENTS.md|CODEX.md|CONTRIBUTING.md|SKILL.md)
    exit 0
    ;;
esac

if echo "$path" | grep -qE "(^|/)\.config/agentic/|^${HOME}/\.claude/(agents|commands|plans|skills)/|^${HOME}/\.claude/rules/instructions/|^${HOME}/\.claude/projects/[^/]+/memory/"; then
  exit 0
fi

reason="Unnecessary documentation file creation blocked. Use README.md/CLAUDE.md/AGENTS.md for docs instead, per CLAUDE.md's file-creation rule."
jq -n --arg reason "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
