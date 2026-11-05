#!/usr/bin/env bash
# Prints one line per open pull request that asks for your review at a head commit not seen before, for the `review-github-pr-watcher` skill and its Monitor.
# It runs from ~/.config without the macsify repository, so it has no shared helpers, and it uses `set -u` without `set -e` to keep polling past one failed call.
# Read only: it lists and reads pull requests, it never posts, edits, checks out or pushes.
#
# Usage: watch-review-requests.sh <organization|me> [--once] [--dry-run] [--interval <seconds>]
#   organization  only pull requests of that organization or user, `me` for every repository
#   --once        poll one time and exit, for a cron fallback
#   --dry-run     print what would be reported and record nothing
#   --interval    seconds between polls, default 60, minimum 30 to stay under the GitHub rate limits
# Output line: <owner>/<repo>#<number>@<head sha> <url>

set -u

STATE_DIRECTORY="${XDG_CACHE_HOME:-$HOME/.cache}/review-github-pr-watcher"
SEEN_FILE="$STATE_DIRECTORY/seen"

scope="${1:-}"
if [ -z "$scope" ]; then
  echo "usage: watch-review-requests.sh <organization|me> [--once] [--dry-run] [--interval <seconds>]" >&2
  exit 2
fi
shift

once=false
dry_run=false
interval=60
while [ $# -gt 0 ]; do
  case "$1" in
    --once) once=true ;;
    --dry-run) dry_run=true ;;
    --interval)
      shift
      interval="${1:-60}"
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

case "$interval" in
  '' | *[!0-9]*)
    echo "interval must be a number of seconds" >&2
    exit 2
    ;;
esac
if [ "$interval" -lt 30 ]; then
  interval=30
fi

# An organization or user name is a plain GitHub login, anything else could smuggle a search qualifier. The bash match is whole string, unlike grep, which checks line by line and lets a newline through.
if [ "$scope" != "me" ] && ! [[ $scope =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,38})$ ]]; then
  echo "invalid organization: $scope" >&2
  exit 2
fi

mkdir -p "$STATE_DIRECTORY"
touch "$SEEN_FILE"

# Search returns `null` nodes for items the token cannot read, such as repositories behind SAML single sign-on, they are skipped below, not reported as pull requests.
# One search per poll, it returns the head commits too, so the cost does not grow with the pull requests waiting. A failure shows on standard error, otherwise an expired token would look like no requests.
# `user-review-requested` is you only, `review-requested` also matches every team you are in. Own pull requests never ask for the author's review.
search_query="is:pr is:open draft:false user-review-requested:@me -author:@me"
if [ "$scope" != "me" ]; then
  search_query="$search_query org:$scope"
fi
GRAPHQL_QUERY='query($search: String!) { search(query: $search, type: ISSUE, first: 50) { nodes { ... on PullRequest { number url headRefOid repository { nameWithOwner } } } } }'

poll() {
  # The seen file only matters while a pull request is open, keep the latest entries.
  if [ "$(wc -l <"$SEEN_FILE")" -gt 2000 ]; then
    tail -n 1000 "$SEEN_FILE" >"$SEEN_FILE.tmp" && mv "$SEEN_FILE.tmp" "$SEEN_FILE"
  fi

  gh api graphql -f query="$GRAPHQL_QUERY" -f "search=$search_query" --jq '.data.search.nodes[] | select(. != null and .number != null) | "\(.repository.nameWithOwner) \(.number) \(.headRefOid) \(.url)"' |
    while read -r repository number head_sha url; do
      [ -n "$repository" ] || continue

      key="$repository#$number@$head_sha"
      if grep -Fqx "$key" "$SEEN_FILE"; then
        continue
      fi

      echo "$key $url"
      if [ "$dry_run" = false ]; then
        echo "$key" >>"$SEEN_FILE"
      fi
    done
}

while true; do
  poll
  if [ "$once" = true ]; then
    break
  fi
  sleep "$interval"
done
