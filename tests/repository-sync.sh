#!/bin/bash

# Checks that `repo-sync.sh` fast-forwards a `main` checkout that is behind
# origin, leaves a feature branch and a checkout with uncommitted changes alone,
# and aborts a conflicting rebase with the checkout restored. Runs against a
# temporary `HOME` and local repositories, never touches real checkouts.

set -e

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Overridable so the test can be pointed at an older copy of the script.
REPO_SYNC_SCRIPT="${REPO_SYNC_SCRIPT:-$TESTS_SCRIPT_DIRECTORY/../.config/herdr-repo-sync/repo-sync.sh}"

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

export HOME="$TEST_HOME"
export XDG_CACHE_HOME="$TEST_HOME/.cache"
export GIT_CONFIG_GLOBAL="$TEST_HOME/.gitconfig"
git config --global user.name tester
git config --global user.email tester@example.invalid
git config --global init.defaultBranch main

origin="$TEST_HOME/origin.git"
seed="$TEST_HOME/seed"
git init --quiet --bare "$origin"
git init --quiet "$seed"
echo 'first' >"$seed/file.txt"
git -C "$seed" add file.txt
git -C "$seed" commit --quiet -m 'Initial commit'
git -C "$seed" remote add origin "$origin"
git -C "$seed" push --quiet -u origin main

# Usage:
#   make_clone <name>, prints the clone path
make_clone() {
  git clone --quiet "$origin" "$TEST_HOME/$1"
  echo "$TEST_HOME/$1"
}

behind=$(make_clone behind)
feature=$(make_clone feature)
git -C "$feature" switch --quiet -c feature/x
dirty=$(make_clone dirty)
echo 'local edit' >"$dirty/file.txt"
conflicting=$(make_clone conflicting)
echo 'local change' >"$conflicting/file.txt"
git -C "$conflicting" commit --quiet -am 'Local change'

# Origin moves ahead after every clone was made.
echo 'second' >"$seed/file.txt"
git -C "$seed" commit --quiet -am 'Upstream change'
git -C "$seed" push --quiet

feature_before=$(git -C "$feature" rev-parse HEAD)
dirty_before=$(git -C "$dirty" rev-parse HEAD)
conflicting_before=$(git -C "$conflicting" rev-parse HEAD)
origin_head=$(git -C "$seed" rev-parse HEAD)

bash "$REPO_SYNC_SCRIPT" --force --detached "$behind" "$feature" "$dirty" "$conflicting"

failures=0

# Usage:
#   expect_head <checkout> <commit> <message>
expect_head() {
  if [ "$(git -C "$1" rev-parse HEAD)" != "$2" ]; then
    echo "FAIL: $3"
    failures=$((failures + 1))
  fi
}

expect_head "$behind" "$origin_head" "main checkout behind origin was not fast-forwarded"
expect_head "$feature" "$feature_before" "checkout on feature/x was moved"
expect_head "$dirty" "$dirty_before" "checkout with uncommitted changes was moved"
if [ "$(cat "$dirty/file.txt")" != 'local edit' ]; then
  echo "FAIL: uncommitted change in the dirty checkout was lost"
  failures=$((failures + 1))
fi
expect_head "$conflicting" "$conflicting_before" "conflicting checkout was not restored after the aborted rebase"
if [ -e "$(git -C "$conflicting" rev-parse --path-format=absolute --git-path rebase-merge)" ]; then
  echo "FAIL: conflicting checkout was left mid rebase"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: repo-sync"
