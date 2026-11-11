#!/usr/bin/env bash
# Hands out the worktree slots of the `green-github-prs-watcher` and `review-github-prs-watcher` dispatchers, so their background agents stay at four together.
# Each watcher runs up to three agents in slots `1` to `3`, both at three would be six agents, each with its own subagents, too many for one machine. A slot is taken only while the two watchers together run fewer than four.
# A second line of a pull request that already has an agent of the same watcher waits for it, its push or reply during the run comes back as a new line, and two runs on one pull request would push or review over each other.
# Allowed in claude/settings.json by its path, so it checks every argument and writes only its own folder.
#
# Usage:
#   agent-slots.sh take <green|review> <owner/repo#number>   prints the free slot, exit 3 when the cap is reached, exit 4 when the pull request has an agent of this watcher running
#   agent-slots.sh free <green|review> <slot 1-3>
#   agent-slots.sh reset <green|review>                       frees every slot of the watcher, run when its dispatcher starts, the agents of an earlier session ended with it
# The state is one file per taken slot, `<watcher>-<slot>` holding `<epoch> <owner/repo#number>`, in `${XDG_CACHE_HOME:-~/.cache}/watcher-agents`. A slot taken more than two hours ago, the claim of the detectors, is free again, its agent died without freeing it. `REVIEW_LOCK_ATTEMPTS` replaces the 120 seconds the lock is waited for, for the tests.

set -e

# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SLOT_SECONDS=7200
TOTAL_AGENTS=4
WATCHER_AGENTS=3
STATE_DIRECTORY="${XDG_CACHE_HOME:-$HOME/.cache}/watcher-agents"

usage() {
  echo "usage: agent-slots.sh take <green|review> <owner/repo#number> | free <green|review> <slot 1-3> | reset <green|review>" >&2
  exit 2
}

[ $# -ge 2 ] || usage
action="$1"
watcher="$2"
case "$watcher" in
  green | review) ;;
  *) usage ;;
esac

mkdir -p "$STATE_DIRECTORY"
lock_directory "$STATE_DIRECTORY/slots.lock"

case "$action" in
  take)
    [ $# -eq 3 ] || usage
    pull_request="$3"
    require_repository "${pull_request%#*}"
    if [ "${pull_request%#*}" = "$pull_request" ]; then
      usage
    fi
    require_number "pull request number" "${pull_request##*#}"
    now="$(date +%s)"
    total=0
    taken=0
    free_slot=""
    for candidate in green-1 green-2 green-3 review-1 review-2 review-3; do
      file="$STATE_DIRECTORY/$candidate"
      if [ -f "$file" ]; then
        read -r started holder <"$file" || true
        if [[ $started =~ ^[0-9]+$ ]] && [ $((now - started)) -lt "$SLOT_SECONDS" ]; then
          total=$((total + 1))
          if [ "${candidate%-*}" = "$watcher" ]; then
            taken=$((taken + 1))
            if [ "$holder" = "$pull_request" ]; then
              exit 4
            fi
          fi
          continue
        fi
        rm -f "$file"
      fi
      if [ "${candidate%-*}" = "$watcher" ] && [ -z "$free_slot" ]; then
        free_slot="${candidate##*-}"
      fi
    done
    if [ "$total" -ge "$TOTAL_AGENTS" ] || [ "$taken" -ge "$WATCHER_AGENTS" ]; then
      exit 3
    fi
    echo "$now $pull_request" >"$STATE_DIRECTORY/$watcher-$free_slot"
    echo "$free_slot"
    ;;
  free)
    [ $# -eq 3 ] || usage
    if ! [[ $3 =~ ^[1-3]$ ]]; then
      echo "invalid slot: $3" >&2
      exit 2
    fi
    rm -f "$STATE_DIRECTORY/$watcher-$3"
    ;;
  reset)
    [ $# -eq 2 ] || usage
    rm -f "$STATE_DIRECTORY/$watcher-1" "$STATE_DIRECTORY/$watcher-2" "$STATE_DIRECTORY/$watcher-3"
    ;;
  *) usage ;;
esac
