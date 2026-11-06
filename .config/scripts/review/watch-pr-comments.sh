#!/usr/bin/env bash
# Prints one line per open pull request of yours with comments to resolve, for the `resolve-github-prs-comments-watcher` skill and its Monitor.
# It runs from ~/.config without the macsify repository, so it carries its own loop, and it uses `set -u` without `set -e` to keep polling past one failed call.
# Read only: it lists and reads pull requests, it never posts, edits, checks out or pushes.
#
# Usage: watch-pr-comments.sh <organization|me> [--once] [--dry-run] [--interval <seconds>]
#        watch-pr-comments.sh --mark <key>
#   organization  only pull requests of that organization or user, `me` for every repository
#   --once        poll one time and exit, for a cron fallback
#   --dry-run     print what would be reported and claim nothing
#   --mark        record one output key as done, the skill calls it once a pull request is handled or deliberately skipped
#   --interval    seconds between polls, default 60, minimum 30 to stay under the GitHub rate limits
# Output line: <key> <head sha> <url> <branch> <reason>
# Reasons:
#   comments  a person of the organization, a collaborator or a bot commented after you, in an unresolved thread, on the pull request or in a review body, the key is `<owner>/<repo>#<number>+<epoch>` of the newest one, without the head, so the push of its own run does not start the cycle again
#   capped    the pull request already started `CYCLE_LIMIT` cycles in a day, a failed one included, it is reported once per head, keyed `<owner>/<repo>#<number>@<head sha>`, and not resolved again until the day passes, so a bot that reviews every push or a run that keeps failing cannot loop
# Outsiders never start an unattended change. Drafts, merged, closed, merge queue and cross repository pull requests are skipped, the push goes to `origin`.
# A key is claimed at detection for two hours, so a run still going is not started twice, and recorded as done by `--mark`. Same as `watch-review-requests.sh`.
# The newest 50 threads, 30 comments each, 50 comments and 50 reviews are read, a pull request with more is judged on those.

set -u

STATE_DIRECTORY="${XDG_CACHE_HOME:-$HOME/.cache}/resolve-github-prs-comments-watcher"
SEEN_FILE="$STATE_DIRECTORY/seen"
CLAIMED_FILE="$STATE_DIRECTORY/claimed"
CLAIM_SECONDS=7200
CYCLE_LIMIT=3
CYCLE_SECONDS=86400

