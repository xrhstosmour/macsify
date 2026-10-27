#!/bin/bash

# Checks that `auto-session-title.sh` stops rescanning a transcript whose answer
# can no longer change: one already named, and one past the 500 KB window it
# reads with no message worth a title. A short trivial session must stay open,
# a later message can still name it. Runs against temporary transcripts, never
# calls `claude`.

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

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: auto-session-title"
