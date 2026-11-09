#!/bin/bash

# Checks the `Herdr` app's `worktree-cleanup` mod: a merged, clean worktree and
# its branch are removed, and one that is unmerged, dirty, untracked, detached on
# an unmerged commit, mid-rebase, protected or the main checkout is kept. The
# decisions live in `logic.js`, `worktree-cleanup-application.mjs` runs them
# against real temporary `git` repositories, so this needs `node` and `git`.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not found"
  exit 0
fi

node "$TESTS_SCRIPT_DIRECTORY/worktree-cleanup-application.mjs"
