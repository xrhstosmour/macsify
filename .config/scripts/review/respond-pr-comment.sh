#!/usr/bin/env bash
# The GitHub writes of the `resolve-github-prs-comments-watcher` skill on a pull request of yours: a reaction, a thread reply, a pull request comment, resolving a thread and re-requesting reviews, plus the one read that needs GraphQL, the review threads.
# Allowed in claude/settings.json by its path, so the script validates every input itself and calls one fixed endpoint per action, never a caller supplied one.
# Only an open pull request you opened that is not a draft, and only a comment or a thread of that pull request, so a comment id read from somewhere else never lands on another one.
#
# Usage: respond-pr-comment.sh react <owner/repo> <number> review|issue <comment id> +1|eyes
#        respond-pr-comment.sh reply <owner/repo> <number> <comment id> <body file>
#        respond-pr-comment.sh comment <owner/repo> <number> <body file>
#        respond-pr-comment.sh resolve <owner/repo> <number> <thread id>
#        respond-pr-comment.sh threads <owner/repo> <number>
#        respond-pr-comment.sh rerequest <owner/repo> <number>
#   react    `review` for a comment in a review thread, `issue` for a comment on the pull request
#   reply    answers in the thread of the comment, the replies endpoint takes the first comment of the thread, so that is where it is sent
#   comment  a comment on the pull request, the answer to a comment outside a thread or to a review body
#   resolve  the GraphQL id of the review thread, `PRRT_...`
#   threads  prints the first 100 review threads, 50 comments each, as JSON, only the comments of owners, members, collaborators, bots and you, the read `resolve-github-pr-comments` makes with `gh api graphql -f`, which waits for a prompt
#   rerequest  requests a review again from every reviewer whose latest approve or change request is not an approval, only owners, members and collaborators, bots and you left out, as `prepare-github-pr-for-review` step 6 picks them, the caller never names one
#   body file: a regular file the caller wrote in a temporary directory, nothing else is read for it
# Prints the URL of what was posted, the thread id once resolved, the threads, or the reviewers requested, nothing when there is none.

set -e

# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  echo "usage: respond-pr-comment.sh react <owner/repo> <number> review|issue <comment id> +1|eyes | reply <owner/repo> <number> <comment id> <body file> | comment <owner/repo> <number> <body file> | resolve <owner/repo> <number> <thread id> | threads <owner/repo> <number> | rerequest <owner/repo> <number>" >&2
  exit 2
}

action="${1:-}"
case "$action" in
  react) [ $# -eq 6 ] || usage ;;
  reply) [ $# -eq 5 ] || usage ;;
  comment | resolve) [ $# -eq 4 ] || usage ;;
  threads | rerequest) [ $# -eq 3 ] || usage ;;
  *) usage ;;
esac
repository="$2"
number="$3"
require_repository "$repository"
require_number "pull request number" "$number"

case "$action" in
  react)
    kind="$4"
    comment_id="$5"
    content="$6"
    case "$kind" in review | issue) ;; *) usage ;; esac
    case "$content" in +1 | eyes) ;; *) usage ;; esac
    require_number "comment id" "$comment_id"
    ;;
  reply)
    comment_id="$4"
    require_number "comment id" "$comment_id"
    read_body_file "$5"
    ;;
  comment)
    read_body_file "$4"
    ;;
  resolve)
    thread_id="$4"
    if ! [[ $thread_id =~ ^PRRT_[A-Za-z0-9_-]{1,100}$ ]]; then
      echo "invalid thread id: $thread_id" >&2
      exit 2
    fi
    ;;
esac

viewer="$(gh api user --jq .login)"
current_state="$(gh api "repos/$repository/pulls/$number" --jq '"\(.state) \(.draft) \(.user.login)"')"
if [ "$current_state" != "open false $viewer" ]; then
  echo "pull request $number is not an open pull request of yours that is ready" >&2
  exit 1
fi

# Fails unless the comment belongs to this pull request, the endpoints take a comment id alone and would accept one of any pull request of the repository.
require_review_comment() {
  local pull_request_url
  pull_request_url="$(gh api "repos/$repository/pulls/comments/$comment_id" --jq .pull_request_url)"
  if [ "$pull_request_url" != "https://api.github.com/repos/$repository/pulls/$number" ]; then
    echo "comment $comment_id is not a review comment of pull request $number" >&2
    exit 1
  fi
}

