#!/bin/bash

# Checks that `auto-session-title.sh` stops rescanning a transcript whose answer
# can no longer change: one already named, and one past the 500 KB window it
# reads with no message worth a title. A short trivial session must stay open,
# a later message can still name it, and so must one whose title call failed.
# Runs against temporary transcripts with a stub `claude`, never the real one.

set -e

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK_SCRIPT="$TESTS_SCRIPT_DIRECTORY/../.config/agentic/hooks/auto-session-title.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT
export TMPDIR="$TEST_DIRECTORY"

failures=0

# Usage:
#   run_hook <session ID> <transcript path>, prints `locked` or `open`
run_hook() {
  jq -n --arg session "$1" --arg transcript "$2" '{session_id: $session, transcript_path: $transcript}' | bash "$HOOK_SCRIPT"
  if [ -d "$TEST_DIRECTORY/agentic-auto-session-title-$1" ]; then
    echo locked
  else
    echo open
  fi
}

# Usage:
#   expect <session ID> <transcript path> <locked or open> <message>
expect() {
  if [ "$(run_hook "$1" "$2")" != "$3" ]; then
    echo "FAIL: $4"
    failures=$((failures + 1))
  fi
}

trivial_line='{"type":"user","message":{"content":"ok"}}'

renamed="$TEST_DIRECTORY/renamed.jsonl"
printf '%s\n{"type":"custom-title","customTitle":"manual-name"}\n' "$trivial_line" >"$renamed"
expect renamed "$renamed" locked "a renamed session was not locked, every prompt rescans it"

short="$TEST_DIRECTORY/short.jsonl"
printf '%s\n%s\n' "$trivial_line" "$trivial_line" >"$short"
expect short "$short" open "a short trivial session was locked, a later message could not name it"

long="$TEST_DIRECTORY/long.jsonl"
for _ in $(seq 15000); do
  printf '%s\n' "$trivial_line"
done >"$long"
expect long "$long" locked "a trivial transcript past the read window was not locked, every prompt reparses it"

# A `claude` call that returns no title releases the lock, so the next prompt
# tries again, until the third failure keeps it. The stub stands in for a
# failed call and counts its calls.
mkdir "$TEST_DIRECTORY/bin"
calls="$TEST_DIRECTORY/claude-calls"
printf '#!/bin/bash\necho call >>"%s"\nexit 1\n' "$calls" >"$TEST_DIRECTORY/bin/claude"
chmod +x "$TEST_DIRECTORY/bin/claude"
failed="$TEST_DIRECTORY/failed.jsonl"
failed_lock="$TEST_DIRECTORY/agentic-auto-session-title-failed"
printf '%s\n%s\n' '{"type":"user","message":{"content":"Fix the login redirect loop"}}' '{"type":"user","message":{"content":"It happens after logout"}}' >"$failed"

# Usage:
#   prompt_failed_session, runs the hook and waits for its background call to finish
prompt_failed_session() {
  jq -n --arg transcript "$failed" '{session_id: "failed", transcript_path: $transcript}' | PATH="$TEST_DIRECTORY/bin:$PATH" bash "$HOOK_SCRIPT"
  for _ in $(seq 50); do
    [ -d "$failed_lock" ] || break
    [ "$(cat "$failed_lock.attempts" 2>/dev/null)" = 2 ] && [ "$(wc -l <"$calls" 2>/dev/null | tr -d ' ')" = 3 ] && break
    sleep 0.1
  done
  sleep 0.2
}

prompt_failed_session
if [ "$(wc -l <"$calls" | tr -d ' ')" != 1 ] || [ -d "$failed_lock" ]; then
  echo "FAIL: a failed title call kept the lock, the session is never titled"
  failures=$((failures + 1))
fi
prompt_failed_session
prompt_failed_session
prompt_failed_session
if [ "$(wc -l <"$calls" | tr -d ' ')" != 3 ] || [ ! -d "$failed_lock" ]; then
  echo "FAIL: title calls kept failing past three tries, got $(wc -l <"$calls" | tr -d ' ') calls"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: auto-session-title"
