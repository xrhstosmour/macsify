#!/bin/bash

# Checks `.config/agentic/hooks/herdr-application-title.sh`: an automatic tab and
# space take the session title (cut to fit, tab color kept), a tab or space renamed
# by hand is kept, a rename after the hook's own is kept too, and nothing happens
# outside an app terminal or without a title. `herdr-app` is stubbed.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK="$TESTS_SCRIPT_DIRECTORY/../.config/agentic/hooks/herdr-application-title.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

export TMPDIR="$TEST_DIRECTORY"
export PATH="$TEST_DIRECTORY/bin:$PATH"
export HC_TERMINAL_ID="t1"
failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# The stub answers `ls` from `$APP_LS` and records every `do` call.
mkdir -p "$TEST_DIRECTORY/bin"
cat >"$TEST_DIRECTORY/bin/herdr-app" <<'STUB'
#!/bin/bash
if [ "$1" = "ls" ]; then cat "$APP_LS"; else echo "$*" >>"$APP_CALLS"; fi
STUB
chmod +x "$TEST_DIRECTORY/bin/herdr-app"
export APP_LS="$TEST_DIRECTORY/ls.json"
export APP_CALLS="$TEST_DIRECTORY/calls"

transcript="$TEST_DIRECTORY/transcript.jsonl"
payload="{\"transcript_path\":\"$transcript\"}"

# Usage: set_app <space name> <named> <tab name>
set_app() {
  printf '{"spaces":[{"id":"sp1","name":"%s","named":%s,"tabs":[{"id":"tb1","name":"%s","terminals":[{"terminal":"t1"}]}]}]}' "$1" "$2" "$3" >"$APP_LS"
}

run_hook() {
  : >"$APP_CALLS"
  printf '%s' "$payload" | bash "$HOOK"
}

set_app "enhancements" null "macsify · Claude Code"

# No title yet, nothing happens.
echo '{"type":"user"}' >"$transcript"
run_hook
[ ! -s "$APP_CALLS" ] || fail "renamed without a session title"

echo '{"type":"custom-title","customTitle":"syncthing-hardening"}' >>"$transcript"
run_hook
grep -q 'tab.rename --id tb1 --name syncthing-hardening' "$APP_CALLS" || fail "automatic tab was not renamed"
grep -q 'space.rename --id sp1 --name syncthing-hardening' "$APP_CALLS" || fail "automatic space was not renamed"

# Same title again, already applied, no new calls.
set_app "syncthing-hardening" true "syncthing-hardening"
run_hook
[ ! -s "$APP_CALLS" ] || fail "renamed again with the same title"

# A new title replaces the one the hook set.
echo '{"type":"custom-title","customTitle":"a-much-longer-session-title-than-fits"}' >>"$transcript"
run_hook
grep -q -- '--name a-much-longer-session-title…' "$APP_CALLS" || fail "long title was not cut to fit"

# A hand rename of the tab is kept, the space still follows.
set_app "a-much-longer-session-title…" true "my own tab"
echo '{"type":"custom-title","customTitle":"third-title"}' >>"$transcript"
run_hook
grep -q 'tab.rename' "$APP_CALLS" && fail "a tab renamed by hand was overwritten"
grep -q 'space.rename --id sp1 --name third-title' "$APP_CALLS" || fail "space did not follow the title"

# A space named by hand, never set by this hook, is kept, the color is kept on the tab.
rm -f "$TEST_DIRECTORY"/herdr-application-title-*
set_app "enhancements" true "🟢 macsify · Claude Code"
run_hook
grep -q -- '--name 🟢 third-title' "$APP_CALLS" || fail "tab color was lost"
grep -q 'space.rename' "$APP_CALLS" && fail "a space named by hand was overwritten"

# Outside an app terminal nothing happens.
unset HC_TERMINAL_ID
rm -f "$TEST_DIRECTORY"/herdr-application-title-*
set_app "enhancements" null "macsify · Claude Code"
run_hook
[ ! -s "$APP_CALLS" ] || fail "renamed outside an app terminal"

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: Herdr application title hook"