case "$action" in
  react)
    if [ "$kind" = review ]; then
      require_review_comment
      endpoint="repos/$repository/pulls/comments/$comment_id/reactions"
    else
      issue_url="$(gh api "repos/$repository/issues/comments/$comment_id" --jq .issue_url)"
      if [ "$issue_url" != "https://api.github.com/repos/$repository/issues/$number" ]; then
        echo "comment $comment_id is not a comment of pull request $number" >&2
        exit 1
      fi
      endpoint="repos/$repository/issues/comments/$comment_id/reactions"
    fi
    jq -n --arg content "$content" '{content: $content}' | gh api "$endpoint" --method POST --input - --jq .content
    ;;
  reply)
    require_review_comment
    root="$(gh api "repos/$repository/pulls/comments/$comment_id" --jq '.in_reply_to_id // .id')"
    require_number "thread root" "$root"
    jq -n --arg body "$body" '{body: $body}' | gh api "repos/$repository/pulls/$number/comments/$root/replies" --method POST --input - --jq .html_url
    ;;
  comment)
    jq -n --arg body "$body" '{body: $body}' | gh api "repos/$repository/issues/$number/comments" --method POST --input - --jq .html_url
    ;;
  resolve)
    # The `$` names are GraphQL variables, not shell ones.
    # shellcheck disable=SC2016
    owner="$(gh api graphql -f query='query($id: ID!) { node(id: $id) { ... on PullRequestReviewThread { pullRequest { number repository { nameWithOwner } } } } }' -f "id=$thread_id" --jq '.data.node.pullRequest | "\(.repository.nameWithOwner) \(.number)"')"
    if [ "$owner" != "$repository $number" ]; then
      echo "thread $thread_id is not a thread of pull request $number" >&2
      exit 1
    fi
    # shellcheck disable=SC2016
    gh api graphql -f query='mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { id isResolved } } }' -f "id=$thread_id" --jq '.data.resolveReviewThread.thread | select(.isResolved) | .id'
    ;;
  threads)
    # shellcheck disable=SC2016
    threads="$(gh api graphql -f query='query($owner: String!, $name: String!, $number: Int!) { repository(owner: $owner, name: $name) { pullRequest(number: $number) { reviewThreads(first: 100) { nodes { id isResolved comments(first: 50) { nodes { databaseId author { __typename login } authorAssociation body createdAt path line originalCommit { oid } } } } } } } }' -f "owner=${repository%%/*}" -f "name=${repository##*/}" -F "number=$number" --jq '.data.repository.pullRequest.reviewThreads.nodes')"
    # Only the comments the detector answers and your own, an outsider's text never reaches the caller, so it cannot drive an edit. Bots mostly come as `NONE`, so they go by type.
    jq --arg viewer "$viewer" 'map(.comments.nodes |= map(select(.author != null and (.author.login == $viewer or .author.__typename == "Bot" or (.authorAssociation | IN("OWNER", "MEMBER", "COLLABORATOR"))))))' <<<"$threads"
    ;;
  rerequest)
    # Every reviewer from review bodies and inline comments, a later plain comment keeps an approval. A deleted account has no user and cannot be asked.
    # Two assignments, so a failed read stops the script instead of leaving reviewers out.
    reviews="$(gh api --paginate "repos/$repository/pulls/$number/reviews" --jq '.[] | select(.user != null) | {login: .user.login, type: .user.type, association: .author_association, state, submitted_at}')"
    review_comments="$(gh api --paginate "repos/$repository/pulls/$number/comments" --jq '.[] | select(.user != null) | {login: .user.login, type: .user.type, association: .author_association, state: "COMMENTED", submitted_at: .created_at}')"
    # Only the people the detector answers, GitHub refuses the whole request when one login cannot review, such as an outside contributor or someone who left.
    reviewers="$(printf '%s\n%s\n' "$reviews" "$review_comments" | jq -s -c --arg viewer "$viewer" 'map(select(.type != "Bot" and .login != $viewer and (.association | IN("OWNER", "MEMBER", "COLLABORATOR")))) | group_by(.login) | map(select((map(select(.state == "APPROVED" or .state == "CHANGES_REQUESTED")) | max_by(.submitted_at) | .state) != "APPROVED") | .[0].login)')"
    if ! jq -e 'all(test("^[A-Za-z0-9-]{1,39}$"))' <<<"$reviewers" >/dev/null; then
      echo "unexpected reviewer login: $reviewers" >&2
      exit 1
    fi
    if [ "$reviewers" != "[]" ]; then
      jq -n --argjson reviewers "$reviewers" '{reviewers: $reviewers}' | gh api "repos/$repository/pulls/$number/requested_reviewers" --method POST --input - --jq '.requested_reviewers[].login'
    fi
    ;;
esac
