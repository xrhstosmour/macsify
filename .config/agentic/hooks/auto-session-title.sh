#!/bin/bash
# Auto-generates a short, content-aware session title once a session has enough
# signal to summarize, using Haiku (cheap, fast) via a headless `claude -p` call.
# Writes a `custom-title` transcript line, the exact format Claude Code itself
# writes for `/rename` (reverse-engineered from the shipped binary's `{type:
# "custom-title", customTitle, sessionId, uuid, timestamp}` object literal), so
# both claude-hud's statusline and Claude Code's own `/resume` picker pick it up.
# Never overwrites a manual `/rename`. Runs the actual generation in the
# background so it never adds latency to the triggering turn.

input=$(cat)
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')

[ -n "$transcript_path" ] && [ -f "$transcript_path" ] && [ -n "$session_id" ] || exit 0

# Already named, by us before or by a manual /rename, never overwrite.
grep -q '"type":"custom-title"' "$transcript_path" 2>/dev/null && exit 0

# Wait for enough signal that a summary is meaningful (skip a bare "hi").
# Counts only turns with real text content, tool-result echoes also carry
# `"role":"user"` in the transcript and would otherwise satisfy this after
# the very first turn.
user_message_count=$(jq -rs '
  [.[] | select(.type == "user") | .message.content |
    (if type == "string" then . elif type == "array" then (map(select(.type == "text") | .text) | first // "") else "" end)
  ] | map(select(length > 0)) | length
' "$transcript_path" 2>/dev/null || echo 0)
[ "${user_message_count:-0}" -ge 2 ] || exit 0

# Find the first substantive user message: skip system-injected/command-wrapped
# content and skip trivial exit-type turns ("exit", "bye", "ok") so a session
# that's just the user leaving, or has no real content yet, isn't named and
# isn't locked out of retrying once real content does show up.
first_message=$(jq -rs '
  [.[] | select(.type == "user") | .message.content |
    (if type == "string" then . elif type == "array" then (map(select(.type == "text") | .text) | first // "") else "" end)
  ] | map(select(length > 3 and (startswith("<") | not))) |
  map(select(
    (gsub("^[[:space:]]+|[[:space:]]+$|[.!?]+$"; "") | ascii_downcase) as $s |
    (["exit","quit","bye","goodbye","stop","cancel","nevermind","never mind",
      "ok","okay","no","yes","yeah","yep","nope","thanks","thank you",
      "hi","hello","hey","test","testing"] | index($s)) | not
  )) |
  first // empty
' "$transcript_path" 2>/dev/null | head -c 800)

[ -n "$first_message" ] || exit 0

# Claim a lock only once there's real content worth summarizing, so an
# empty/trivial-only session can still pick up a title from a later message
# instead of being locked out permanently.
lock="${TMPDIR:-/tmp}/agentic-auto-session-title-${session_id}"
mkdir "$lock" 2>/dev/null || exit 0

nohup bash -c '
  first_message="$1"
  session_id="$2"
  transcript_path="$3"

  title=$(claude -p --model haiku --no-session-persistence \
    "Summarize this coding-session request as a 3-5 word kebab-case slug: lowercase, hyphen-separated, no punctuation, no quotes, output nothing but the slug itself. Request: $first_message" \
    2>/dev/null | tr -d "\"" | tr -c "a-z0-9-" "-" | sed -E "s/-+/-/g; s/^-//; s/-$//" | cut -c1-60)

  [ -n "$title" ] || exit 0

  uuid=$(uuidgen | tr "A-Z" "a-z")
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  jq -nc --arg sid "$session_id" --arg title "$title" --arg uuid "$uuid" --arg ts "$timestamp" \
    "{type: \"custom-title\", sessionId: \$sid, customTitle: \$title, uuid: \$uuid, timestamp: \$ts}" \
    >> "$transcript_path"
' _ "$first_message" "$session_id" "$transcript_path" >/dev/null 2>&1 &
disown

exit 0
