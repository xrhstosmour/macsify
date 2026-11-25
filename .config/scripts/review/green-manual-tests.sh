#!/usr/bin/env bash
# Starts a test workflow that `green-respond.sh dispatch` and `green-git.sh tests` refuse because its tree mentions a deploy word, by moving your own branch to the head of the pull request, a branch whose push runs that workflow, the manual trigger you would run by hand.
# Only for a repository and workflow you listed once in `manual-tests` next to the trust file of `lib.sh`, one `<owner/repo> <workflow file> <branch>` per line, written by hand, never by an agent, `claude/settings.json` denies the edit. Listing a line approves moving that branch for every pull request of the repository, so it must be a branch you use for nothing else, which nothing deploys from.
# Allowed in claude/settings.json by its path, so it validates every input and config line itself and calls fixed endpoints, never a caller supplied one.
# It never moves `main`, `master`, the default branch, a branch named after a deploy target or the branch of the pull request itself, and moves nothing while a run of the branch is not completed, another slot is moving it, or it moved under two minutes ago, the branch is yours too and a push would cancel or mix that run.
#
# Usage: green-manual-tests.sh <owner/repo> <number> <head sha> <workflow file>
#        green-manual-tests.sh due <owner/repo> <number> <head sha> <workflow file>
# Prints `<branch> <head sha>` once the branch is at the head.
# Exit 0 moved, 1 refused, 2 bad input, 6 no line of `manual-tests` for the repository and workflow, so the caller keeps its own needs attention line, 7 the branch is busy as above, or the last busy try of this head is under five minutes old, so the caller tries again later, 8 six busy tries of this head already, so the caller gives up and shows it.
# `due` reads only the busy tries and calls nothing, exit 0 when a try may run now, 7 or 8 as above, so the dispatcher starts no agent that would only wait.
# The limits live here and not in the dispatcher's prose, so a busy branch can never start an agent every poll.

set -e

# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

due_only=false
if [ "$1" = due ]; then
  due_only=true
  shift
