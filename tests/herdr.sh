#!/bin/bash

# Checks `settings/herdr.sh`: an installer whose checksum does not match
# the pinned one is never run, an installed app is not installed again, every
# pinned mod is copied from a checkout at its pinned commit, also before the app
# is installed, an installed mod folder is never overwritten, and a mod that
# fails `herdr-app check` is reported. Runs with a temporary home and fake
# `curl`, `git` and `herdr-app`, so nothing touches the network or the real
# configuration.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HERDR_APPLICATION_SCRIPT="$TESTS_SCRIPT_DIRECTORY/../settings/herdr.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

export HOME="$TEST_DIRECTORY/home"
unset HERDR_APPLICATION_HOME
MODS_DIRECTORY="$HOME/.config/herdr-app/mods"
FAKE_BINARIES="$TEST_DIRECTORY/bin"
CALLS="$TEST_DIRECTORY/calls"
INSTALLER_RAN="$TEST_DIRECTORY/installer_ran"
mkdir -p "$HOME/.local/bin" "$FAKE_BINARIES"
failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# `clone` makes a checkout holding every mod folder, `checkout` records the commit.
cat >"$FAKE_BINARIES/git" <<'FAKE'
#!/bin/bash
if [ "$1" = "clone" ] && [ -n "$FAIL_CLONE" ] && [[ "$2$3" == *"$FAIL_CLONE"* ]]; then
  exit 128
elif [ "$1" = "clone" ]; then
  for folder in reviewer git-graph space-folders roundup roundup-dry open-vscode; do
    mkdir -p "${!#}/mods/$folder"
    echo '{}' >"${!#}/mods/$folder/mod.json"
  done
elif [ "$1" = "-C" ] && [ "$3" = "checkout" ]; then
  echo "checkout $5" >>"$CALLS"
fi
FAKE

# Serves an installer that is not the reviewed one, it only leaves a mark if run.
cat >"$FAKE_BINARIES/curl" <<'FAKE'
#!/bin/bash
echo "curl" >>"$CALLS"
printf 'touch "%s"\n' "$INSTALLER_RAN" >"${!#}"
FAKE

chmod +x "$FAKE_BINARIES"/*
export CALLS INSTALLER_RAN

run_script() {
  PATH="$FAKE_BINARIES:$PATH" bash "$HERDR_APPLICATION_SCRIPT" 2>&1
}

# A changed installer is refused, and every mod still goes in at its pinned commit, unchecked.
output=$(run_script)
[ -e "$INSTALLER_RAN" ] && fail "an installer with a different checksum was run"
grep -q "installer changed since it was reviewed" <<<"$output" || fail "a changed installer was not reported"
for folder in reviewer git-graph space-folders roundup roundup-dry open-vscode; do
  [ -f "$MODS_DIRECTORY/$folder/mod.json" ] || fail "the '$folder' mod was not copied"
done
for commit in $(grep -oE '\b[0-9a-f]{40}\b' "$HERDR_APPLICATION_SCRIPT"); do
  grep -q "^checkout $commit$" "$CALLS" || fail "a mod was not checked out at its pinned commit $commit"
done
grep -q '^check ' "$CALLS" && fail "a mod was checked without 'herdr-app' installed"
for folder in tmux-prefix worktree-cleanup repository-sync tab-names; do
  [ -f "$MODS_DIRECTORY/$folder/mod.json" ] || fail "the vendored '$folder' mod was not copied"
done

# The app is installed now, a second run neither downloads it nor touches the installed mods.
cat >"$HOME/.local/bin/herdr-app" <<'FAKE'
#!/bin/bash
echo "check $2" >>"$CALLS"
[ -z "$FAIL_CHECK" ] || [ "$(basename "$2")" != "$FAIL_CHECK" ]
FAKE
chmod +x "$HOME/.local/bin/herdr-app"
echo "mine" >"$MODS_DIRECTORY/reviewer/edited"
: >"$CALLS"
run_script >/dev/null
grep -q '^curl' "$CALLS" && fail "an installed app was downloaded again"
[ -f "$MODS_DIRECTORY/reviewer/edited" ] || fail "an installed mod folder was overwritten"
grep -q '^checkout' "$CALLS" && fail "an installed mod was fetched again"

# Installed mods are checked too, and a stale vendored mod is refreshed.
echo "stale" >"$MODS_DIRECTORY/tab-names/mod.json"
: >"$CALLS"
run_script >/dev/null
grep -q "^check .*/reviewer$" "$CALLS" || fail "an installed mod was not checked"
cmp -s "$MODS_DIRECTORY/tab-names/mod.json" "$TESTS_SCRIPT_DIRECTORY/../.config/herdr-app/mods/tab-names/mod.json" || fail "a vendored mod was not refreshed"

# A mod failing its check is reported, the rest still install.
rm -rf "$MODS_DIRECTORY/open-vscode"
: >"$CALLS"
output=$(FAIL_CHECK=open-vscode run_script)
grep -q "'open-vscode' mod fails its check" <<<"$output" || fail "a failing mod check was not reported"

# A repository that cannot be cloned is reported, the other mods still install.
rm -rf "$MODS_DIRECTORY/reviewer" "$MODS_DIRECTORY/git-graph"
output=$(FAIL_CLONE=herdr-reviewer run_script)
grep -q "Could not fetch 'vytasgavelis/herdr-reviewer'" <<<"$output" || fail "a failing clone was not reported"
[ -d "$MODS_DIRECTORY/reviewer" ] && fail "a mod was installed from a failed clone"
[ -f "$MODS_DIRECTORY/git-graph/mod.json" ] || fail "a failing clone stopped the other mods"

[ "$failures" = "0" ] && echo "herdr-application: all checks passed"
exit "$failures"
