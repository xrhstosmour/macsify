#!/bin/bash

# Checks how `profile_resolve` picks the work or personal profile: the
# environment wins and is saved, a saved profile is reused, an unknown value
# fails without overwriting the saved one, and with no terminal it falls back to
# `personal` without saving it. Then checks that `brewfile_declares` sees only the
# base and the active profile's Brewfile. Runs against a temporary profile file and
# temporary Brewfiles, never the real ones.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROFILE_HELPER="$TESTS_SCRIPT_DIRECTORY/../helpers/profile.sh"
BREWFILE_HELPER="$TESTS_SCRIPT_DIRECTORY/../helpers/brewfile.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

export PROFILE_FILE_PATH="$TEST_DIRECTORY/macsify/profile"
failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# Prints the resolved profile, or `error` when resolution fails. Standard input
# is not a terminal, so the prompt is never reached.
resolve() {
  (
    # shellcheck disable=SC1090
    source "$PROFILE_HELPER"
    profile_resolve 2>/dev/null || { echo error; exit 0; }
    echo "$MACSIFY_PROFILE"
  ) </dev/null
}

saved_profile() {
  cat "$PROFILE_FILE_PATH" 2>/dev/null
}

# No environment value and no saved file, nobody to ask.
unset MACSIFY_PROFILE
rm -f "$PROFILE_FILE_PATH"
[ "$(resolve)" = "personal" ] || fail "no profile and no terminal did not fall back to personal"
[ ! -f "$PROFILE_FILE_PATH" ] || fail "the fallback profile was saved, a later run would not ask"

# The environment wins over the saved file and replaces it.
mkdir -p "$(dirname "$PROFILE_FILE_PATH")"
echo personal >"$PROFILE_FILE_PATH"
[ "$(MACSIFY_PROFILE=work resolve)" = "work" ] || fail "MACSIFY_PROFILE=work was not used"
[ "$(saved_profile)" = "work" ] || fail "MACSIFY_PROFILE=work was not saved"

# A saved profile is reused without the environment.
[ "$(resolve)" = "work" ] || fail "the saved work profile was not reused"

# An unknown value fails and leaves the saved profile alone.
[ "$(MACSIFY_PROFILE=home resolve)" = "error" ] || fail "an unknown profile did not fail"
[ "$(saved_profile)" = "work" ] || fail "an unknown profile overwrote the saved one"

# `brewfile_declares` reads `base.Brewfile` and the active profile's Brewfile, never another profile's.
export BREWFILE_DIRECTORY="$TEST_DIRECTORY/packages"
mkdir -p "$BREWFILE_DIRECTORY"
echo "cask 'wezterm'" >"$BREWFILE_DIRECTORY/base.Brewfile"
echo "cask 'flutter'" >"$BREWFILE_DIRECTORY/personal.Brewfile"
echo "# cask 'datagrip'" >"$BREWFILE_DIRECTORY/work.Brewfile"

# Prints `yes` when the given profile declares the package, `no` otherwise.
declares() {
  (
    # shellcheck disable=SC1090
    source "$BREWFILE_HELPER"
    MACSIFY_PROFILE="$1" brewfile_declares "$2" && echo yes || echo no
  )
}

[ "$(declares work wezterm)" = "yes" ] || fail "a base package was not declared for work"
[ "$(declares personal flutter)" = "yes" ] || fail "a personal package was not declared for personal"
[ "$(declares work flutter)" = "no" ] || fail "a personal package was declared for work"
[ "$(declares work datagrip)" = "no" ] || fail "a commented package was declared"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "PASS: profile resolution and Brewfile selection"
