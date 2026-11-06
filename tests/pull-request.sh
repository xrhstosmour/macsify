#!/bin/bash

# Checks the rules of the `Herdr` app's `pull-request` mod, described in the header
# of its `main.js`. The rules live in `logic.js`, `pull-request.mjs` runs them, so
# this needs `node`.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not found"
  exit 0
fi

node "$TESTS_SCRIPT_DIRECTORY/pull-request.mjs"
