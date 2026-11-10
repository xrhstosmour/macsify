#!/bin/bash

# Checks that the permission rules in `claude/settings.json` keep the entries the
# rest of the setup relies on. It reads the file only, it does not run Claude
# Code's matcher, so it catches a rule being deleted or widened, not one that
# is written wrong.

set -e

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SETTINGS_FILE="$TESTS_SCRIPT_DIRECTORY/../claude/settings.json"

failures=0

# Usage:
#   expect_rule <deny|ask|allow> <rule> <present|absent>
expect_rule() {
  local list="$1" rule="$2" expected="$3" actual="absent"
  if jq -e --arg list "$list" --arg rule "$rule" '.permissions[$list] | index($rule) != null' "$SETTINGS_FILE" >/dev/null; then
    actual="present"
  fi
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: '$rule' in permissions.$list should be $expected"
    failures=$((failures + 1))
  fi
}

expect_rule deny 'Bash(sudo *)' present
expect_rule deny 'Bash(git push *--force* main)' present
expect_rule deny 'Bash(git push --mirror *)' present
expect_rule ask 'Bash(git branch -D *)' present
expect_rule ask 'Bash(git reset --hard *)' present
# The force-with-lease allow only holds while these ask rules cover the other spellings of the default branch.
expect_rule ask 'Bash(git push*+*main*)' present
expect_rule ask 'Bash(git push*refs/heads/main*)' present
# The resolves worktree is editable, its `.git` pointer must not be, `green-git.sh` checks it too.
expect_rule deny 'Edit(~/Developer/worktrees/*/resolves/.git)' present
# Nor a `.git` in a folder of it, which would turn that folder into a submodule with a configuration of the caller.
expect_rule deny 'Edit(~/Developer/worktrees/*/resolves/**/.git)' present
# The green watcher cuts a failed check log piped into `tail -n 200`, only that exact form is allowed, a file argument would read any file unprompted.
expect_rule allow 'Bash(tail -n 200)' present
expect_rule allow 'Bash(tail -n *)' absent
# Port scanning is not something to allow unprompted.
expect_rule allow 'Bash(nc -z *)' absent
# The green watcher searches past sessions through `green-search.sh`, scoped to the checkout of the pull request, never a `Read` of every transcript.
expect_rule allow 'Bash(~/.config/scripts/review/green-search.sh *)' present
expect_rule allow 'Read(~/.claude/projects/*-Developer-*/**)' absent
expect_rule allow 'Read(~/.claude/projects/**)' absent
# Only the read-only `qmd` commands, never a bare `qmd *` that would allow its writes too.
expect_rule allow 'Bash(qmd search *)' present
expect_rule allow 'Bash(qmd query *)' present
expect_rule allow 'Bash(qmd get *)' present
expect_rule allow 'Bash(qmd *)' absent
# Search endpoints are read-only, the ask rules on the write flags must keep winning over the `gh api` allows.
expect_rule allow 'Bash(gh api search/*)' present
expect_rule ask 'Bash(gh api *-X*)' present
expect_rule ask 'Bash(gh api *-f*)' present
# Trusting a workflow that mentions a deploy is your call, `green-trust.sh` is a script of its own on no allow list so every run asks, and the trust file is never written outside it.
# A Bash rule matches the command text, so the ask rule takes any spelling of the path, `~`, `$HOME` or absolute.
expect_rule ask 'Bash(*green-trust.sh*)' present
expect_rule allow 'Bash(~/.config/scripts/review/green-trust.sh *)' absent
expect_rule deny 'Edit(~/.config/green-github-prs-watcher/**)' present
expect_rule deny 'Bash(*trusted-workflows*)' present
# Nor writes the state that tells its own cycles from yours, a deleted line would resume a paused pull request, `seen` stays editable for a recheck.
expect_rule deny 'Edit(~/.cache/green-github-prs-watcher/claimed)' present
expect_rule deny 'Edit(~/.cache/green-github-prs-watcher/pushed)' present
expect_rule deny 'Bash(*green-github-prs-watcher/claimed*)' present
expect_rule deny 'Bash(*green-github-prs-watcher/pushed*)' present
# A command run with another cache would push without a record or detect from empty state. The rules match command text only, defense in depth next to the skill's rule.
expect_rule deny 'Bash(*XDG_CACHE_HOME=*)' present
# `rg --pre` runs any command, so `rg` stays prompted.
expect_rule allow 'Bash(rg *)' absent

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: claude-settings"
