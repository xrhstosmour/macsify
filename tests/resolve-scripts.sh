#!/bin/bash

# Checks the `resolve-github-prs-comments-watcher` GitHub scripts against a stub
# `gh` on `PATH`, never the real GitHub. The detector reports a pull request of
# the viewer once a member, a collaborator or a bot reviewer commented after the
# viewer, once while its run goes and until it is marked done, never for an
# outsider, the viewer, a deleted author, a bot outside a review thread, a
# resolved thread or a pull request from a fork, keys a cycle without the head so
# its own push does not start it again, caps a pull request after three cycles
# started in a day, failed ones included, claims nothing on a dry run, and
# rejects a scope that could carry a search qualifier. The responder posts only
# on an open pull request of the viewer that is not a draft, only to a comment
# or a thread of that pull request, a reply to the first comment of its thread,
# reads the threads of that pull request without an outsider's comment,
# corrects its description through the pull request endpoint,
# re-requests reviews only of reviewers not approving, never of a bot or the
# viewer, and rejects a bad action, reaction, id or body.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WATCHER="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/watch-pr-comments.sh"
RESPONDER="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/respond-pr-comment.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

failures=0
fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

HEAD_SHA=0123456789012345678901234567890123456789
mkdir -p "$TEST_DIRECTORY/bin"
export XDG_CACHE_HOME="$TEST_DIRECTORY/cache"
export STUB_POSTED="$TEST_DIRECTORY/posted"
STATE="$XDG_CACHE_HOME/resolve-github-prs-comments-watcher"

