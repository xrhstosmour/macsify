#!/bin/bash

# Checks the naming rules of the `Herdr` app's `tab-names` mod: an unnamed tab
# is named `folder · program`, a tab the person renamed is left alone, and a
# color prefix survives renames. The rules live in `logic.js`, `tab-names.mjs`
# runs them, so this needs `node`.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not found"
  exit 0
fi

node "$TESTS_SCRIPT_DIRECTORY/tab-names.mjs"
