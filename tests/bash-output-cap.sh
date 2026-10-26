#!/bin/bash

# Checks that the command `bash-output-cap.sh` rewrites runs exactly like the
# original, same output and same exit status, including a trailing `;` that
# used to turn the wrapper into a syntax error.

set -e

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK_SCRIPT="$TESTS_SCRIPT_DIRECTORY/../.config/agentic/hooks/bash-output-cap.sh"

failures=0

for command in 'echo hello' 'echo hello;' 'echo hello ;  ' 'false && echo no;' '(cd /tmp; pwd)' 'sh -c "exit 3"' 'echo before; exit 2' 'find /tmp -maxdepth 0 -exec echo {} \;'; do
  rewritten=$(jq -n --arg command "$command" '{tool_input: {command: $command}}' | bash "$HOOK_SCRIPT" | jq -r '.hookSpecificOutput.updatedInput.command // empty')
  # The hook leaves a command it does not wrap untouched.
  [ -n "$rewritten" ] || rewritten="$command"

  expected_output=$(bash -c "$command" 2>&1) && expected_status=0 || expected_status=$?
  actual_output=$(bash -c "$rewritten" 2>&1) && actual_status=0 || actual_status=$?

  if [ "$expected_output" != "$actual_output" ] || [ "$expected_status" != "$actual_status" ]; then
    echo "FAIL: '$command' expected status $expected_status and '$expected_output', got status $actual_status and '$actual_output'"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: bash-output-cap"
