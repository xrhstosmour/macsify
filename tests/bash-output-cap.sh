#!/bin/bash

# Checks that the command `bash-output-cap.sh` rewrites runs exactly like the
# original, same output and same exit status, including a trailing `;` that
# used to turn the wrapper into a syntax error. Then that output past the cap
# keeps its first and last halves around an elision line, and that the
# commands `claude/settings.json` denies or asks about are never rewritten, a
# wrapper would defeat their end-anchored patterns, and that nothing is
# rewritten in auto mode, whose classifier denies a rewritten call.

set -e

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK_SCRIPT="$TESTS_SCRIPT_DIRECTORY/../.config/agentic/hooks/bash-output-cap.sh"

failures=0

# Usage:
#   rewrite <command>, prints the rewritten command, empty when left untouched
rewrite() {
  jq -n --arg command "$1" '{tool_input: {command: $command}}' | bash "$HOOK_SCRIPT" | jq -r '.hookSpecificOutput.updatedInput.command // empty'
}

for command in 'echo hello' 'echo hello;' 'echo hello ;  ' 'false && echo no;' '(cd /tmp; pwd)' 'sh -c "exit 3"' 'echo before; exit 2' 'find /tmp -maxdepth 0 -exec echo {} \;'; do
  rewritten=$(rewrite "$command")
  # The hook leaves a command it does not wrap untouched.
  [ -n "$rewritten" ] || rewritten="$command"

  expected_output=$(bash -c "$command" 2>&1) && expected_status=0 || expected_status=$?
  actual_output=$(bash -c "$rewritten" 2>&1) && actual_status=0 || actual_status=$?

  if [ "$expected_output" != "$actual_output" ] || [ "$expected_status" != "$actual_status" ]; then
    echo "FAIL: '$command' expected status $expected_status and '$expected_output', got status $actual_status and '$actual_output'"
    failures=$((failures + 1))
  fi
done

long_command="printf 'x%.0s' \$(seq 24997); printf END"
rewritten=$(rewrite "$long_command")
if [ -z "$rewritten" ]; then
  echo "FAIL: command printing 25000 bytes was not wrapped"
  failures=$((failures + 1))
else
  output=$(bash -c "$rewritten")
  capture_file=$(printf '%s\n' "$output" | sed -n 's/^\[5000 bytes elided, full output in \(.*\)\]$/\1/p')
  expected="$(printf 'x%.0s' $(seq 10000))
[5000 bytes elided, full output in $capture_file]
$(printf 'x%.0s' $(seq 9997))END"
  if [ -z "$capture_file" ] || [ "$output" != "$expected" ]; then
    echo "FAIL: command printing 25000 bytes did not keep the first and last 10000 bytes around an elision line naming the capture file"
    failures=$((failures + 1))
  elif [ "$(wc -c < "$capture_file" | tr -d ' ')" != 25000 ]; then
    echo "FAIL: the capture file named in the elision line does not hold the full 25000 bytes"
    failures=$((failures + 1))
  fi
  rm -f "$capture_file"
fi

for command in 'git push --force origin main' 'git push origin main' 'git branch -D feature/example' 'git reset --hard HEAD' 'git clean -fd' 'git checkout .' 'git restore .' 'gh pr merge 1' 'sudo ls' 'dd if=/dev/zero of=file'; do
  rewritten=$(rewrite "$command")
  if [ -n "$rewritten" ]; then
    echo "FAIL: '$command' was rewritten, its deny or ask pattern would no longer match"
    failures=$((failures + 1))
  fi
done

auto_mode_output=$(jq -n '{permission_mode: "auto", tool_input: {command: "echo hello"}}' | bash "$HOOK_SCRIPT")
if [ -n "$auto_mode_output" ]; then
  echo "FAIL: 'echo hello' was rewritten in auto mode, the classifier would deny it with no verdict"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: bash-output-cap"
