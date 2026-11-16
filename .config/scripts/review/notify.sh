#!/usr/bin/env bash
# Shows a macOS notification that opens a GitHub link on click, through the app `setup/agentic.sh` builds from `settings/review-notifier`.
# Best effort, a missing app or a refused notification exits 0, the callers have already done their work and must not fail over a banner.
#
# Usage: notify.sh <title> <message> <github url> <group> [ok|bad|info]
#   group: a later notification with the same group replaces the earlier one
#   status: the mark on the banner picture, ok is a check, bad a cross, info a bubble
#   REVIEW_NOTIFIER: path of the app's executable, for tests

if [ $# -ne 4 ] && [ $# -ne 5 ]; then
  echo "usage: notify.sh <title> <message> <url> <group> [ok|bad|info]" >&2
  exit 2
fi

title="$1"
message="$2"
url="$3"
group="$4"
status="${5:-}"

case "$status" in
  "" | ok | bad | info) ;;
  *) status="" ;;
esac

notifier="${REVIEW_NOTIFIER:-$HOME/Applications/ReviewNotifier.app/Contents/MacOS/review-notifier}"
[ -x "$notifier" ] || exit 0

# Only a GitHub address is opened on click, the app checks it again.
[[ $url =~ ^https://github\.com/[A-Za-z0-9._/#-]+$ ]] || exit 0

"$notifier" "$title" "$message" "$url" "$group" ${status:+"$status"} >/dev/null 2>&1 || true
exit 0
