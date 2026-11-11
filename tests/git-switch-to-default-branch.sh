#!/bin/bash

# Checks `git_switch_to_default_branch` in `.config/fish/functions/git.fish`, run
# by the `Herdr` sidebar + in every new space: a clean checkout on another branch
# lands on the default branch with the commits `origin` gained since, through
# `repository-sync.sh`, a checkout with uncommitted changes or a rebase in
# progress stays on its branch untouched, and a folder outside a repository or a
# repository without `origin` does nothing. `origin` is a local bare repository.
# Needs `fish`.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY="$TESTS_SCRIPT_DIRECTORY/.."

if ! command -v fish >/dev/null 2>&1; then
  echo "SKIP: fish not found"
  exit 0
fi

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

mkdir -p "$TEST_DIRECTORY/home/.config/herdr-app/mods/repository-sync"
cp "$REPOSITORY/.config/herdr-app/mods/repository-sync/repository-sync.sh" "$TEST_DIRECTORY/home/.config/herdr-app/mods/repository-sync/"

export GIT_CONFIG_GLOBAL="$TEST_DIRECTORY/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.name "Test"
git config --global user.email "test@example.com"
git config --global init.defaultBranch main
git config --global commit.gpgsign false

failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# Runs the function in the folder given, with the files `git.fish` needs sourced.
switch() {
  (cd "$1" && HOME="$TEST_DIRECTORY/home" XDG_CACHE_HOME="$TEST_DIRECTORY/cache" fish -N -c "source $REPOSITORY/.config/fish/constants/colors.fish; source $REPOSITORY/.config/fish/functions/logs.fish; source $REPOSITORY/.config/fish/functions/git.fish; git_switch_to_default_branch") >/dev/null 2>&1
}

git init --quiet --bare "$TEST_DIRECTORY/origin.git"
git clone --quiet "$TEST_DIRECTORY/origin.git" "$TEST_DIRECTORY/seed" 2>/dev/null
echo "tracked" >"$TEST_DIRECTORY/seed/file"
git -C "$TEST_DIRECTORY/seed" add file
git -C "$TEST_DIRECTORY/seed" commit --quiet -m "First"
git -C "$TEST_DIRECTORY/seed" push --quiet origin main
git clone --quiet "$TEST_DIRECTORY/origin.git" "$TEST_DIRECTORY/checkout"
git -C "$TEST_DIRECTORY/checkout" checkout --quiet -b feature
git -C "$TEST_DIRECTORY/checkout" commit --quiet --allow-empty -m "Feature"
git -C "$TEST_DIRECTORY/seed" commit --quiet --allow-empty -m "Second"
git -C "$TEST_DIRECTORY/seed" push --quiet origin main

# Uncommitted changes keep the checkout on its branch, `main` tracks the same
# file, so only the guard stops the checkout from carrying the change over.
echo "edited" >"$TEST_DIRECTORY/checkout/file"
switch "$TEST_DIRECTORY/checkout"
[ "$(git -C "$TEST_DIRECTORY/checkout" branch --show-current)" = "feature" ] || fail "a dirty checkout left its branch"
[ "$(cat "$TEST_DIRECTORY/checkout/file")" = "edited" ] || fail "a dirty checkout lost its changes"
git -C "$TEST_DIRECTORY/checkout" checkout --quiet file

# A rebase paused on a clean tree is left alone.
GIT_SEQUENCE_EDITOR="sed -i.bak s/^pick/edit/" git -C "$TEST_DIRECTORY/checkout" rebase --quiet -i HEAD~1 >/dev/null 2>&1
switch "$TEST_DIRECTORY/checkout"
[ -d "$TEST_DIRECTORY/checkout/.git/rebase-merge" ] || fail "a rebase in progress was disturbed"
[ "$(git -C "$TEST_DIRECTORY/checkout" rev-parse --abbrev-ref HEAD)" = "HEAD" ] || fail "a rebase in progress was switched to a branch"
git -C "$TEST_DIRECTORY/checkout" rebase --abort

# A clean checkout switches and picks up what `origin` gained.
switch "$TEST_DIRECTORY/checkout"
[ "$(git -C "$TEST_DIRECTORY/checkout" branch --show-current)" = "main" ] || fail "a clean checkout did not switch to main"
[ "$(git -C "$TEST_DIRECTORY/checkout" log -1 --format=%s)" = "Second" ] || fail "main did not pick up the commit origin gained"

# A repository without `origin` and a folder outside a repository do nothing and succeed.
git init --quiet "$TEST_DIRECTORY/local"
switch "$TEST_DIRECTORY/local" || fail "a repository without origin failed"
mkdir "$TEST_DIRECTORY/plain"
switch "$TEST_DIRECTORY/plain" || fail "a folder outside a repository failed"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "PASS: git-switch-to-default-branch"
