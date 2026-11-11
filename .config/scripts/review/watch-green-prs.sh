#!/usr/bin/env bash
# Prints one line per open pull request of yours that is not green yet, with comments to resolve, a fixup or conflict to prepare, or a failed check, for the `green-github-prs-watcher` skill and its Monitor.
# It runs from ~/.config without the macsify repository, so it carries its own loop, and it uses `set -u` without `set -e` to keep polling past one failed call.
# Read only: it lists and reads pull requests, it never posts, edits, checks out or pushes.
#
# Usage: watch-green-prs.sh <organization|me> [--once] [--dry-run] [--interval <seconds>]
#        watch-green-prs.sh --mark <key>
#   organization  only pull requests of that organization or user, `me` for every repository
#   --once        poll one time and exit, for a cron fallback
#   --dry-run     print what would be reported and claim nothing
#   --mark        record one output key as done, the skill calls it once a pull request is handled or deliberately skipped
#   --interval    seconds between polls, default 60, minimum 30 to stay under the GitHub rate limits
# Output line: <key> <head sha> <url> <branch> <reason>
# Reasons:
#   comments  a person of the organization, a collaborator or a bot commented after you, in an unresolved thread, on the pull request or in a review body, the key is `<owner>/<repo>#<number>+<epoch>` of the newest one, without the head, so the push of its own run does not start the cycle again
#   prepare   no comments, but a `fixup!`, `squash!` or `amend!` commit is left or the pull request conflicts with its base, keyed `<owner>/<repo>#<number>~<head sha>`, once per head
#   checks    no comments and nothing to prepare, but a check failed on the head and none still runs, so one run sees every failure, keyed `<owner>/<repo>#<number>=<head sha>`, apart from `prepare` so a conflict after a handled failure at the same head still counts, the push of its own run is a new head, so a failure after it starts the next cycle
#   One line per pull request and poll, the first reason not done yet, a reason marked done falls through to the next, so an approval nobody answers never hides a conflict or a failed check. A reason still claimed holds the pull request, its run handles the rest.
#   paused    the last `CYCLE_LIMIT` cycles of the pull request ran with nobody in between and this one would too, reported once per head, keyed `<owner>/<repo>#<number>@<head sha>`, so a bot that reviews every push or a check the watcher keeps breaking cannot loop. A cycle runs with nobody when no member or collaborator wrote any of its comments and its head is one `green-git.sh` pushed or one an earlier cycle already ran on, a bot answering the watcher's replies, or when its key was claimed before, a run that failed. A member's comment or a push of yours resumes it, nothing else does.
# Outsiders never start an unattended change. Drafts, merged, closed, merge queue and cross repository pull requests are skipped, the push goes to `origin`.
# A key is claimed at detection for two hours and recorded as done by `--mark`, same as `watch-review-requests.sh`. While any claim of a pull request is not done, the pull request is held, so a run still going is never started twice, not even for a reason its own push revealed. A run that failed without marking holds it until its claim expires, a newer comment waits too.
# The newest 50 threads, 30 comments each, 50 comments and 50 reviews, 100 commits and 100 checks are read, a pull request with more is judged on those.

set -u

# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STATE_DIRECTORY="${XDG_CACHE_HOME:-$HOME/.cache}/green-github-prs-watcher"
SEEN_FILE="$STATE_DIRECTORY/seen"
CLAIMED_FILE="$STATE_DIRECTORY/claimed"
PUSHED_FILE="$STATE_DIRECTORY/pushed"
CLAIM_SECONDS=7200
CYCLE_LIMIT=3