fi
if [ $# -ne 4 ]; then
  echo "usage: green-manual-tests.sh [due] <owner/repo> <number> <head sha> <workflow file>" >&2
  exit 2
fi
repository="$1"
number="$2"
head_sha="$3"
workflow="$4"
require_repository "$repository"
require_number "pull request number" "$number"
require_sha "head" "$head_sha"
require_workflow_file "$workflow"

tries_file="${XDG_CACHE_HOME:-$HOME/.cache}/green-github-prs-watcher/manual-tries"
try_key="$repository#$number $head_sha $workflow"
retry_seconds=300
maximum_tries=6
# One `<epoch> <owner/repo>#<number> <head sha> <workflow file>` line per busy try, a new head starts again from none.
tries=0
last_try=0
if [ -f "$tries_file" ]; then
  while read -r try_time try_pull_request try_head try_workflow; do
    if [ "$try_pull_request $try_head $try_workflow" = "$try_key" ]; then
      tries=$((tries + 1))
      last_try="$try_time"
    fi
  done <"$tries_file"
fi
if [ "$tries" -ge "$maximum_tries" ]; then
  echo "the manual trigger was busy $tries times at $head_sha, trigger it by hand" >&2
  exit 8
fi
if [ $(($(date +%s) - last_try)) -lt "$retry_seconds" ]; then
  echo "the last busy try at $head_sha is under $retry_seconds seconds old, try again later" >&2
  exit 7
fi
if [ "$due_only" = true ]; then
  exit 0
fi

manual_tests_file="$HOME/.config/green-github-prs-watcher/manual-tests"
manual_tests_pattern='^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100} [A-Za-z0-9_][A-Za-z0-9._-]{0,99}\.ya?ml [A-Za-z0-9_][A-Za-z0-9._/-]{0,100}$'

if [ ! -e "$manual_tests_file" ] && [ ! -L "$manual_tests_file" ]; then
  echo "no manual-tests file, trigger $workflow by hand" >&2
  exit 6
fi
# A file nobody can read, or with a line that is not an entry, fails closed like the trust file, it must not approve anything.
if [ -L "$manual_tests_file" ] || [ ! -f "$manual_tests_file" ] || grep -qvE "$manual_tests_pattern" "$manual_tests_file"; then
  echo "$manual_tests_file is not a plain file of <owner/repo> <workflow file> <branch> lines, fix or remove it" >&2
  exit 1
fi
# The first line of the repository and workflow wins, so the answer never depends on the order a reader picks.
branch=""
while read -r line_repository line_workflow line_branch; do
  if [ "$line_repository" = "$repository" ] && [ "$line_workflow" = "$workflow" ]; then
    branch="$line_branch"
    break
  fi
done <"$manual_tests_file"
if [ -z "$branch" ]; then
  echo "no manual-tests line for $repository $workflow, trigger it by hand" >&2
  exit 6
fi
# A line git cannot take as a branch name is as bad as a line that is no entry.
if ! git check-ref-format "refs/heads/$branch"; then
  echo "invalid manual-tests branch: $branch" >&2
  exit 1
fi

viewer="$(gh api user --jq .login)"
pull_request="$(gh api "repos/$repository/pulls/$number" --jq '"\(.state) \(.draft) \(.user.login) \(.head.sha) \(.head.repo.full_name) \(.changed_files) \(.head.ref)"')"
read -r state draft author current_head head_repository changed_files ref <<<"$pull_request"
if [ "$state $draft $author" != "open false $viewer" ]; then
  echo "pull request $number is not an open pull request of yours that is ready" >&2
  exit 1
fi
if [ "$current_head" != "$head_sha" ] || [ "$head_repository" != "$repository" ]; then
  echo "pull request $number is not at $head_sha in $repository" >&2
  exit 1
fi
# The branch push runs the workflow of the head with the repository's secrets, so a change to `.github` is never run unattended, as in `green-respond.sh dispatch`.
require_number "changed files" "$changed_files"
if [ "$changed_files" -gt 3000 ]; then
  echo "pull request $number changes more files than can be checked, trigger its tests by hand" >&2
  exit 1
fi
if [ -n "$(gh api --paginate "repos/$repository/pulls/$number/files?per_page=100" --jq '.[].filename | select(startswith(".github/"))')" ]; then
  echo "the pull request changes .github, trigger its tests by hand" >&2
  exit 1
fi

default_branch="$(gh api "repos/$repository" --jq .default_branch)"
require_branch "default branch" "$default_branch"
if [ "$branch" = "main" ] || [ "$branch" = "master" ] || [ "$branch" = "$default_branch" ] || [ "$branch" = "$ref" ] || is_deploy_target "$branch"; then
  echo "refusing to move $branch, it is the default branch, the branch of the pull request or named after a deploy target" >&2
  exit 1
fi

state_directory="$(dirname "$tries_file")"
mkdir -p "$state_directory"
record_busy() {
  echo "$(date +%s) $try_key" >>"$tries_file"
  echo "$1, try again later" >&2
  exit 7
}

# The watcher runs this from several slots at once, the lock keeps two of them from both finding the branch idle and both moving it. A lock left by a killed run frees itself after ten minutes.
lock="$state_directory/manual-lock-${repository//\//_}-${branch//\//_}"
find "$lock" -maxdepth 0 -mmin +10 -exec rmdir {} \; 2>/dev/null || true
if ! mkdir "$lock" 2>/dev/null; then
  record_busy "another run is moving $branch"
fi
trap 'rmdir "$lock"' EXIT

# The run a move starts takes a while to show up in the run list, so the branch stays busy for two minutes after a move.
moves_file="$state_directory/manual-moves"
move_seconds=120
last_move=0
if [ -f "$moves_file" ]; then
  while read -r move_time move_repository move_branch; do
    if [ "$move_repository $move_branch" = "$repository $branch" ]; then
      last_move="$move_time"
    fi
  done <"$moves_file"
fi
if [ $(($(date +%s) - last_move)) -lt "$move_seconds" ]; then
  record_busy "$branch was moved under $move_seconds seconds ago"
fi

busy="$(gh run list --repo "$repository" --branch "$branch" --json status --jq '[.[] | select(.status != "completed")] | length')"
require_number "run count" "$busy"
if [ "$busy" -gt 0 ]; then
  record_busy "$branch has $busy run not completed"
fi

# The reads above took a while, a push in the meantime would run a head nobody checked.
if [ "$(gh api "repos/$repository/pulls/$number" --jq .head.sha)" != "$head_sha" ]; then
  echo "pull request $number moved from $head_sha, trigger its tests by hand" >&2
  exit 1
fi
# The matching refs endpoint lists by prefix and answers an empty list for none, unlike a read of the ref, whose 404 could not be told from another failure.
existing="$(gh api "repos/$repository/git/matching-refs/heads/$branch" --jq '.[].ref')"
if grep -qxF -- "refs/heads/$branch" <<<"$existing"; then
  gh api -X PATCH "repos/$repository/git/refs/heads/$branch" -f "sha=$head_sha" -F force=true >/dev/null
else
  gh api -X POST "repos/$repository/git/refs" -f "ref=refs/heads/$branch" -f "sha=$head_sha" >/dev/null
fi
echo "$(date +%s) $repository $branch" >>"$moves_file"
echo "$branch $head_sha"
