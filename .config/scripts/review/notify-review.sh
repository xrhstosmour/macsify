#!/usr/bin/env bash
# Shows a macOS notification for a review the `review-github-prs-watcher` just posted, a click opens that review.
# Called only by `post-pr-review.sh` after the post. The review already exists, so this never fails, see `notify.sh`.
#
# Usage: notify-review.sh <owner/repo> <pull request number> <APPROVE|REQUEST_CHANGES|COMMENT> <review url>

if [ $# -ne 4 ]; then
  echo "usage: notify-review.sh <owner/repo> <number> <event> <review url>" >&2
  exit 2
fi

repository="$1"
number="$2"
event="$3"
url="$4"

case "$event" in
  APPROVE) state="APPROVED" status="ok" ;;
  REQUEST_CHANGES) state="CHANGES REQUESTED" status="bad" ;;
  COMMENT) state="COMMENTED" status="info" ;;
  *) exit 0 ;;
esac

exec "$(dirname "$0")/notify.sh" "PR #$number $state" "$repository" "$url" "review-$repository#$number" "$status"
