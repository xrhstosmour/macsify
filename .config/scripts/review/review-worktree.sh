#!/usr/bin/env bash
# Prepares the detached `reviews` worktree at the head of one pull request for the `review-github-prs-watcher` skill and prints its path.
# Allowed in claude/settings.json by its path, so it validates every input itself and runs only the fixed git commands below. A broad `git -C` allow rule would let `-c` options or `--output` through with no prompt while the model reads untrusted pull request content.
# Hooks are switched off for every git command, the worktree holds the pull request's own files and a `post-checkout` hook must never run from them. Symlinks of the pull request are written as plain files, so the allowed `Read` of the worktree never follows one out of it, and `git-lfs` filters are skipped, they would contact a server the pull request picks.
# One run at a time per repository, a lock in its git directory, because all its pull requests share one worktree and `FETCH_HEAD`. The caller reviews one pull request at a time, the lock only covers the fetch and the move.
# It never touches a branch or a working tree of yours, the only worktree it creates or moves is `<developer>/worktrees/<checkout>/reviews`, a name the `Herdr` worktree cleanup never removes.
#
# Usage: review-worktree.sh <owner/repo> <pull request number> <head sha>
# The developer directory is `~/Developer`, `REVIEW_DEVELOPER_DIRECTORY` replaces it for the tests, and `REVIEW_LOCK_ATTEMPTS` the 120 seconds the lock is waited for.

set -e

if [ $# -ne 3 ]; then
  echo "usage: review-worktree.sh <owner/repo> <number> <head sha>" >&2
  exit 2
fi

repository="$1"
number="$2"
head_sha="$3"

# Whole string matches, grep would check line by line and let a newline through.
if ! [[ $repository =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$ ]]; then
  echo "invalid repository: $repository" >&2
  exit 2
fi
case "$number" in
  '' | *[!0-9]*)
    echo "invalid pull request number: $number" >&2
    exit 2
    ;;
esac
if ! [[ $head_sha =~ ^[0-9a-f]{40}$ ]]; then
  echo "invalid head sha: $head_sha" >&2
  exit 2
fi

developer="${REVIEW_DEVELOPER_DIRECTORY:-$HOME/Developer}"
owner="${repository%%/*}"
name="${repository##*/}"

git_without_hooks() {
  GIT_LFS_SKIP_SMUDGE=1 git -c core.hooksPath=/dev/null -c core.symlinks=false "$@"
}

# A checkout of this repository already on the machine, found by its `origin`, whatever its folder is called.
checkout=""
for candidate in "$developer"/*/; do
  candidate="${candidate%/}"
  [ -e "$candidate/.git" ] || continue
  url="$(git -C "$candidate" config --get remote.origin.url)" || continue
  case "${url%.git}" in
    *"github.com:$repository" | *"github.com/$repository")
      checkout="$candidate"
      break
      ;;
  esac
done

# Never clone what is already here, and never into a folder that belongs to another repository with the same name.
if [ -z "$checkout" ]; then
  checkout="$developer/$name"
  if [ -e "$checkout" ]; then
    checkout="$developer/$owner-$name"
  fi
  gh repo clone "$repository" "$checkout" >&2
fi

# A lock older than ten minutes is left over from a run that died.
lock="$(git -C "$checkout" rev-parse --path-format=absolute --git-common-dir)/review-worktree.lock"
attempts=0
until mkdir "$lock" 2>/dev/null; do
  if [ -n "$(find "$lock" -maxdepth 0 -mmin +10)" ]; then
    rmdir "$lock"
    continue
  fi
  attempts=$((attempts + 1))
  if [ "$attempts" -gt "${REVIEW_LOCK_ATTEMPTS:-120}" ]; then
    echo "another review holds $lock" >&2
    exit 1
  fi
  sleep 1
done
trap 'rmdir "$lock"' EXIT

git_without_hooks -C "$checkout" fetch --quiet origin "pull/$number/head" >&2
if [ "$(git -C "$checkout" rev-parse FETCH_HEAD)" != "$head_sha" ]; then
  echo "pull request $number is not at $head_sha anymore" >&2
  exit 1
fi

worktree="$developer/worktrees/$(basename "$checkout")/reviews"
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
