#!/usr/bin/env bash
# The review threads read of the `review-github-pr` and `resolve-github-pr-comments` skills, one JSON object per thread.
# Allowed in claude/settings.json by its path, so a skill never stops on the `gh api *-f*` ask rule, which guards the GraphQL mutations a free form query could send. The script validates its inputs and sends one fixed read query, never a caller supplied one.
#
# Usage: review-threads.sh [--comments] <owner/repo> <pull request number>
#   Without --comments: the threads that are not outdated, with their first comment, for a review.
#   With --comments: every thread with its ID and all its comments, for resolving comments.

set -e

# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

comments=false
if [ "$1" = "--comments" ]; then
  comments=true
  shift
fi

if [ $# -ne 2 ]; then
  echo "usage: review-threads.sh [--comments] <owner/repo> <number>" >&2
  exit 2
fi

repository="$1"
number="$2"

require_repository "$repository"
require_number "pull request number" "$number"

response="$(gh api graphql -F "owner=${repository%%/*}" -F "name=${repository##*/}" -F "number=$number" -f query='
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        totalCount
        nodes {
          id path line isResolved isOutdated
          comments(first: 50) {
            totalCount
            nodes { databaseId author { __typename login } body createdAt path line originalCommit { oid } }
          }
        }
      }
    }
  }
}')"

# More than 100 threads, or 50 comments in a thread when they are all printed, fails loudly instead of dropping the rest, a dropped reply would read as an unanswered thread.
# A review leaves out outdated threads, their code is gone.
jq -c --argjson comments "$comments" '.data.repository.pullRequest.reviewThreads
  | if .totalCount > (.nodes | length) then error("more than 100 review threads, add pagination") end
  | .nodes[]
  | if $comments then
      if .comments.totalCount > (.comments.nodes | length) then error("more than 50 comments in a review thread, add pagination") end
      | {id, isResolved, comments: [.comments.nodes[] | {databaseId, author: .author.login, body, createdAt, path, line, originalCommit: .originalCommit.oid}]}
    else
      select(.isOutdated | not)
      | {path, line, isResolved, author: .comments.nodes[0].author.login, bot: (.comments.nodes[0].author.__typename == "Bot"), body: .comments.nodes[0].body}
    end' <<<"$response"