# Both files hold `<epoch> <key>`, the claimed file adds `auto` for a cycle that ran with nobody in between and `person` otherwise, then the head it ran on. `pushed` holds `<epoch> <head sha>`, written by `green-git.sh`.
if [ "${1:-}" = "--mark" ]; then
  if ! [[ ${2:-} =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}#[0-9]+([@=~][0-9a-f]{40}|\+[0-9]+)$ ]]; then
    echo "usage: watch-green-prs.sh --mark <owner/repo#number+epoch|owner/repo#number=head sha|owner/repo#number~head sha|owner/repo#number@head sha>" >&2
    exit 2
  fi
  lock_state "$STATE_DIRECTORY"
  echo "$(date +%s) $2" >>"$SEEN_FILE"
  exit 0
fi

scope="${1:-}"
if [ -z "$scope" ]; then
  echo "usage: watch-green-prs.sh <organization|me> [--once] [--dry-run] [--interval <seconds>]" >&2
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
touch "$SEEN_FILE" "$CLAIMED_FILE" "$PUSHED_FILE"

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
    number url headRefOid headRefName isCrossRepository repository { nameWithOwner } mergeable
    commits(last: 100) { nodes { commit { messageHeadline } } }
    latest: commits(last: 1) { nodes { commit { statusCheckRollup { state
      contexts(first: 100) { pageInfo { hasNextPage } nodes { ... on CheckRun { status } ... on StatusContext { state } } } } } } }
    reviewThreads(last: 50) { nodes { isResolved comments(last: 30) { nodes { author { ...Author } authorAssociation createdAt } } } }
    comments(last: 50) { nodes { author { ...Author } authorAssociation createdAt } }
    reviews(last: 50) { nodes { author { ...Author } authorAssociation body submittedAt } }
  } } }
}'

