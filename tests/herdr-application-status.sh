#!/bin/bash

# Checks `.config/agentic/hooks/herdr-application-status.sh`: outside an app terminal it
# writes nothing, inside one each state becomes the right `OSC 7501` escape, a
# permission or question notification is `blocked` and any other notification
# or an unknown state writes nothing, and so does a multiplexer pane. The terminal is a temporary file.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK="$TESTS_SCRIPT_DIRECTORY/../.config/agentic/hooks/herdr-application-status.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

export HERDR_APPLICATION_STATUS_TTY="$TEST_DIRECTORY/terminal"
failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# Prints what the hook wrote for a state and payload, empty when nothing.
written() {
  : >"$HERDR_APPLICATION_STATUS_TTY"
  printf '%s' "$2" | bash "$HOOK" "$1"
  cat "$HERDR_APPLICATION_STATUS_TTY"
}

unset HC_TERMINAL_ID
[ -z "$(written working '{}')" ] || fail "wrote outside an app terminal"

export HC_TERMINAL_ID="t1"
for state in working "done" idle clear; do
  [ "$(written "$state" '{}')" = "$(printf '\033]7501;state=%s:app=claude-code\033\\' "$state")" ] || fail "wrong escape for '$state'"
done

# The multiplexer's own hook reports there, this one stays silent.
[ -z "$(HERDR_ENV=1 written working '{}')" ] || fail "wrote inside a multiplexer pane"

[ "$(written notification '{"notification_type":"permission_prompt"}')" = "$(printf '\033]7501;state=blocked:app=claude-code:kind=permission\033\\')" ] || fail "a permission prompt was not blocked"
[ "$(written notification '{"notification_type":"elicitation_dialog"}')" = "$(printf '\033]7501;state=blocked:app=claude-code:kind=question\033\\')" ] || fail "a question was not blocked"
[ -z "$(written notification '{"notification_type":"idle_prompt"}')" ] || fail "an idle prompt changed the state"
[ -z "$(written notification 'not json')" ] || fail "a broken payload changed the state"
[ -z "$(written bogus '{}')" ] || fail "an unknown state was written"

[ "$failures" = "0" ] && echo "herdr-application-status: all checks passed"
exit "$failures"
