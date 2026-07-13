#!/bin/bash

cat ~/.config/agentic/hooks/reminders.md

input=$(cat)
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  size_bytes=$(stat -f%z "$transcript_path")
  mtime=$(stat -f%m "$transcript_path")
  now=$(date +%s)
  idle_seconds=$((now - mtime))
  idle_minutes=$((idle_seconds / 60))
  estimated_tokens=$((size_bytes / 17))

  size_warn_bytes=850000
  idle_warn_seconds=1800

  if [ "$size_bytes" -gt "$size_warn_bytes" ] || [ "$idle_seconds" -gt "$idle_warn_seconds" ]; then
    size_megabytes=$((size_bytes / 1024 / 1024))
    echo ""
    echo "# Context Health Warning"
    echo ""
    echo "This session's transcript is ~${size_megabytes}MB (~${estimated_tokens} estimated tokens), last active ${idle_minutes} minutes ago."
    echo "Long idle gaps on large contexts force an expensive full cache rebuild on the next turn."
    echo "Tell the user their context is large or stale. They MUST compact now or start a fresh session. Do not defer."
  fi
fi
