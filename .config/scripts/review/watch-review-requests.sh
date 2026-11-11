#!/usr/bin/env bash
# Prints one line per open pull request that needs you again, for the `review-github-prs-watcher` skill and its Monitor.
# It runs from ~/.config without the macsify repository, so it has no shared helpers, and it uses `set -u` without `set -e` to keep polling past one failed call.
# Read only: it lists and reads pull requests, it never posts, edits, checks out or pushes.
#
# Usage: watch-review-requests.sh <organization|me> [--once] [--dry-run] [--interval <seconds>]
#        watch-review-requests.sh --mark <key>
#   organization  only pull requests of that organization or user, `me` for every repository
#   --once        poll one time and exit, for a cron fallback
#   --dry-run     print what would be reported and claim nothing
#   --mark        record one output key as done, the skill calls it after a review is posted or deliberately skipped
#   --interval    seconds between polls, default 60, minimum 30 to stay under the GitHub rate limits
# Output line: <owner>/<repo>#<number>@<head sha>[+<epoch>] <url> <reason>, the first field is the key
# Reasons, a pull request you approved never comes back unless it asks for your review again:
#   requested  your review is requested, a first time or again
#   pushed     you reviewed it without approving and the author pushed since
#   reply      you reviewed it without approving and a person of the organization or a collaborator answered in a thread you took part in, the key ends in the epoch of the newest answer
# A key is claimed at detection for two hours, so a review still running is not started twice, and recorded as done by `--mark`. A review that failed or was interrupted is reported again once its claim expires. Approximate on purpose, the poster refuses a second review at the same commit. The poster also reads the claimed file, it posts an `APPROVE` only for a key claimed here less than `CLAIM_SECONDS` ago, so a review that outlives the claim cannot approve.
# The newest 30 threads, 30 comments each and 50 reviews are read, a pull request with more is judged on those.

set -u

# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STATE_DIRECTORY="${XDG_CACHE_HOME:-$HOME/.cache}/review-github-prs-watcher"
SEEN_FILE="$STATE_DIRECTORY/seen"
CLAIMED_FILE="$STATE_DIRECTORY/claimed"
CLAIM_SECONDS=7200

if [ "${1:-}" = "--mark" ]; then
  if ! [[ ${2:-} =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}#[0-9]+@[0-9a-f]{40}(\+[0-9]+)?$ ]]; then
    echo "usage: watch-review-requests.sh --mark <owner/repo#number@head sha[+epoch]>" >&2
    exit 2
  fi
  lock_state "$STATE_DIRECTORY"
  echo "$2" >>"$SEEN_FILE"
  exit 0
fi

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
touch "$SEEN_FILE" "$CLAIMED_FILE"

# Search returns `null` nodes for items the token cannot read, such as repositories behind SAML single sign-on, they are skipped below, not reported as pull requests.
# Two searches per poll, both return what the decision needs, so the cost does not grow with the pull requests waiting. A failure shows on standard error, otherwise an expired token would look like no requests.
# `user-review-requested` is you only, `review-requested` also matches every team you are in, and GitHub clears it when you review, so it only matches again when the author asks again. Own pull requests never ask for the author's review.
# `is:open` leaves out merged and closed, `-is:queued` the ones already in the merge queue.
requested_query="is:pr is:open -is:queued draft:false user-review-requested:@me -author:@me"
reviewed_query="is:pr is:open -is:queued draft:false reviewed-by:@me -author:@me"
if [ "$scope" != "me" ]; then
  requested_query="$requested_query org:$scope"
  reviewed_query="$reviewed_query org:$scope"
fi
# The `$` names are GraphQL variables, not shell ones.
# shellcheck disable=SC2016
GRAPHQL_QUERY='
fragment Details on PullRequest {
  number url headRefOid repository { nameWithOwner }
  reviews(last: 50) { nodes { author { login } state commit { oid } } }
  reviewThreads(last: 30) { nodes { comments(last: 30) { nodes { author { __typename login } authorAssociation createdAt } } } }
}
query($requested: String!, $reviewed: String!) {
  viewer { login }
  requested: search(query: $requested, type: ISSUE, first: 50) { nodes { ...Details } }
  reviewed: search(query: $reviewed, type: ISSUE, first: 50) { nodes { ...Details } }
}'

# Your reviews of the pull request, the newest 50. A reply in a thread creates a COMMENTED review too, so approval is judged on the latest review that is not COMMENTED, and the reviewed commit on the latest of all.
# The newest answer comes from a person, never a bot or a deleted author, who belongs to the organization or collaborates on the repository, after your last comment in a thread you took part in. An outsider's comment never starts an unattended reply.
# shellcheck disable=SC2016
JQ_FILTER='
.data.viewer.login as $me
| def answered: [
    .reviewThreads.nodes[].comments.nodes as $comments
    | ([$comments[] | select(.author.login == $me)] | last) as $mine
    | select($mine != null)
    | [$comments[] | select(.author != null and .author.__typename == "User" and .author.login != $me and (.authorAssociation | IN("OWNER", "MEMBER", "COLLABORATOR")) and .createdAt > $mine.createdAt) | .createdAt]
    | max | select(. != null)
  ] | max;
  def line($identity; $reason): "\(.repository.nameWithOwner) \(.number) \($identity) \(.url) \($reason)";
  (.data.requested.nodes[] | select(. != null and .number != null) | line(.headRefOid; "requested")),
  (.data.reviewed.nodes[]
    | select(. != null and .number != null)
    | [.reviews.nodes[] | select(.author.login == $me)] as $mine
    | select($mine | length > 0)
    | select(($mine | map(select(.state != "COMMENTED" and .state != "PENDING")) | last | .state) != "APPROVED")
    | if ($mine | last | .commit.oid) != .headRefOid then line(.headRefOid; "pushed")
      else answered as $newest | select($newest != null) | line("\(.headRefOid)+\($newest | fromdateiso8601)"; "reply") end)'

# Whether a key is done or claimed by a review that started less than two hours ago.
claimed() {
  grep -Fqx "$1" "$SEEN_FILE" && return 0
  local now claimed_at claimed_key
  now="$(date +%s)"
  while read -r claimed_at claimed_key; do
    if [ "$claimed_key" = "$1" ] && [ $((now - claimed_at)) -lt "$CLAIM_SECONDS" ]; then
      return 0
    fi
  done <"$CLAIMED_FILE"
  return 1
}

poll() {
  # Both files only matter while a pull request is open, keep the latest entries.
  (
    lock_state "$STATE_DIRECTORY"
    for file in "$SEEN_FILE" "$CLAIMED_FILE"; do
      if [ "$(wc -l <"$file")" -gt 2000 ]; then
        tail -n 1000 "$file" >"$file.tmp" && mv "$file.tmp" "$file"
      fi
    done
  )

  gh api graphql -f query="$GRAPHQL_QUERY" -f "requested=$requested_query" -f "reviewed=$reviewed_query" --jq "$JQ_FILTER" |
    while read -r repository number identity url reason; do
      [ -n "$repository" ] || continue

      key="$repository#$number@$identity"
      if claimed "$key"; then
        continue
      fi

      echo "$key $url $reason"
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
