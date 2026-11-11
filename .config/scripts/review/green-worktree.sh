#!/usr/bin/env bash
# Prepares the detached `resolves-<slot>` worktree at the head of one pull request of yours for the `green-github-prs-watcher` skill and prints its path.
# A slot is one of three, so up to three pull requests of one repository are handled at once, each in a worktree reused across runs, a fresh checkout of a large repository per pull request would cost minutes.
# Allowed in claude/settings.json by its path, so it validates every input itself and runs only the fixed git commands below, same as `review-worktree.sh`.
# Detached because the branch is usually checked out in a worktree of yours and git refuses a second checkout of it, and a working tree of yours is never touched. Hooks, symlinks and `git-lfs` filters are off as in `review-worktree.sh`.
# Only an open pull request you opened, not a draft, from a branch of the same repository and not `main` or `master`, since the fixes are pushed to that branch on `origin`.
# The base and the branch of the pull request are written to `resolve-base` and `resolve-branch` in the git directory of the worktree, `green-git.sh` reads them there, so the caller never picks where a rebase starts or a push goes.
# A leftover of an earlier run, an unfinished rebase or uncommitted edits, is thrown away, the worktree belongs to the watcher and every run starts at the pushed head.
#
# Usage: green-worktree.sh <owner/repo> <pull request number> <head sha> <branch> <slot 1-3>
# The developer directory is `~/Developer`, `REVIEW_DEVELOPER_DIRECTORY` replaces it for the tests, and `REVIEW_LOCK_ATTEMPTS` the 120 seconds the lock is waited for.

set -e

# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [ $# -ne 5 ]; then
  echo "usage: green-worktree.sh <owner/repo> <number> <head sha> <branch> <slot 1-3>" >&2
  exit 2
fi

repository="$1"
number="$2"
head_sha="$3"
branch="$4"
slot="$5"

if ! [[ $slot =~ ^[1-3]$ ]]; then
  echo "invalid slot: $slot" >&2
  exit 2
fi
require_repository "$repository"
require_number "pull request number" "$number"
require_sha "head sha" "$head_sha"
require_branch branch "$branch"
case "$branch" in
  main | master)
    echo "refusing to resolve on $branch" >&2
    exit 2
    ;;
esac

developer="${REVIEW_DEVELOPER_DIRECTORY:-$HOME/Developer}"

# Submodules are never entered, as in `green-git.sh`.
git_without_hooks() {
  GIT_LFS_SKIP_SMUDGE=1 git -c core.hooksPath=/dev/null -c core.symlinks=false -c core.fsmonitor=false -c submodule.recurse=false -c diff.ignoreSubmodules=all "$@"
}

viewer="$(gh api user --jq .login)"
pull_request="$(gh api "repos/$repository/pulls/$number" --jq '[.state, .draft, .user.login, .head.repo.full_name, .head.ref, .head.sha, .base.ref] | map(tostring) | join(" ")')"
read -r state draft author head_repository head_branch api_sha base <<<"$pull_request"
if [ "$state" != open ] || [ "$draft" != false ]; then
  echo "pull request $number is not open or is a draft" >&2
  exit 1
fi
if [ "$author" != "$viewer" ]; then
  echo "pull request $number is not yours" >&2
  exit 1
fi
if [ "$head_repository" != "$repository" ] || [ "$head_branch" != "$branch" ]; then
  echo "pull request $number is not from $branch of $repository" >&2
  exit 1
fi
if [ "$api_sha" != "$head_sha" ]; then
  echo "pull request $number is not at $head_sha anymore" >&2
  exit 1
fi
require_branch base "$base"

checkout="$(find_checkout "$developer" "$repository")"
# The slots of one checkout share its `refs/remotes` and `FETCH_HEAD`, so the fetches and the read of `FETCH_HEAD` take the `fetch` lock `green-git.sh` and `review-worktree.sh` take too. The subshell frees it before the move, a slow checkout of a large repository never holds up the fetches of the other slots, and each slot moves only its own worktree.
(
  lock_checkout "$checkout" fetch
  git_without_hooks -C "$checkout" fetch --quiet origin "+refs/heads/$base:refs/remotes/origin/$base" >&2
  git_without_hooks -C "$checkout" fetch --quiet origin "pull/$number/head" >&2
  if [ "$(git -C "$checkout" rev-parse FETCH_HEAD)" != "$head_sha" ]; then
    echo "pull request $number is not at $head_sha anymore" >&2
    exit 1
  fi
)

worktree="$developer/worktrees/$(basename "$checkout")/resolves-$slot"
if [ -e "$worktree" ]; then
  # Another repository's worktree would not hold this commit, and a `.git` edited to point elsewhere would run its configuration, stop instead of moving it.
  require_worktree_of "$worktree" "$checkout"
  if [ -d "$(git -C "$worktree" rev-parse --path-format=absolute --git-path rebase-merge)" ]; then
    git_without_hooks -C "$worktree" rebase --abort >&2
  fi
  git_without_hooks -C "$worktree" checkout --quiet --force --detach "$head_sha" >&2
  git_without_hooks -C "$worktree" clean --quiet -fd >&2
else
  mkdir -p "$(dirname "$worktree")"
  git_without_hooks -C "$checkout" worktree add --quiet --detach "$worktree" "$head_sha" >&2
fi

git_directory="$(git -C "$worktree" rev-parse --path-format=absolute --git-dir)"
echo "$base" >"$git_directory/resolve-base"
echo "$branch" >"$git_directory/resolve-branch"

echo "$worktree"
