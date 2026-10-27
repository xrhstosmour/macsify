#!/bin/bash

# Checks that the command `bash-output-cap.sh` rewrites runs exactly like the
# original, same output and same exit status, including a trailing `;` that
# used to turn the wrapper into a syntax error. Then that output past the cap is
# cut to it, and that the commands `claude/settings.json` denies or asks about
# are never rewritten, a wrapper would defeat their end-anchored patterns.

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

long_command="printf 'x%.0s' \$(seq 25000)"
rewritten=$(rewrite "$long_command")
if [ -z "$rewritten" ]; then
  echo "FAIL: command printing 25000 bytes was not wrapped"
  failures=$((failures + 1))
else
  output_bytes=$(bash -c "$rewritten" | wc -c | tr -d ' ')
  if [ "$output_bytes" -ne 20000 ]; then
    echo "FAIL: command printing 25000 bytes gave $output_bytes bytes, expected the 20000-byte cap"
    failures=$((failures + 1))
  fi
fi

for command in 'git push --force origin main' 'git push origin main' 'git branch -D feature/example' 'git reset --hard HEAD' 'git clean -fd' 'git checkout .' 'git restore .' 'gh pr merge 1' 'sudo ls' 'dd if=/dev/zero of=file'; do
  rewritten=$(rewrite "$command")
  if [ -n "$rewritten" ]; then
    echo "FAIL: '$command' was rewritten, its deny or ask pattern would no longer match"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: bash-output-cap"
