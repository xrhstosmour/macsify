#!/bin/bash

# Checks `agent-slots.sh`, the slots both watcher dispatchers take for their
# background agents. Each watcher gets at most three, both together at most
# four, a pull request with a running agent of a watcher gets no second one, a
# slot left over from a dead agent is free again after two hours, parallel
# takes never hand out one slot twice, and a bad argument is rejected.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SLOTS="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/agent-slots.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

failures=0
fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

export XDG_CACHE_HOME="$TEST_DIRECTORY/cache"
STATE="$XDG_CACHE_HOME/watcher-agents"

[ "$("$SLOTS" take green acme/app#1)" = 1 ] || fail "the first green agent did not get slot 1"
"$SLOTS" take green acme/app#1 >/dev/null
[ $? = 4 ] || fail "a second agent of one pull request was not held"
[ "$("$SLOTS" take review acme/app#1)" = 1 ] || fail "the review watcher was held by an agent of the green watcher"
[ "$("$SLOTS" take green acme/app#2)" = 2 ] || fail "the second green agent did not get slot 2"
[ "$("$SLOTS" take green acme/app#3)" = 3 ] || fail "the third green agent did not get slot 3"
"$SLOTS" take review acme/app#4 >/dev/null
[ $? = 3 ] || fail "a fifth agent was started"

"$SLOTS" free green 2
[ "$("$SLOTS" take review acme/app#4)" = 2 ] || fail "a freed slot was not taken again"
"$SLOTS" take green acme/app#5 >/dev/null
[ $? = 3 ] || fail "a fifth agent was started after a free"

"$SLOTS" reset green
[ ! -e "$STATE/green-1" ] && [ ! -e "$STATE/green-3" ] || fail "a reset left a slot of the watcher taken"
[ -e "$STATE/review-1" ] || fail "a reset freed a slot of the other watcher"
"$SLOTS" reset review

# Three of one watcher leave the fourth agent to the other.
for number in 1 2 3; do
  "$SLOTS" take review "acme/app#$number" >/dev/null
done
"$SLOTS" take review acme/app#4 >/dev/null
[ $? = 3 ] || fail "a watcher got a fourth slot"
[ "$("$SLOTS" take green acme/app#4)" = 1 ] || fail "the other watcher did not get the fourth agent"
"$SLOTS" reset review
"$SLOTS" reset green

# A slot taken more than two hours ago belongs to an agent that died without freeing it.
echo "$(($(date +%s) - 7300)) acme/app#1" >"$STATE/green-1"
[ "$("$SLOTS" take green acme/app#1)" = 1 ] || fail "a slot of a dead agent was never freed"
"$SLOTS" reset green

# Takes at the same moment never share a slot, nor go past the cap.
for number in 1 2 3 4 5 6; do
  "$SLOTS" take green "acme/app#$number" >"$TEST_DIRECTORY/take-$number" 2>&1 &
done
wait
[ "$(cat "$TEST_DIRECTORY"/take-* | sort | tr '\n' ' ')" = "1 2 3 " ] || fail "parallel takes handed out $(cat "$TEST_DIRECTORY"/take-* | tr '\n' ' ')"
"$SLOTS" reset green

# The lock is held while the slots are read and written.
mkdir "$STATE/slots.lock"
REVIEW_LOCK_ATTEMPTS=1 "$SLOTS" take green acme/app#1 >/dev/null 2>&1 && fail "a slot was taken while another run held the lock"
rmdir "$STATE/slots.lock"
"$SLOTS" take green acme/app#1 >/dev/null
[ ! -e "$STATE/slots.lock" ] || fail "a take kept the lock"

for arguments in "take other acme/app#1" "take green acme/app" "take green acme/app#x" "take green ../x#1" "free green 4" "free green ../x" "reset" "take green acme/app#1 extra"; do
  # shellcheck disable=SC2086
  "$SLOTS" $arguments >/dev/null 2>&1
  [ $? = 2 ] || fail "agent-slots.sh accepted $arguments"
done
[ "$(find "$STATE" -type f | wc -l | tr -d ' ')" = 1 ] || fail "a rejected argument wrote a file"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "PASS: agent slots script"
