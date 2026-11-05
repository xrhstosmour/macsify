#!/bin/bash

# Checks that the permission rules in `claude/settings.json` keep the entries the
# rest of the setup relies on. It reads the file only, it does not run Claude
# Code's matcher, so it catches a rule being deleted or widened, not one that
# is written wrong.

set -e

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SETTINGS_FILE="$TESTS_SCRIPT_DIRECTORY/../claude/settings.json"

failures=0

# Usage:
#   expect_rule <deny|ask|allow> <rule> <present|absent>
expect_rule() {
  local list="$1" rule="$2" expected="$3" actual="absent"
  if jq -e --arg list "$list" --arg rule "$rule" '.permissions[$list] | index($rule) != null' "$SETTINGS_FILE" >/dev/null; then
    actual="present"
  fi
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: '$rule' in permissions.$list should be $expected"
    failures=$((failures + 1))
  fi
}

expect_rule deny 'Bash(sudo *)' present
expect_rule deny 'Bash(git push *--force* main)' present
expect_rule deny 'Bash(git push --mirror *)' present
expect_rule ask 'Bash(git branch -D *)' present
expect_rule ask 'Bash(git reset --hard *)' present
# The force-with-lease allow only holds while these ask rules cover the other spellings of the default branch.
expect_rule ask 'Bash(git push*+*main*)' present
expect_rule ask 'Bash(git push*refs/heads/main*)' present
# Port scanning is not something to allow unprompted.
expect_rule allow 'Bash(nc -z *)' absent

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: claude-settings"