# Both files hold `<epoch> <key>`, the epochs of the claimed file count the cycles of a day.
if [ "${1:-}" = "--mark" ]; then
  if ! [[ ${2:-} =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}#[0-9]+(@[0-9a-f]{40}|\+[0-9]+)$ ]]; then
    echo "usage: watch-pr-comments.sh --mark <owner/repo#number+epoch|owner/repo#number@head sha>" >&2
    exit 2
  fi
  mkdir -p "$STATE_DIRECTORY"
  echo "$(date +%s) $2" >>"$SEEN_FILE"
  exit 0
fi

scope="${1:-}"
if [ -z "$scope" ]; then
  echo "usage: watch-pr-comments.sh <organization|me> [--once] [--dry-run] [--interval <seconds>]" >&2
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
touch "$SEEN_FILE" "$CLAIMED_FILE"

# One search per poll returns everything the decision needs. A failure shows on standard error, otherwise an expired token would look like no comments.
# Search returns `null` nodes for items the token cannot read, such as repositories behind SAML single sign-on, they are skipped below.
search="is:pr is:open -is:queued draft:false author:@me"
if [ "$scope" != "me" ]; then
  search="$search org:$scope"
fi
# The `$` names are GraphQL variables, not shell ones.
# shellcheck disable=SC2016
GRAPHQL_QUERY='
fragment Author on Actor { __typename login }
query($search: String!) {
  viewer { login }
  search(query: $search, type: ISSUE, first: 50) { nodes { ... on PullRequest {
    number url headRefOid headRefName isCrossRepository repository { nameWithOwner }
    reviewThreads(last: 50) { nodes { isResolved comments(last: 30) { nodes { author { ...Author } authorAssociation createdAt } } } }
    comments(last: 50) { nodes { author { ...Author } authorAssociation createdAt } }
    reviews(last: 50) { nodes { author { ...Author } authorAssociation body submittedAt } }
  } } }
}'

# A comment counts when a bot or a person of the organization or a collaborator wrote it, never you, never a deleted author.
# In an unresolved thread it counts after your last comment there, on the pull request and in a review body after your last comment on the pull request. A review with an empty body is the wrapper of inline comments, the threads carry those.
# shellcheck disable=SC2016
JQ_FILTER='
.data.viewer.login as $me
| def counts: .author != null and .author.login != $me
    and (.author.__typename == "Bot" or (.author.__typename == "User" and (.authorAssociation | IN("OWNER", "MEMBER", "COLLABORATOR"))));
  def after($time): [.[] | select(counts and .time > $time) | .time] | max;
  .data.search.nodes[]
  | select(. != null and .number != null and .isCrossRepository == false)
  | ([.comments.nodes[] | select(.author.login == $me) | .createdAt] | max // "") as $mine
  | ([
      (.reviewThreads.nodes[] | select(.isResolved == false) | [.comments.nodes[] | . + {time: .createdAt}]
        | ([.[] | select(.author.login == $me) | .time] | max // "") as $last | after($last)),
      ([.comments.nodes[] | . + {time: .createdAt}] + [.reviews.nodes[] | select(.body != "") | . + {time: .submittedAt}]
        | map(select(.author.__typename == "User")) | after($mine))
    ] | map(select(. != null)) | max) as $newest
  | select($newest != null)
  | "\(.repository.nameWithOwner) \(.number) \(.headRefOid) \($newest | fromdateiso8601) \(.url) \(.headRefName)"'

# Whether a key is done or claimed by a run that started less than two hours ago.
claimed() {
  awk -v key="$1" '$2 == key { found = 1 } END { exit !found }' "$SEEN_FILE" && return 0
  awk -v key="$1" -v now="$(date +%s)" -v limit="$CLAIM_SECONDS" '$2 == key && now - $1 < limit { found = 1 } END { exit !found }' "$CLAIMED_FILE"
}

# How many comment cycles of the pull request started in the last day. Every claim counts, so a run that fails and is claimed again counts each time.
cycles() {
  awk -v prefix="$1+" -v now="$(date +%s)" -v limit="$CYCLE_SECONDS" 'index($2, prefix) == 1 && now - $1 < limit { count++ } END { print count + 0 }' "$CLAIMED_FILE"
}

poll() {
  # Both files only matter while a pull request is open, keep the latest entries.
  local file
  for file in "$SEEN_FILE" "$CLAIMED_FILE"; do
    if [ "$(wc -l <"$file")" -gt 2000 ]; then
      tail -n 1000 "$file" >"$file.tmp" && mv "$file.tmp" "$file"
    fi
  done

  gh api graphql -f query="$GRAPHQL_QUERY" -f "search=$search" --jq "$JQ_FILTER" |
    while read -r repository number head epoch url branch; do
      [ -n "$repository" ] || continue

      pull_request="$repository#$number"
      key="$pull_request+$epoch"
      reason=comments
      # A cycle still going is skipped before the cap, its own claim would count it as capped otherwise.
      if claimed "$key"; then
        continue
      fi
      if [ "$(cycles "$pull_request")" -ge "$CYCLE_LIMIT" ]; then
        key="$pull_request@$head"
        reason=capped
        if claimed "$key"; then
          continue
        fi
      fi

      echo "$key $head $url $branch $reason"
      if [ "$dry_run" = false ]; then
        echo "$(date +%s) $key" >>"$CLAIMED_FILE"
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
