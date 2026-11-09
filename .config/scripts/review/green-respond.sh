#!/usr/bin/env bash
# The GitHub writes of the `green-github-prs-watcher` skill on a pull request of yours: a reaction, a thread reply, a pull request comment, resolving a thread, correcting the description and re-requesting reviews and starting a test workflow by `workflow_dispatch`, plus the one read that needs GraphQL, the review threads.
# Allowed in claude/settings.json by its path, so the script validates every input itself and calls one fixed endpoint per action, never a caller supplied one.
# Only an open pull request you opened that is not a draft, and only a comment or a thread of that pull request, so a comment id read from somewhere else never lands on another one.
#
# Usage: green-respond.sh react <owner/repo> <number> review|issue <comment id> +1|eyes
#        green-respond.sh reply <owner/repo> <number> <comment id> <body file>
#        green-respond.sh comment <owner/repo> <number> <body file>
#        green-respond.sh resolve <owner/repo> <number> <thread id>
#        green-respond.sh body <owner/repo> <number> <body file>
#        green-respond.sh threads <owner/repo> <number>
#        green-respond.sh rerequest <owner/repo> <number>
#        green-respond.sh dispatch <owner/repo> <number> <head sha> <workflow file>
#   react    `review` for a comment in a review thread, `issue` for a comment on the pull request
#   reply    answers in the thread of the comment, the replies endpoint takes the first comment of the thread, so that is where it is sent
#   comment  a comment on the pull request, the answer to a comment outside a thread or to a review body
#   resolve  the GraphQL id of the review thread, `PRRT_...`
#   body     replaces the description of the pull request, GitHub keeps the one before in the edit history of the description
#   threads  prints the first 100 review threads, 50 comments each, as JSON, only the comments of owners, members, collaborators, bots and you, the read `resolve-github-pr-comments` makes with `gh api graphql -f`, which waits for a prompt
#   rerequest  requests a review again from every reviewer whose latest approve or change request is not an approval, only owners, members and collaborators, bots and you left out, as `prepare-github-pr-for-review` step 6 picks them, the caller never names one
#   dispatch   starts the workflow file of `.github/workflows` on the pull request branch, only at the head the caller saw, only when it has `workflow_dispatch`, and neither it, a workflow or local action it calls, nor a workflow chained by `workflow_run` or `create` at the head or on the default branch names a deploy, release, publish, promotion, production, migration or environment, and never for a pull request that changes `.github`, whose workflows would run with the repository's secrets. A tree that mentions a deploy exits 5, see `require_test_only_tree` in `lib.sh` for what can be trusted
#   body file: a regular file the caller wrote in a temporary directory, nothing else is read for it
# Prints the URL of what was posted, the thread id once resolved, the threads, or the reviewers requested, nothing when there is none.

set -e

# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  echo "usage: green-respond.sh react <owner/repo> <number> review|issue <comment id> +1|eyes | reply <owner/repo> <number> <comment id> <body file> | comment <owner/repo> <number> <body file> | resolve <owner/repo> <number> <thread id> | body <owner/repo> <number> <body file> | threads <owner/repo> <number> | rerequest <owner/repo> <number> | dispatch <owner/repo> <number> <head sha> <workflow file>" >&2
  exit 2
}

action="${1:-}"
case "$action" in
  react) [ $# -eq 6 ] || usage ;;
  reply) [ $# -eq 5 ] || usage ;;
  comment | resolve | body) [ $# -eq 4 ] || usage ;;
  dispatch) [ $# -eq 5 ] || usage ;;
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
  comment | body)
    read_body_file "$4"
    ;;
  resolve)
    thread_id="$4"
    if ! [[ $thread_id =~ ^PRRT_[A-Za-z0-9_-]{1,100}$ ]]; then
      echo "invalid thread id: $thread_id" >&2
      exit 2
    fi
    ;;
  dispatch)
    head_sha="$4"
    workflow="$5"
    require_sha "head" "$head_sha"
    require_workflow_file "$workflow"
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
  body)
    jq -n --arg body "$body" '{body: $body}' | gh api "repos/$repository/pulls/$number" --method PATCH --input - --jq .html_url
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
  dispatch)
    # A trust line names the repository the reads below go to, and only the workflow started here.
    trust_repository="$repository"
    trust_workflow=".github/workflows/$workflow"
    trust_ref="$head_sha"
    # The run starts at the branch, so the branch must still be at the head the caller checked, in this repository and not a fork.
    pull_request="$(gh api "repos/$repository/pulls/$number" --jq '"\(.head.sha) \(.head.repo.full_name) \(.changed_files) \(.head.ref)"')"
    read -r current_head head_repository changed_files ref <<<"$pull_request"
    if [ "$current_head" != "$head_sha" ] || [ "$head_repository" != "$repository" ]; then
      echo "pull request $number is not at $head_sha in $repository" >&2
      exit 1
    fi
    require_branch "branch" "$ref"
    # The files endpoint lists at most 3000, a longer list could hide a workflow change.
    require_number "changed files" "$changed_files"
    if [ "$changed_files" -gt 3000 ]; then
      echo "pull request $number changes more files than can be checked, trigger its tests by hand" >&2
      exit 1
    fi
    workflow_changes="$(gh api --paginate "repos/$repository/pulls/$number/files?per_page=100" --jq '.[].filename | select(startswith(".github/"))')"
    if [ -n "$workflow_changes" ]; then
      echo "the pull request changes .github, trigger its tests by hand" >&2
      exit 1
    fi
    content="$(gh api "repos/$repository/contents/.github/workflows/$workflow?ref=$head_sha" -H 'Accept: application/vnd.github.raw+json')"
    if ! trigger_block "$content" | grep -qE '(^|[^a-z_])workflow_dispatch([^a-z_]|$)'; then
      echo "$workflow has no workflow_dispatch trigger" >&2
      exit 1
    fi
    read_repository_file() { gh api "repos/$repository/contents/$2?ref=$1" -H 'Accept: application/vnd.github.raw+json'; }
    list_workflows() { gh api "repos/$repository/contents/.github/workflows?ref=$1" --jq '.[] | select(.type == "file") | .name'; }
    require_test_only_tree "$head_sha" ".github/workflows/$workflow" "$content"
    # A workflow chained after the run, or after any other, would run next to the tests. A `workflow_run` runs the file of the default branch, so that branch is read too, by its commit so no name lands in a URL.
    require_no_deploy_started "$head_sha" ""
    default_branch="$(gh api "repos/$repository" --jq .default_branch)"
    require_branch "default branch" "$default_branch"
    default_sha="$(gh api "repos/$repository/commits/$(jq -rn --arg branch "$default_branch" '$branch | @uri')" --jq .sha)"
    require_sha "default branch commit" "$default_sha"
    require_no_deploy_started "$default_sha" ""
    # The reads above took a while, a push in the meantime would run workflows nobody checked.
    if [ "$(gh api "repos/$repository/pulls/$number" --jq .head.sha)" != "$head_sha" ]; then
      echo "pull request $number moved from $head_sha, trigger its tests by hand" >&2
      exit 1
    fi
    jq -n --arg ref "$ref" '{ref: $ref}' | gh api "repos/$repository/actions/workflows/$workflow/dispatches" --method POST --input - >/dev/null
    echo "$workflow"
    ;;
esac