# The stub answers the search with the nodes the test set, and applies the `--jq`
# filter the way `gh` does. A query that does not leave the merge queue out also
# gets a queued pull request. For the responder it prints what the `--jq` filters
# of the script would, review comment 2 replies to 1 on pull request 5, review
# comment 9 and issue comment 8 are on pull request 6, issue comment 3 on 5, and
# thread `PRRT_five` is on 5. A write keeps its endpoint and standard input.
cat >"$TEST_DIRECTORY/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
  *"--method POST"*) { echo "$2"; cat; } >"$STUB_POSTED"; echo "https://github.com/owner/repo/pull/5#posted" ;;
  *"--method PATCH"*) { echo "$2"; cat; } >"$STUB_POSTED"; echo "https://github.com/owner/repo/pull/5" ;;
  *resolveReviewThread*) echo "mutation $*" >"$STUB_POSTED"; echo "${*: -3:1}" | cut -d= -f2 ;;
  *"reviewThreads(first"*) echo "$*" >"$STUB_POSTED.read"; [ -z "$STUB_READ_FAILS" ] || exit 1; echo '[{"id":"PRRT_five","comments":{"nodes":[{"body":"member","author":{"__typename":"User","login":"author"},"authorAssociation":"MEMBER"},{"body":"outsider","author":{"__typename":"User","login":"stranger"},"authorAssociation":"CONTRIBUTOR"},{"body":"bot","author":{"__typename":"Bot","login":"copilot"},"authorAssociation":"NONE"},{"body":"mine","author":{"__typename":"User","login":"me"},"authorAssociation":"NONE"},{"body":"deleted","author":null,"authorAssociation":"MEMBER"}]}}]' ;;
  *"node(id"*) case "$*" in *id=PRRT_five*) echo "owner/repo 5" ;; *) echo "owner/repo 6" ;; esac ;;
  "api --paginate repos/owner/repo/pulls/5/reviews "*) [ -z "$STUB_READ_FAILS" ] || exit 1; printf '%s\n' "$STUB_REVIEWS" ;;
  "api --paginate repos/owner/repo/pulls/5/comments "*) printf '%s\n' "$STUB_REVIEW_COMMENTS" ;;
  "api user"*) echo me ;;
  "api repos/owner/repo/pulls/5 "*) echo "${STUB_STATE:-open false me}" ;;
  "api repos/owner/repo/pulls/comments/2 --jq .pull_request_url") echo "https://api.github.com/repos/owner/repo/pulls/5" ;;
  "api repos/owner/repo/pulls/comments/2 "*) echo 1 ;;
  "api repos/owner/repo/pulls/comments/"*) echo "https://api.github.com/repos/owner/repo/pulls/6" ;;
  "api repos/owner/repo/issues/comments/3 "*) echo "https://api.github.com/repos/owner/repo/issues/5" ;;
  "api repos/owner/repo/issues/comments/"*) echo "https://api.github.com/repos/owner/repo/issues/6" ;;
  "api graphql"*)
    nodes="${STUB_NODES:-[]}"
    case "$*" in
      *-is:queued*) ;;
      *) nodes="$(jq -c '. + [{number: 9, url: "u", headRefOid: "q", headRefName: "queued", isCrossRepository: false, repository: {nameWithOwner: "owner/repo"}, reviewThreads: {nodes: []}, comments: {nodes: [{author: {__typename: "User", login: "author"}, authorAssociation: "MEMBER", createdAt: "2026-11-05T11:00:00Z"}]}, reviews: {nodes: []}}]' <<<"$nodes")" ;;
    esac
    while [ $# -gt 0 ]; do
      [ "$1" = "--jq" ] && filter="$2"
      shift
    done
    jq -n --argjson nodes "$nodes" '{data: {viewer: {login: "me"}, search: {nodes: $nodes}}}' | jq -r "$filter" ;;
esac
STUB
chmod +x "$TEST_DIRECTORY/bin/gh"
export PATH="$TEST_DIRECTORY/bin:$PATH"

# A comment is [login, time, type, association], the last two default to a person who is a member.
# One search node: threads is a JSON array of [resolved, [comments]], comments and reviews are arrays
# of comments, a review comment takes its body as a fifth field.
node() {
  jq -nc --argjson threads "${1:-[]}" --argjson comments "${2:-[]}" --argjson reviews "${3:-[]}" --argjson fork "${4:-false}" --arg sha "$HEAD_SHA" '
    def actor: {author: (if .[0] == null then null else {__typename: (.[2] // "User"), login: .[0]} end), authorAssociation: (.[3] // "MEMBER")};
    {number: 5, url: "https://github.com/owner/repo/pull/5", headRefOid: $sha, headRefName: "fix/thing", isCrossRepository: $fork, repository: {nameWithOwner: "owner/repo"},
     reviewThreads: {nodes: [$threads[] | {isResolved: .[0], comments: {nodes: [.[1][] | actor + {createdAt: .[1]}]}}]},
     comments: {nodes: [$comments[] | actor + {createdAt: .[1]}]},
     reviews: {nodes: [$reviews[] | actor + {submittedAt: .[1], body: (.[4] // "a note")}]}}'
}
nodes() {
  export STUB_NODES="[$1]"
  rm -rf "$XDG_CACHE_HOME"
}
detect() {
  "$WATCHER" owner --once
}
epoch() {
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s
}
LATE="$(epoch 2026-11-05T11:00:00Z)"
KEY="owner/repo#5+$LATE"
LINE="$KEY $HEAD_SHA https://github.com/owner/repo/pull/5 fix/thing comments"

# A dry run reports and claims nothing.
nodes "$(node '[[false, [["author","2026-11-05T11:00:00Z"]]]]')"
[ -n "$("$WATCHER" owner --once --dry-run)" ] || fail "the detector did not report on a dry run"
[ -n "$("$WATCHER" owner --once --dry-run)" ] || fail "a dry run claimed a pull request"

# A member's thread is reported, claimed, not done, reported again only when the claim expires, never once marked.
[ "$(detect)" = "$LINE" ] || fail "the detector did not report a member's comment in a thread"
[ ! -s "$STATE/seen" ] || fail "the detector recorded a pull request before it was handled"
[ -z "$(detect)" ] || fail "the detector started a run that is still going twice"
echo "$(($(date +%s) - 7300)) $KEY" >"$STATE/claimed"
[ -n "$(detect)" ] || fail "the detector dropped a pull request whose claim expired"
"$WATCHER" --mark "$KEY" || fail "the detector refused to mark a pull request done"
[ -z "$(detect)" ] || fail "the detector reported a handled cycle again"
# The push of the run moves the head, the same comments are still the same cycle.
STUB_NODES="[$(HEAD_SHA=1111111111111111111111111111111111111111 node '[[false, [["author","2026-11-05T11:00:00Z"]]]]')]"
[ -z "$(detect)" ] || fail "the detector started a handled cycle again after its own push"

# A bot reviewer's thread counts, a thread the viewer answered last or that is resolved does not.
nodes "$(node '[[false, [["copilot","2026-11-05T11:00:00Z","Bot","NONE"]]]]')"
[ "$(detect)" = "$LINE" ] || fail "the detector missed a bot reviewer's thread"
nodes "$(node '[[false, [["author","2026-11-05T10:00:00Z"],["me","2026-11-05T11:00:00Z"]]], [true, [["author","2026-11-05T11:00:00Z"]]]]')"
[ -z "$(detect)" ] || fail "the detector reported a thread the viewer answered last or a resolved thread"

# Outsiders and deleted authors never count.
nodes "$(node '[[false, [["stranger","2026-11-05T11:00:00Z","User","NONE"]]], [false, [[null,"2026-11-05T11:00:00Z"]]]]' '[["stranger","2026-11-05T11:00:00Z","User","CONTRIBUTOR"]]')"
[ -z "$(detect)" ] || fail "the detector reported an outsider or a deleted author"

# A comment on the pull request and a review body count after the viewer's last comment, a bot's does not.
nodes "$(node '[]' '[["me","2026-11-05T10:00:00Z"],["author","2026-11-05T11:00:00Z","User","COLLABORATOR"]]')"
[ "$(detect)" = "$LINE" ] || fail "the detector missed a collaborator's comment on the pull request"
nodes "$(node '[]' '[["me","2026-11-05T10:00:00Z"]]' '[["author","2026-11-05T11:00:00Z"]]')"
[ "$(detect)" = "$LINE" ] || fail "the detector missed a review body"
nodes "$(node '[]' '[["author","2026-11-05T10:00:00Z"],["me","2026-11-05T11:00:00Z"]]' '[["author","2026-11-05T09:00:00Z"],["author","2026-11-05T11:30:00Z","User","MEMBER",""]]')"
[ -z "$(detect)" ] || fail "the detector reported comments the viewer answered or an empty review body"
nodes "$(node '[]' '[["deploy","2026-11-05T11:00:00Z","Bot","NONE"]]' '[["copilot","2026-11-05T11:00:00Z","Bot","NONE"]]')"
[ -z "$(detect)" ] || fail "the detector reported a bot outside a review thread"

# The newest comment keys the cycle, a pull request from a fork and the merge queue stay out.
nodes "$(node '[[false, [["author","2026-11-05T09:00:00Z"]]]]' '[["author","2026-11-05T11:00:00Z"]]')"
[ "$(detect)" = "$LINE" ] || fail "the detector did not key the cycle on the newest comment"
nodes "$(node '[[false, [["author","2026-11-05T11:00:00Z"]]]]' '[]' '[]' true)"
[ -z "$(detect)" ] || fail "the detector reported a pull request from a fork"
nodes ""
[ -z "$(detect)" ] || fail "the detector reported a pull request in the merge queue"

# Three cycles started in a day cap the pull request, failed ones included, reported once per head, an old cycle does not count, and a third cycle still going is not capped.
nodes "$(node '[[false, [["copilot","2026-11-05T11:00:00Z","Bot","NONE"]]]]')"
mkdir -p "$STATE"
for cycle in 1 2 3; do
  echo "$(date +%s) owner/repo#5+$cycle" >>"$STATE/claimed"
done
[ "$(detect)" = "owner/repo#5@$HEAD_SHA $HEAD_SHA https://github.com/owner/repo/pull/5 fix/thing capped" ] || fail "the detector did not cap a pull request after three cycles"
[ -z "$(detect)" ] || fail "the detector reported a capped head twice"
echo "$(($(date +%s) - 90000)) owner/repo#5+1" >"$STATE/claimed"
[ "$(detect)" = "$LINE" ] || fail "the detector counted a cycle older than a day"
echo "$(date +%s) owner/repo#5+1" >>"$STATE/claimed"
echo "$(date +%s) owner/repo#5+2" >>"$STATE/claimed"
[ -z "$(detect)" ] || fail "the detector capped a third cycle that is still going"
unset STUB_NODES

"$WATCHER" --mark 'owner/repo#5@abc' >/dev/null 2>&1 && fail "the detector marked a malformed key"
"$WATCHER" --mark "owner/repo#5@$HEAD_SHA+1" >/dev/null 2>&1 && fail "the detector marked a key with a head and an epoch"
"$WATCHER" --mark "$(printf 'owner/repo#5@%s\nx' "$HEAD_SHA")" >/dev/null 2>&1 && fail "the detector marked a key with a newline"
"$WATCHER" "$(printf 'owner\nauthor:someone')" --once >/dev/null 2>&1 && fail "the detector accepted a scope with a newline"
"$WATCHER" 'owner author:someone' --once >/dev/null 2>&1 && fail "the detector accepted a scope with a search qualifier"
"$WATCHER" owner --interval ten --once >/dev/null 2>&1 && fail "the detector accepted a non numeric interval"

# The responder.
echo "Fixed, thanks." >"$TEST_DIRECTORY/body.txt"
respond() {
  rm -f "$STUB_POSTED"
  "$RESPONDER" "$@" >/dev/null 2>&1
}
respond react owner/repo 5 review 2 eyes || fail "the responder refused a reaction to a review comment of the pull request"
[ "$(head -1 "$STUB_POSTED")" = "repos/owner/repo/pulls/comments/2/reactions" ] || fail "the responder reacted on another endpoint"
[ "$(tail -n +2 "$STUB_POSTED" | jq -r .content)" = eyes ] || fail "the responder sent another reaction"
respond react owner/repo 5 issue 3 +1 || fail "the responder refused a reaction to a comment of the pull request"
respond react owner/repo 5 review 9 eyes && fail "the responder reacted to a review comment of another pull request"
respond react owner/repo 5 issue 8 +1 && fail "the responder reacted to a comment of another pull request"
respond react owner/repo 5 review 2 heart && fail "the responder sent a reaction it was not built for"
respond react owner/repo 5 commit 2 eyes && fail "the responder accepted an unknown comment kind"
respond reply owner/repo 5 2 "$TEST_DIRECTORY/body.txt" || fail "the responder refused a reply in a thread of the pull request"
[ "$(head -1 "$STUB_POSTED")" = "repos/owner/repo/pulls/5/comments/1/replies" ] || fail "the responder did not reply to the first comment of the thread"
[ "$(tail -n +2 "$STUB_POSTED" | jq -r .body)" = "Fixed, thanks." ] || fail "the responder changed the body"
respond reply owner/repo 5 9 "$TEST_DIRECTORY/body.txt" && fail "the responder replied in a thread of another pull request"
respond comment owner/repo 5 "$TEST_DIRECTORY/body.txt" || fail "the responder refused a comment on the pull request"
[ "$(head -1 "$STUB_POSTED")" = "repos/owner/repo/issues/5/comments" ] || fail "the responder commented on another endpoint"
respond comment owner/repo 5 "$TESTS_SCRIPT_DIRECTORY/resolve-scripts.sh" && fail "the responder posted a file outside a temporary directory"
respond body owner/repo 5 "$TEST_DIRECTORY/body.txt" || fail "the responder refused to correct the description of the pull request"
[ "$(head -1 "$STUB_POSTED")" = "repos/owner/repo/pulls/5" ] || fail "the responder corrected the description on another endpoint"
[ "$(tail -n +2 "$STUB_POSTED" | jq -r .body)" = "Fixed, thanks." ] || fail "the responder changed the description it was given"
respond body owner/repo 5 "$TESTS_SCRIPT_DIRECTORY/resolve-scripts.sh" && fail "the responder took a description outside a temporary directory"
respond resolve owner/repo 5 PRRT_five || fail "the responder refused to resolve a thread of the pull request"
grep -q 'id=PRRT_five' "$STUB_POSTED" || fail "the responder resolved another thread"
respond resolve owner/repo 5 PRRT_six && fail "the responder resolved a thread of another pull request"
respond resolve owner/repo 5 'PRRT_five extra' && fail "the responder accepted a thread id with a space"
respond resolve owner/repo 5 MDQ6VXNlcjE= && fail "the responder accepted an id that is not a review thread"
for state in "open true me" "closed false me" "open false someone"; do
  STUB_STATE="$state" respond comment owner/repo 5 "$TEST_DIRECTORY/body.txt" && fail "the responder posted on a pull request that is $state"
  STUB_STATE="$state" respond body owner/repo 5 "$TEST_DIRECTORY/body.txt" && fail "the responder corrected the description of a pull request that is $state"
done
[ ! -e "$STUB_POSTED" ] || fail "the responder wrote something it refused"
respond comment 'owner/repo extra' 5 "$TEST_DIRECTORY/body.txt" && fail "the responder accepted a repository with a space"
respond comment owner/repo x "$TEST_DIRECTORY/body.txt" && fail "the responder accepted a non numeric pull request"
"$RESPONDER" threads owner/repo 5 2>/dev/null | grep -q PRRT_five || fail "the responder did not print the threads"
[ "$("$RESPONDER" threads owner/repo 5 2>/dev/null | jq -r '[.[].comments.nodes[].body] | join(" ")')" = "member bot mine" ] || fail "the responder printed a comment of an outsider or a deleted author"
STUB_READ_FAILS=1 respond threads owner/repo 5 && fail "the responder printed threads after a failed read"
grep -q 'owner=owner -f name=repo -F number=5' "$STUB_POSTED.read" || fail "the responder read the threads of another pull request"
respond threads owner/repo 5 extra && fail "the responder accepted an argument too many for the threads"
respond merge owner/repo 5 "$TEST_DIRECTORY/body.txt" && fail "the responder accepted an unknown action"

# A review is asked again of the members and collaborators not approving by their latest approve or change request, never of a bot, an outsider or the viewer.
export STUB_REVIEWS='{"login":"alice","type":"User","association":"MEMBER","state":"APPROVED","submitted_at":"2026-11-05T10:00:00Z"}
{"login":"alice","type":"User","association":"MEMBER","state":"COMMENTED","submitted_at":"2026-11-05T11:00:00Z"}
{"login":"bob","type":"User","association":"COLLABORATOR","state":"APPROVED","submitted_at":"2026-11-05T10:00:00Z"}
{"login":"bob","type":"User","association":"COLLABORATOR","state":"CHANGES_REQUESTED","submitted_at":"2026-11-05T11:00:00Z"}
{"login":"linter","type":"Bot","association":"NONE","state":"COMMENTED","submitted_at":"2026-11-05T10:00:00Z"}
{"login":"me","type":"User","association":"OWNER","state":"COMMENTED","submitted_at":"2026-11-05T10:00:00Z"}'
export STUB_REVIEW_COMMENTS='{"login":"carol","type":"User","association":"OWNER","state":"COMMENTED","submitted_at":"2026-11-05T10:00:00Z"}
{"login":"outsider","type":"User","association":"CONTRIBUTOR","state":"COMMENTED","submitted_at":"2026-11-05T10:00:00Z"}
{"login":"linter","type":"Bot","association":"NONE","state":"COMMENTED","submitted_at":"2026-11-05T10:00:00Z"}'
respond rerequest owner/repo 5 || fail "the responder refused to re-request reviews"
[ "$(head -1 "$STUB_POSTED")" = "repos/owner/repo/pulls/5/requested_reviewers" ] || fail "the responder re-requested on another endpoint"
[ "$(tail -n +2 "$STUB_POSTED" | jq -c .reviewers)" = '["bob","carol"]' ] || fail "the responder re-requested from the wrong reviewers"
STUB_READ_FAILS=1 respond rerequest owner/repo 5 && fail "the responder went on after failing to read the reviews"
[ ! -e "$STUB_POSTED" ] || fail "the responder re-requested after failing to read the reviews"
STUB_REVIEW_COMMENTS='' STUB_REVIEWS='{"login":"alice","type":"User","association":"MEMBER","state":"APPROVED","submitted_at":"2026-11-05T10:00:00Z"}' respond rerequest owner/repo 5 || fail "the responder failed with every reviewer approving"
[ ! -e "$STUB_POSTED" ] || fail "the responder re-requested with every reviewer approving"
STUB_STATE="open true me" respond rerequest owner/repo 5 && fail "the responder re-requested on a draft"
respond rerequest owner/repo 5 bob && fail "the responder accepted a reviewer named by the caller"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "PASS: resolve comments watcher scripts"