# A comment counts when a bot or a person of the organization or a collaborator wrote it, never you, never a deleted author.
# In an unresolved thread it counts after your last comment there, on the pull request and in a review body after your last comment on the pull request. A review with an empty body is the wrapper of inline comments, the threads carry those.
# Each reason carries who started it, `person` when a member or collaborator wrote any of its comments, `machine` for a bot's comments, a fixup, a conflict or failed checks.
# Every reason that applies, one line each, comments before prepare before checks, the loop below reports the first not done yet. A `mergeable` still `UNKNOWN` while GitHub computes it is left for the next poll.
# A head with more than 100 checks is left alone, a pending one could hide past the page.
# shellcheck disable=SC2016
JQ_FILTER='
.data.viewer.login as $me
| def counts: .author != null and .author.login != $me
    and (.author.__typename == "Bot" or (.author.__typename == "User" and (.authorAssociation | IN("OWNER", "MEMBER", "COLLABORATOR"))));
  def after($time): .[] | select(counts and .time > $time);
  .data.search.nodes[]
  | select(. != null and .number != null and .isCrossRepository == false)
  | ([.comments.nodes[] | select(.author.login == $me) | .createdAt] | max // "") as $mine
  | [
      (.reviewThreads.nodes[] | select(.isResolved == false) | [.comments.nodes[] | . + {time: .createdAt}]
        | ([.[] | select(.author.login == $me) | .time] | max // "") as $last | after($last)),
      ([.comments.nodes[] | . + {time: .createdAt}] + [.reviews.nodes[] | select(.body != "") | . + {time: .submittedAt}]
        | map(select(.author.__typename == "User")) | after($mine))
    ] as $new
  | ($new | map(.time) | max) as $newest
  | (if any($new[]; .author.__typename == "User") then "person" else "machine" end) as $by
  | .latest.nodes[0].commit.statusCheckRollup as $rollup
  | ((if $newest != null then "comments \($newest | fromdateiso8601) \($by)" else empty end),
     (if any(.commits.nodes[]; .commit.messageHeadline | test("^(fixup|squash|amend)! ")) or .mergeable == "CONFLICTING" then "prepare 0 machine" else empty end),
     (if ($rollup.state // "" | IN("FAILURE", "ERROR")) and ($rollup.contexts.pageInfo.hasNextPage // false | not)
       and all($rollup.contexts.nodes[]; (.status // "COMPLETED") == "COMPLETED" and (.state // "" | IN("PENDING", "EXPECTED") | not)) then "checks 0 machine" else empty end)) as $reason
  | "\(.repository.nameWithOwner) \(.number) \(.headRefOid) \($reason) \(.url) \(.headRefName)"'

# Whether a key is marked done, after an optional epoch.
done_key() {
  awk -v key="$1" -v since="${2:-0}" '$2 == key && $1 > since { found = 1 } END { exit !found }' "$SEEN_FILE"
}

# Whether a key is claimed by a run that started less than two hours ago, after an optional epoch.
running() {
  awk -v key="$1" -v since="${2:-0}" -v now="$(date +%s)" -v limit="$CLAIM_SECONDS" '$2 == key && $1 > since && now - $1 < limit { found = 1 } END { exit !found }' "$CLAIMED_FILE"
}

# Whether any run of the pull request is claimed and not done yet. A run that answers its comments and pushes a fixup before the autosquash shows a new reason mid-run, it must not start a second cycle.
busy() {
  awk -v seen="$SEEN_FILE" -v pull_request="$1" -v now="$(date +%s)" -v limit="$CLAIM_SECONDS" '
    FILENAME == seen { done[$2] = 1; next }
    index($2, pull_request) == 1 && index("+=~", substr($2, length(pull_request) + 1, 1)) > 0 && now - $1 < limit && !($2 in done) { found = 1 }
    END { exit !found }' "$SEEN_FILE" "$CLAIMED_FILE"
}

# Whether a key was claimed before, a run that failed and comes back.
reclaimed() {
  awk -v key="$1" '$2 == key { found = 1 } END { exit !found }' "$CLAIMED_FILE"
}

# Whether `green-git.sh` pushed the head, so a bot or a check reacting to it reacts to the watcher, not to you.
pushed() {
  awk -v head="$1" '$2 == head { found = 1 } END { exit !found }' "$PUSHED_FILE"
}

# Whether a cycle of the pull request already ran on the head, so a bot answering the watcher's replies with no push in between reacts to the watcher, not to you.
revisited() {
  awk -v pull_request="$1" -v head="$2" 'index($2, pull_request) == 1 && index("+=~", substr($2, length(pull_request) + 1, 1)) > 0 && $4 == head { found = 1 } END { exit !found }' "$CLAIMED_FILE"
}

# Whether the last `CYCLE_LIMIT` cycles of the pull request all ran with nobody in between. A claim from before the third column counts as a person's, so an upgrade pauses nothing.
paused() {
  awk -v pull_request="$1" -v limit="$CYCLE_LIMIT" 'index($2, pull_request) == 1 && index("+=~", substr($2, length(pull_request) + 1, 1)) > 0 { streak = ($3 == "auto") ? streak + 1 : 0 } END { exit !(streak >= limit) }' "$CLAIMED_FILE"
}

# When a person last started a cycle of the pull request, 0 when never, a paused head before it is reported again.
resumed() {
  awk -v pull_request="$1" 'index($2, pull_request) == 1 && index("+=~", substr($2, length(pull_request) + 1, 1)) > 0 && $3 != "auto" { latest = $1 } END { print latest + 0 }' "$CLAIMED_FILE"
}

poll() {
  # The state files only matter while a pull request is open, keep the latest entries.
  (
    lock_state "$STATE_DIRECTORY"
    for file in "$SEEN_FILE" "$CLAIMED_FILE" "$PUSHED_FILE"; do
      if [ "$(wc -l <"$file")" -gt 2000 ]; then
        tail -n 1000 "$file" >"$file.tmp" && mv "$file.tmp" "$file"
      fi
    done
  )

  local held=""
  gh api graphql -f query="$GRAPHQL_QUERY" -f "search=$search" --jq "$JQ_FILTER" |
    while read -r repository number head reason epoch by url branch; do
      [ -n "$repository" ] || continue

      pull_request="$repository#$number"
      if [ "$pull_request" = "$held" ]; then
        continue
      fi
      case "$reason" in
        comments) key="$pull_request+$epoch" ;;
        prepare) key="$pull_request~$head" ;;
        *) key="$pull_request=$head" ;;
      esac
      # Done is checked before the claim, every done key was claimed when it was reported.
      if done_key "$key"; then
        continue
      fi
      held="$pull_request"
      # A cycle still going holds the pull request and is skipped before the pause, its own claim would count otherwise.
      if busy "$pull_request"; then
        continue
      fi
      kind=person
      if reclaimed "$key" || { [ "$by" = machine ] && { pushed "$head" || revisited "$pull_request" "$head"; }; }; then
        kind=auto
      fi
      if [ "$kind" = auto ] && paused "$pull_request"; then
        key="$pull_request@$head"
        reason=paused
        since="$(resumed "$pull_request")"
        if done_key "$key" "$since" || running "$key" "$since"; then
          continue
        fi
      fi

      echo "$key $head $url $branch $reason"
      if [ "$dry_run" = false ]; then
        echo "$(date +%s) $key $kind $head" >>"$CLAIMED_FILE"
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
