#!/usr/bin/env bash
# Prepares the detached `reviews-<slot>` worktree at the head of one pull request for the `review-github-prs-watcher` skill and prints its path.
# Allowed in claude/settings.json by its path, so it validates every input itself and runs only the fixed git commands below. A broad `git -C` allow rule would let `-c` options or `--output` through with no prompt while the model reads untrusted pull request content.
# Hooks are switched off for every git command, the worktree holds the pull request's own files and a `post-checkout` hook must never run from them. Symlinks of the pull request are written as plain files, so the allowed `Read` of the worktree never follows one out of it, and `git-lfs` filters are skipped, they would contact a server the pull request picks.
# Up to three reviews run at once, one per slot, each slot a worktree of its own reused across pull requests, so a review never waits for a full checkout of a large repository. The slots of one repository share `FETCH_HEAD`, and its `refs/remotes` with the green watcher's, so the `fetch` lock in its git directory, the one `green-worktree.sh` and `green-git.sh` take, lets one run at a time through the fetch. Each slot moves only its own worktree, so the moves run at once.
# It never touches a branch or a working tree of yours, the only worktrees it creates or moves are `<developer>/worktrees/<checkout>/reviews-<slot>`, names the `Herdr` worktree cleanup never removes.
#
# Usage: review-worktree.sh <owner/repo> <pull request number> <head sha> <slot 1-3>
# The developer directory is `~/Developer`, `REVIEW_DEVELOPER_DIRECTORY` replaces it for the tests, and `REVIEW_LOCK_ATTEMPTS` the 120 seconds the lock is waited for.

set -e

# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [ $# -ne 4 ]; then
  echo "usage: review-worktree.sh <owner/repo> <number> <head sha> <slot 1-3>" >&2
  exit 2
fi

repository="$1"
number="$2"
head_sha="$3"
slot="$4"

require_repository "$repository"
require_number "pull request number" "$number"
require_sha "head sha" "$head_sha"
if ! [[ $slot =~ ^[1-3]$ ]]; then
  echo "invalid slot: $slot" >&2
  exit 2
fi

developer="${REVIEW_DEVELOPER_DIRECTORY:-$HOME/Developer}"

git_without_hooks() {
  GIT_LFS_SKIP_SMUDGE=1 git -c core.hooksPath=/dev/null -c core.symlinks=false "$@"
}

checkout="$(find_checkout "$developer" "$repository")"
# The subshell frees the `fetch` lock before the move, a slow checkout never holds up the fetches of the other slots.
(
  lock_checkout "$checkout" fetch
  git_without_hooks -C "$checkout" fetch --quiet origin "pull/$number/head" >&2
  if [ "$(git -C "$checkout" rev-parse FETCH_HEAD)" != "$head_sha" ]; then
    echo "pull request $number is not at $head_sha anymore" >&2
    exit 1
  fi
)

worktree="$developer/worktrees/$(basename "$checkout")/reviews-$slot"
if [ -e "$worktree" ]; then
  # Another repository's worktree would not hold this commit, stop instead of moving it.
  if [ "$(git -C "$worktree" rev-parse --path-format=absolute --git-common-dir)" != "$(git -C "$checkout" rev-parse --path-format=absolute --git-common-dir)" ]; then
    echo "$worktree belongs to another repository" >&2
    exit 1
  fi
  git_without_hooks -C "$worktree" checkout --quiet --detach "$head_sha" >&2
else
  mkdir -p "$(dirname "$worktree")"
  git_without_hooks -C "$checkout" worktree add --quiet --detach "$worktree" "$head_sha" >&2
fi

echo "$worktree"
