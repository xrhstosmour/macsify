#!/bin/bash

input=$(cat)
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  mtime=$(stat -f%m "$transcript_path" 2>/dev/null || stat -c%Y "$transcript_path" 2>/dev/null)
  now=$(date +%s)
  idle_seconds=$((now - mtime))
  idle_minutes=$((idle_seconds / 60))

  # Matches Claude Code's automatic 1-hour prompt-cache TTL on a subscription
  # (code.claude.com/docs/en/prompt-caching#cache-lifetime). Past this point the
  # cache is already cold, so warn right at the boundary, not an hour after it.
  idle_warn_seconds=3600

  if [ "$idle_seconds" -gt "$idle_warn_seconds" ]; then
    # Context size from the last assistant usage after the latest compaction, 0 when none is found,
    # which is the case for any transcript without a usage field, such as Codex and Copilot.
    tokens=$(tail -n 200 "$transcript_path" | jq -rs '(map(.subtype == "compact_boundary") | rindex(true) // -1) as $boundary | [.[($boundary + 1):][] | .message.usage? | select(.) | ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))] | last // 0' 2>/dev/null)
    tokens=${tokens:-0}

    echo ""
    echo "# Context Health Warning"
    echo ""
    if [ "$tokens" -gt 0 ]; then
      echo "This session has been idle for ~${idle_minutes} minutes, with about $((tokens / 1000))K tokens of context."
    else
      echo "This session has been idle for ~${idle_minutes} minutes."
    fi
    echo "The prompt cache has likely expired, so the next turn rebuilds the full context at full price."
    echo "Finish responding to the user's current request first. Then inform them the session has been idle a while, and advise compacting, handoff, or a new session."
    echo "Do not interrupt the current answer to do this, and do not invoke anything yourself, only inform and advise."
  fi
fi
