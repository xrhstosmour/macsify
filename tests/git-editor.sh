#!/bin/bash

# Checks which editor `.config/scripts/git/editor.sh` hands the file to: `VS Code`
# with `--wait` only while it runs and its `code` command exists, `hx` otherwise,
# `vi` when `hx` is missing too. Stub commands on a temporary `PATH` log their
# arguments, no real editor starts.

set -e

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EDITOR_SCRIPT="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/git/editor.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# Runs the editor script with only the given stubs, plus `bash` and `env` it
# needs to start, on the `PATH`, and prints what the chosen stub was called with.
# `pgrep` exits with the given status, so the `VS Code` check is decided here.
# Usage:
#   run_editor <pgrep exit status> <stub>...
run_editor() {
  local status="$1" stubs="$TEST_DIRECTORY/bin" stub
  shift
  rm -rf "$stubs" "$TEST_DIRECTORY/called"
  mkdir -p "$stubs"
  ln -s "$(command -v bash)" "$stubs/bash"
  ln -s "$(command -v env)" "$stubs/env"
  printf '#!/bin/sh\nexit %s\n' "$status" >"$stubs/pgrep"
  for stub in "$@"; do
    printf '#!/bin/sh\necho "%s $*" >"%s/called"\n' "$stub" "$TEST_DIRECTORY" >"$stubs/$stub"
  done
  chmod +x "$stubs"/*
  PATH="$stubs" "$stubs/bash" "$EDITOR_SCRIPT" todo || true
  cat "$TEST_DIRECTORY/called" 2>/dev/null
}

[ "$(run_editor 0 code hx vi)" = "code --wait todo" ] || fail "a running VS Code did not get the file"
[ "$(run_editor 1 code hx vi)" = "hx todo" ] || fail "a closed VS Code did not fall back to hx"
[ "$(run_editor 0 hx vi)" = "hx todo" ] || fail "a running VS Code without its code command did not fall back to hx"
[ "$(run_editor 1 vi)" = "vi todo" ] || fail "a machine without hx did not fall back to vi"

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: git-editor"
