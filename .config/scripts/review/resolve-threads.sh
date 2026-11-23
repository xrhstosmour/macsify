#!/usr/bin/env bash
# The review threads read of the `resolve-github-pr-comments` skill, one JSON object per thread with its comments.
# Allowed in claude/settings.json by its path, so a resolve never stops on the `gh api *-f*` ask rule, which guards the GraphQL mutations a free form query could send. The script validates its inputs and sends one fixed read query, never a caller supplied one.
#
# Usage: resolve-threads.sh <owner/repo> <pull request number>

set -e

# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [ $# -ne 2 ]; then
  echo "usage: resolve-threads.sh <owner/repo> <number>" >&2
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
          id isResolved
          comments(first: 50) {
            totalCount
            nodes { databaseId author { login } body createdAt path line originalCommit { oid } }
          }
        }
      }
    }
  }
}')"

# More than 100 threads or 50 comments in a thread fails loudly instead of dropping the rest, a dropped reply would read as an unanswered thread.
jq -c '.data.repository.pullRequest.reviewThreads
  | if .totalCount > (.nodes | length) then error("more than 100 review threads, add pagination") end
  | .nodes[]
  | if .comments.totalCount > (.comments.nodes | length) then error("more than 50 comments in a review thread, add pagination") end
  | {id, isResolved, comments: [.comments.nodes[] | {databaseId, author: .author.login, body, createdAt, path, line, originalCommit: .originalCommit.oid}]}' <<<"$response"
