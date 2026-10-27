#!/bin/bash

# Checks that `repository-sync.sh` fast-forwards a `main` checkout that is behind
# origin, leaves a feature branch, a checkout with uncommitted changes and one
# whose own configuration or hooks would run a command alone, and aborts a conflicting
# rebase with the checkout restored. Runs against a
# temporary `HOME` and local repositories, never touches real checkouts.

set -e

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Overridable so the test can be pointed at an older copy of the script.
REPOSITORY_SYNC_SCRIPT="${REPOSITORY_SYNC_SCRIPT:-$TESTS_SCRIPT_DIRECTORY/../.config/herdr-repository-sync/repository-sync.sh}"

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
# An unreachable extra remote must not block the sync, only `origin` is fetched.
git -C "$behind" remote add unreachable "$TEST_HOME/missing.git"
feature=$(make_clone feature)
git -C "$feature" switch --quiet -c feature/x
dirty=$(make_clone dirty)
echo 'local edit' >"$dirty/file.txt"
conflicting=$(make_clone conflicting)
echo 'local change' >"$conflicting/file.txt"
git -C "$conflicting" commit --quiet -am 'Local change'

# Checkouts whose own configuration or hooks would run a command, each command leaves a
# marker file behind if it ever runs.
monitored=$(make_clone monitored)
git -C "$monitored" config core.fsmonitor "touch '$TEST_HOME/fsmonitor-ran'"
hooked=$(make_clone hooked)
printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$TEST_HOME" >"$hooked/.git/hooks/post-rewrite"
chmod +x "$hooked/.git/hooks/post-rewrite"
hooks_path=$(make_clone hooks-path)
git -C "$hooks_path" config core.hooksPath custom-hooks
filtered=$(make_clone filtered)
git -C "$filtered" config filter.planted.smudge "touch '$TEST_HOME/filter-ran'"
index_hooked=$(make_clone index-hooked)
printf '#!/bin/sh\ntouch "%s/index-hook-ran"\n' "$TEST_HOME" >"$index_hooked/.git/hooks/post-index-change"
chmod +x "$index_hooked/.git/hooks/post-index-change"
# A hook `fetch` and `rebase` never run does not block the sync.
pre_commit=$(make_clone pre-commit)
printf '#!/bin/sh\nexit 0\n' >"$pre_commit/.git/hooks/pre-commit"
chmod +x "$pre_commit/.git/hooks/pre-commit"

# Origin moves ahead after every clone was made.
echo 'second' >"$seed/file.txt"
git -C "$seed" commit --quiet -am 'Upstream change'
git -C "$seed" push --quiet

feature_before=$(git -C "$feature" rev-parse HEAD)
dirty_before=$(git -C "$dirty" rev-parse HEAD)
conflicting_before=$(git -C "$conflicting" rev-parse HEAD)
untrusted_before=$(git -C "$monitored" rev-parse HEAD)
origin_head=$(git -C "$seed" rev-parse HEAD)

bash "$REPOSITORY_SYNC_SCRIPT" --force --detached "$behind" "$feature" "$dirty" "$conflicting" "$monitored" "$hooked" "$hooks_path" "$filtered" "$index_hooked" "$pre_commit"

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
expect_head "$monitored" "$untrusted_before" "checkout with a core.fsmonitor command was synced"
expect_head "$hooked" "$untrusted_before" "checkout with a post-rewrite hook was synced"
expect_head "$hooks_path" "$untrusted_before" "checkout with core.hooksPath was synced"
expect_head "$filtered" "$untrusted_before" "checkout with a filter smudge command was synced"
expect_head "$index_hooked" "$untrusted_before" "checkout with a post-index-change hook was synced"
expect_head "$pre_commit" "$origin_head" "checkout with only a pre-commit hook was not synced"
for marker in fsmonitor-ran hook-ran filter-ran index-hook-ran; do
  if [ -e "$TEST_HOME/$marker" ]; then
    echo "FAIL: a repository's own command ran, $marker exists"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: repository-sync"
