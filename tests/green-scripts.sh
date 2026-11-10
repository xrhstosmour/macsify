#!/bin/bash

# Checks the `green-github-prs-watcher` GitHub scripts against a stub
# `gh` on `PATH`, never the real GitHub. The detector reports a pull request of
# the viewer once a member, a collaborator or a bot reviewer commented after the
# viewer, once while its run goes and until it is marked done, never for an
# outsider, the viewer, a deleted author, a bot outside a review thread, a
# resolved thread or a pull request from a fork, keys a cycle without the head so
# its own push does not start it again, holds a pull request while any of its
# runs goes, caps it after three cycles
# started in a day, failed ones included, claims nothing on a dry run, and
# rejects a scope that could carry a search qualifier. The responder posts only
# on an open pull request of the viewer that is not a draft, only to a comment
# or a thread of that pull request, a reply to the first comment of its thread,
# reads the threads of that pull request without an outsider's comment,
# corrects its description through the pull request endpoint,
# re-requests reviews only of reviewers not approving, never of a bot or the
# viewer, dispatches a test workflow only at the head the caller saw, never
# for a fork, a change to `.github` or a workflow that could deploy, and rejects
# a bad action, reaction, id or body.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WATCHER="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/watch-green-prs.sh"
RESPONDER="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/green-respond.sh"
TRUST_SCRIPT="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/green-trust.sh"

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
# The trust file lives under `HOME`, your own must never approve a test tree.
export HOME="$TEST_DIRECTORY/home"
TRUST_FILE="$HOME/.config/green-github-prs-watcher/trusted-workflows"
export STUB_POSTED="$TEST_DIRECTORY/posted"
STATE="$XDG_CACHE_HOME/green-github-prs-watcher"

# The stub answers the search with the nodes the test set, and applies the `--jq`
# filter the way `gh` does. A query that does not leave the merge queue out also
# gets a queued pull request. For the responder it prints what the `--jq` filters
# of the script would, review comment 2 replies to 1 on pull request 5, review
# comment 9 and issue comment 8 are on pull request 6, issue comment 3 on 5, and
# thread `PRRT_five` is on 5. A write keeps its endpoint and standard input.
# The contents endpoint serves `STUB_TREE/<ref>/<path>`, a folder as the JSON
# listing GitHub sends, the default branch `main` is at commit 2222.
cat >"$TEST_DIRECTORY/bin/gh" <<'STUB'
#!/bin/bash
filter=""
arguments=("$@")
for index in "${!arguments[@]}"; do
  [ "${arguments[index]}" = --jq ] && filter="${arguments[index + 1]}"
done
apply() {
  if [ -n "$filter" ]; then jq -r "$filter"; else cat; fi
}
case "$*" in
  *"--method POST"*) { echo "$2"; cat; } >"$STUB_POSTED"; echo "https://github.com/owner/repo/pull/5#posted" ;;
  *"--method PATCH"*) { echo "$2"; cat; } >"$STUB_POSTED"; echo "https://github.com/owner/repo/pull/5" ;;
  *resolveReviewThread*) echo "mutation $*" >"$STUB_POSTED"; echo "${*: -3:1}" | cut -d= -f2 ;;
  *"reviewThreads(first"*) echo "$*" >"$STUB_POSTED.read"; [ -z "$STUB_READ_FAILS" ] || exit 1; echo '[{"id":"PRRT_five","comments":{"nodes":[{"body":"member","author":{"__typename":"User","login":"author"},"authorAssociation":"MEMBER"},{"body":"outsider","author":{"__typename":"User","login":"stranger"},"authorAssociation":"CONTRIBUTOR"},{"body":"bot","author":{"__typename":"Bot","login":"copilot"},"authorAssociation":"NONE"},{"body":"mine","author":{"__typename":"User","login":"me"},"authorAssociation":"NONE"},{"body":"deleted","author":null,"authorAssociation":"MEMBER"}]}}]' ;;
  *"node(id"*) case "$*" in *id=PRRT_five*) echo "owner/repo 5" ;; *) echo "owner/repo 6" ;; esac ;;
  "api --paginate repos/owner/repo/pulls/5/reviews "*) [ -z "$STUB_READ_FAILS" ] || exit 1; printf '%s\n' "$STUB_REVIEWS" ;;
  "api --paginate repos/owner/repo/pulls/5/comments "*) printf '%s\n' "$STUB_REVIEW_COMMENTS" ;;
  "api user"*) echo me ;;
  "api repos/owner/repo/pulls/5 --jq .head.sha") echo "${STUB_LATER_HEAD:-0123456789012345678901234567890123456789}" ;;
  "api repos/owner/repo/pulls/5 --jq "*head.sha*) echo "${STUB_HEAD:-0123456789012345678901234567890123456789 owner/repo 2 fix/thing}" ;;
  "api --paginate repos/owner/repo/pulls/5/files"*) [ -z "$STUB_READ_FAILS" ] || exit 1; printf '%s\n' "${STUB_FILES:-a.txt}" | jq -R '[{filename: .}]' | apply ;;
  "api repos/owner/repo --jq .default_branch") echo main ;;
  "api repos/owner/repo/commits/main --jq .sha") echo 2222222222222222222222222222222222222222 ;;
  "api repos/owner/repo/contents/"*)
    path="${2#repos/owner/repo/contents/}"
    file="$STUB_TREE/${path##*\?ref=}/${path%%\?ref=*}"
    if [ -n "$STUB_LIST_FAILS" ] && [ -d "$file" ]; then
      exit 1
    elif [ -d "$file" ]; then
      for entry in "$file"/*; do
        [ -e "$entry" ] || continue
        jq -n --arg name "${entry##*/}" --arg type "$([ -d "$entry" ] && echo dir || echo file)" '{name: $name, type: $type}'
      done | jq -s . | apply
    elif [ -f "$file" ]; then
      cat "$file"
    else
      exit 1
    fi ;;
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
# of comments, a review comment takes its body as a fifth field. `COMMITS` is a JSON array of
# commit subjects, `MERGEABLE` the conflict state and `ROLLUP` the checks of the head.
node() {
  jq -nc --argjson threads "${1:-[]}" --argjson comments "${2:-[]}" --argjson reviews "${3:-[]}" --argjson fork "${4:-false}" --arg sha "$HEAD_SHA" \
    --argjson commits "${COMMITS:-[\"Add the thing\"]}" --arg mergeable "${MERGEABLE:-MERGEABLE}" --argjson rollup "${ROLLUP:-null}" '
    def actor: {author: (if .[0] == null then null else {__typename: (.[2] // "User"), login: .[0]} end), authorAssociation: (.[3] // "MEMBER")};
    {number: 5, url: "https://github.com/owner/repo/pull/5", headRefOid: $sha, headRefName: "fix/thing", isCrossRepository: $fork, repository: {nameWithOwner: "owner/repo"},
     mergeable: $mergeable, commits: {nodes: [$commits[] | {commit: {messageHeadline: .}}]}, latest: {nodes: [{commit: {statusCheckRollup: $rollup}}]},
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
# Two finished cycles and a third that failed, its claim expired without a mark.
for cycle in 1 2; do
  echo "$(date +%s) owner/repo#5+$cycle" >>"$STATE/claimed"
  echo "$(date +%s) owner/repo#5+$cycle" >>"$STATE/seen"
done
echo "$(($(date +%s) - 7300)) owner/repo#5+3" >>"$STATE/claimed"
[ "$(detect)" = "owner/repo#5@$HEAD_SHA $HEAD_SHA https://github.com/owner/repo/pull/5 fix/thing capped" ] || fail "the detector did not cap a pull request after three cycles"
[ -z "$(detect)" ] || fail "the detector reported a capped head twice"
echo "$(($(date +%s) - 90000)) owner/repo#5+1" >"$STATE/claimed"
[ "$(detect)" = "$LINE" ] || fail "the detector counted a cycle older than a day"
echo "$(date +%s) owner/repo#5+1" >>"$STATE/claimed"
echo "$(date +%s) owner/repo#5+2" >>"$STATE/claimed"
[ -z "$(detect)" ] || fail "the detector capped a third cycle that is still going"

# Without comments, a leftover fixup or a conflict is reported to prepare, keyed on the head, once.
PREPARE="owner/repo#5~$HEAD_SHA $HEAD_SHA https://github.com/owner/repo/pull/5 fix/thing prepare"
nodes "$(COMMITS='["Add the thing","fixup! Add the thing"]' node)"
[ "$(detect)" = "$PREPARE" ] || fail "the detector did not report a leftover fixup commit"
"$WATCHER" --mark "owner/repo#5~$HEAD_SHA" || fail "the detector refused to mark a prepare key done"
[ -z "$(detect)" ] || fail "the detector reported a prepared head again"
nodes "$(MERGEABLE=CONFLICTING node)"
[ "$(detect)" = "$PREPARE" ] || fail "the detector did not report a conflict with the base"
nodes "$(MERGEABLE=UNKNOWN node)"
[ -z "$(detect)" ] || fail "the detector reported a pull request whose conflict state is still unknown"

# A failed check counts once every check of the head finished, a failure on the next head starts the next cycle.
FAILED='{"state":"FAILURE","contexts":{"nodes":[{"status":"COMPLETED"},{"state":"FAILURE"}]}}'
CHECKS="owner/repo#5=$HEAD_SHA $HEAD_SHA https://github.com/owner/repo/pull/5 fix/thing checks"
nodes "$(ROLLUP="$FAILED" node)"
[ "$(detect)" = "$CHECKS" ] || fail "the detector did not report a failed check"
"$WATCHER" --mark "owner/repo#5=$HEAD_SHA"
STUB_NODES="[$(HEAD_SHA=1111111111111111111111111111111111111111 ROLLUP="$FAILED" node)]"
[ "$(detect)" = "owner/repo#5=1111111111111111111111111111111111111111 1111111111111111111111111111111111111111 https://github.com/owner/repo/pull/5 fix/thing checks" ] || fail "the detector did not report a failed check on the pushed head"
# A conflict after the failed checks of the same head were handled is still prepared.
nodes "$(ROLLUP="$FAILED" node)"
[ "$(detect)" = "$CHECKS" ] || fail "the detector did not report a failed check"
"$WATCHER" --mark "owner/repo#5=$HEAD_SHA"
STUB_NODES="[$(MERGEABLE=CONFLICTING ROLLUP="$FAILED" node)]"
[ "$(detect)" = "$PREPARE" ] || fail "the detector hid a conflict behind the handled checks of the same head"
nodes "$(ROLLUP='{"state":"FAILURE","contexts":{"pageInfo":{"hasNextPage":true},"nodes":[{"state":"FAILURE"}]}}' node)"
[ -z "$(detect)" ] || fail "the detector reported failed checks with a page of checks unread"
nodes "$(ROLLUP='{"state":"FAILURE","contexts":{"nodes":[{"state":"FAILURE"},{"status":"IN_PROGRESS"}]}}' node)"
[ -z "$(detect)" ] || fail "the detector reported a failed check while another still runs"
nodes "$(ROLLUP='{"state":"FAILURE","contexts":{"nodes":[{"state":"FAILURE"},{"state":"PENDING"}]}}' node)"
[ -z "$(detect)" ] || fail "the detector reported a failed check while a status is pending"
nodes "$(ROLLUP='{"state":"SUCCESS","contexts":{"nodes":[{"status":"COMPLETED"}]}}' node)"
[ -z "$(detect)" ] || fail "the detector reported a green pull request"

# Comments come first, the run handles the rest, and the cap counts every reason.
nodes "$(COMMITS='["fixup! Add the thing"]' ROLLUP="$FAILED" node '[[false, [["author","2026-11-05T11:00:00Z"]]]]')"
[ "$(detect)" = "$LINE" ] || fail "the detector did not report comments before the rest"
# A run still going holds the pull request, comments marked done fall through to a conflict or a failed check, an approval nobody answers never hides them.
nodes "$(MERGEABLE=CONFLICTING node '[]' '[]' '[["author","2026-11-05T11:00:00Z","User","MEMBER","Approving"]]')"
[ "$(detect)" = "$LINE" ] || fail "the detector did not report an approval body as comments"
[ -z "$(detect)" ] || fail "the detector started a second run on a pull request whose comments run is going"
"$WATCHER" --mark "$KEY"
[ "$(detect)" = "$PREPARE" ] || fail "the detector hid a conflict behind handled comments"
# A comments run that answered its threads and pushed a fixup, or that gets a newer comment, still holds the pull request until it is marked.
nodes "$(COMMITS='["Add the thing","fixup! Add the thing"]' node)"
mkdir -p "$STATE"
echo "$(date +%s) $KEY" >"$STATE/claimed"
[ -z "$(detect)" ] || fail "the detector started a prepare cycle on the fixup of a comments run still going"
STUB_NODES="[$(node '[[false, [["author","2026-11-05T12:00:00Z"]]]]')]"
[ -z "$(detect)" ] || fail "the detector started a second comments run while one is going"
"$WATCHER" --mark "$KEY"
STUB_NODES="[$(COMMITS='["Add the thing","fixup! Add the thing"]' node)]"
[ "$(detect)" = "$PREPARE" ] || fail "the detector kept holding a pull request whose run was marked done"
nodes "$(ROLLUP="$FAILED" node '[]' '[]' '[["author","2026-11-05T11:00:00Z"]]')"
"$WATCHER" --mark "$KEY"
[ "$(detect)" = "$CHECKS" ] || fail "the detector hid a failed check behind handled comments"
nodes "$(COMMITS='["fixup! Add the thing"]' ROLLUP="$FAILED" node)"
"$WATCHER" --mark "owner/repo#5~$HEAD_SHA"
[ "$(detect)" = "$CHECKS" ] || fail "the detector hid a failed check behind a prepared head"
nodes "$(ROLLUP="$FAILED" node)"
mkdir -p "$STATE"
echo "$(date +%s) owner/repo#5+1" >>"$STATE/claimed"
echo "$(date +%s) owner/repo#5=2222222222222222222222222222222222222222" >>"$STATE/claimed"
echo "$(date +%s) owner/repo#5~3333333333333333333333333333333333333333" >>"$STATE/claimed"
cp "$STATE/claimed" "$STATE/seen"
[ "$(detect)" = "owner/repo#5@$HEAD_SHA $HEAD_SHA https://github.com/owner/repo/pull/5 fix/thing capped" ] || fail "the detector did not count prepare and checks cycles for the cap"
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
respond comment owner/repo 5 "$TESTS_SCRIPT_DIRECTORY/green-scripts.sh" && fail "the responder posted a file outside a temporary directory"
respond body owner/repo 5 "$TEST_DIRECTORY/body.txt" || fail "the responder refused to correct the description of the pull request"
[ "$(head -1 "$STUB_POSTED")" = "repos/owner/repo/pulls/5" ] || fail "the responder corrected the description on another endpoint"
[ "$(tail -n +2 "$STUB_POSTED" | jq -r .body)" = "Fixed, thanks." ] || fail "the responder changed the description it was given"
respond body owner/repo 5 "$TESTS_SCRIPT_DIRECTORY/green-scripts.sh" && fail "the responder took a description outside a temporary directory"
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

# A test workflow is dispatched only at the head the caller saw, on its branch, never one that could deploy.
DEFAULT_SHA=2222222222222222222222222222222222222222
export STUB_TREE="$TEST_DIRECTORY/tree"
TEST_WORKFLOW=$'on:\n  workflow_dispatch:\njobs:\n  test:\n    steps:\n      - run: make test'
# Writes a file of the commit, `tree_file <ref> <path> <content>`.
tree_file() {
  mkdir -p "$(dirname "$STUB_TREE/$1/$2")"
  printf '%s\n' "$3" >"$STUB_TREE/$1/$2"
}
# Starts both commits over, the head with the test workflow, or the one given, and the default branch with no workflow.
tree_reset() {
  rm -rf "$STUB_TREE"
  mkdir -p "$STUB_TREE/$DEFAULT_SHA/.github/workflows"
  tree_file "$HEAD_SHA" .github/workflows/tests.yaml "${1:-$TEST_WORKFLOW}"
}
# Fails unless the dispatch is refused and nothing is posted.
dispatch_refused() {
  respond dispatch owner/repo 5 "$HEAD_SHA" tests.yaml && fail "the responder dispatched $1"
  [ ! -e "$STUB_POSTED" ] || fail "the responder posted after refusing $1"
}
# Fails unless the dispatch is refused for a deploy, exit 5, and nothing is posted.
dispatch_deploy_refused() {
  respond dispatch owner/repo 5 "$HEAD_SHA" tests.yaml
  [ $? -eq 5 ] || fail "the responder did not exit 5 on $1"
  [ ! -e "$STUB_POSTED" ] || fail "the responder posted after refusing $1"
}
tree_reset
respond dispatch owner/repo 5 "$HEAD_SHA" tests.yaml || fail "the responder refused to dispatch a test workflow"
[ "$(head -1 "$STUB_POSTED")" = "repos/owner/repo/actions/workflows/tests.yaml/dispatches" ] || fail "the responder dispatched on another endpoint"
[ "$(tail -n +2 "$STUB_POSTED" | jq -c .)" = '{"ref":"fix/thing"}' ] || fail "the responder dispatched on another ref"
respond dispatch owner/repo 5 1111111111111111111111111111111111111111 tests.yaml && fail "the responder dispatched at a head the pull request moved from"
STUB_LATER_HEAD=1111111111111111111111111111111111111111 dispatch_refused "for a pull request that moved while the workflows were read"
STUB_HEAD="$HEAD_SHA fork/repo 2 fix/thing" dispatch_refused "for a pull request from a fork"
STUB_HEAD="$HEAD_SHA owner/repo 3001 fix/thing" dispatch_refused "for a pull request with more files than it can check"
STUB_FILES=$'a.txt\n.github/workflows/tests.yaml' dispatch_refused "for a pull request that changes .github"
STUB_READ_FAILS=1 dispatch_refused "after failing to read the files"
tree_reset $'on:\n  push:\njobs:\n  workflow_dispatch: {}'
dispatch_refused "a workflow without a workflow_dispatch trigger"
for word in "run: ./deploy" "environment: production" "run: make release" "run: rails db:migrate" "run: npx vercel --prod" "run: terraform apply"; do
  tree_reset "$TEST_WORKFLOW"$'\n      - '"$word"
  dispatch_deploy_refused "a workflow with $word"
done
tree_reset "$TEST_WORKFLOW"$'\n      # Deploy is another workflow.'
respond dispatch owner/repo 5 "$HEAD_SHA" tests.yaml || fail "the responder refused a workflow whose comment names a deploy"
# A workflow or local action the test workflow calls runs with it, one of another repository cannot be read.
tree_reset "$TEST_WORKFLOW"$'\n  shared:\n    uses: ./.github/workflows/shared.yml'
tree_file "$HEAD_SHA" .github/workflows/shared.yml $'on: workflow_call\njobs:\n  ship:\n    steps:\n      - run: ./deploy'
dispatch_deploy_refused "a workflow calling a reusable workflow that deploys"
tree_file "$HEAD_SHA" .github/workflows/shared.yml $'on: workflow_call\njobs:\n  check:\n    steps:\n      - uses: ./.github/actions/setup'
tree_file "$HEAD_SHA" .github/actions/setup/action.yml $'runs:\n  using: composite\n  steps:\n    - run: ./scripts/deploy.sh'
dispatch_deploy_refused "a workflow whose reusable workflow calls a local action that deploys"
tree_file "$HEAD_SHA" .github/actions/setup/action.yml $'runs:\n  using: composite\n  steps:\n    - run: make setup'
respond dispatch owner/repo 5 "$HEAD_SHA" tests.yaml || fail "the responder refused a workflow whose callees only test"
tree_reset "$TEST_WORKFLOW"$'\n  shared:\n    uses: other/repo/.github/workflows/shared.yml@main'
dispatch_refused "a workflow calling a reusable workflow of another repository"
tree_reset "$TEST_WORKFLOW"$'\n      - uses: ./missing'
dispatch_refused "a workflow calling a local action it cannot read"
# A deploy chained after a run, or on a new branch, would run next to the tests, a chained one that only tests does not block them. A `workflow_run` runs from the default branch, so a deploy chained only there blocks them too.
for trigger in $'on:\n  workflow_run:\n    workflows: [other]' 'on: [create]'; do
  tree_reset
  tree_file "$HEAD_SHA" .github/workflows/chained.yml "$trigger"$'\njobs:\n  ship:\n    steps:\n      - run: ./deploy'
  dispatch_deploy_refused "next to a deploy chained by $trigger"
done
tree_reset
tree_file "$DEFAULT_SHA" .github/workflows/chained.yml $'on:\n  workflow_run:\n    workflows: [tests]\njobs:\n  ship:\n    steps:\n      - run: ./deploy'
dispatch_deploy_refused "next to a deploy chained on the default branch only"
tree_reset
tree_file "$HEAD_SHA" .github/workflows/chained.yml $'on:\n  workflow_run:\n    workflows: [tests]\njobs:\n  report:\n    steps:\n      - run: make report'
respond dispatch owner/repo 5 "$HEAD_SHA" tests.yaml || fail "the responder refused next to a chained workflow that only tests"
# An anchor or alias can move a trigger where the line reader does not look, so such a workflow counts as chained.
tree_reset
tree_file "$HEAD_SHA" .github/workflows/chained.yml $'triggers: &triggers\n  workflow_run:\n    workflows: [tests]\non: *triggers\njobs:\n  ship:\n    steps:\n      - run: ./deploy'
dispatch_deploy_refused "next to a deploy chained through an alias"
# The dispatched tree that mentions a deploy exits 5 with the command that trusts it for the repository named, and dispatch runs it once trusted, until any of its files changes.
tree_reset "$TEST_WORKFLOW"$'\n      - uses: ./.github/actions/setup'
tree_file "$HEAD_SHA" .github/actions/setup/action.yml $'runs:\n  using: composite\n  steps:\n    - run: ./scripts/deploy.sh'
"$RESPONDER" dispatch owner/repo 5 "$HEAD_SHA" tests.yaml >/dev/null 2>"$TEST_DIRECTORY/refused"
[ $? -eq 5 ] || fail "the responder did not exit 5 on a workflow tree that mentions a deploy"
grep -q 'action.yml: .*deploy' "$TEST_DIRECTORY/refused" || fail "the refusal did not show the matched line"
TRUST_ARGUMENTS="$(grep -oE 'green-trust\.sh owner/repo \.github/workflows/tests\.yaml [0-9a-f]{64}$' "$TEST_DIRECTORY/refused" | cut -d ' ' -f 2-)"
[ -n "$TRUST_ARGUMENTS" ] || fail "the refusal did not print the command that trusts the tree"
# shellcheck disable=SC2086
"$TRUST_SCRIPT" $TRUST_ARGUMENTS >/dev/null || fail "green-trust.sh refused the printed line"
respond dispatch owner/repo 5 "$HEAD_SHA" tests.yaml || fail "the responder refused a trusted workflow tree"
[ "$(head -1 "$STUB_POSTED")" = "repos/owner/repo/actions/workflows/tests.yaml/dispatches" ] || fail "the responder did not dispatch a trusted workflow tree"
tree_file "$HEAD_SHA" .github/actions/setup/action.yml $'runs:\n  using: composite\n  steps:\n    - run: ./scripts/deploy.sh --again'
dispatch_deploy_refused "a trusted tree after a file it calls changed"
# A workflow chained next to the trusted one is never trusted, even when it calls the same action.
tree_file "$HEAD_SHA" .github/actions/setup/action.yml $'runs:\n  using: composite\n  steps:\n    - run: ./scripts/deploy.sh'
tree_file "$HEAD_SHA" .github/workflows/chained.yml $'on:\n  workflow_run:\n    workflows: [tests]\njobs:\n  ship:\n    steps:\n      - uses: ./.github/actions/setup'
"$RESPONDER" dispatch owner/repo 5 "$HEAD_SHA" tests.yaml >/dev/null 2>"$TEST_DIRECTORY/refused"
[ $? -eq 5 ] || fail "the responder did not exit 5 next to a chained deploy calling a trusted action"
grep -q 'chained.yml mentions a deploy' "$TEST_DIRECTORY/refused" || fail "the responder did not name the chained workflow"
grep -q 'green-trust.sh' "$TEST_DIRECTORY/refused" && fail "the responder offered to trust a chained workflow"
# A pull request that changes `.github`, a line of another repository, or a reusable workflow it cannot read is never trusted.
tree_reset "$TEST_WORKFLOW"$'\n      - uses: ./.github/actions/setup'
tree_file "$HEAD_SHA" .github/actions/setup/action.yml $'runs:\n  using: composite\n  steps:\n    - run: ./scripts/deploy.sh'
STUB_FILES=$'a.txt\n.github/workflows/tests.yaml' dispatch_refused "a trusted tree in a pull request that changes .github"
cp "$TRUST_FILE" "$TEST_DIRECTORY/trusted"
sed 's|^owner/repo |other/repo |' "$TEST_DIRECTORY/trusted" >"$TRUST_FILE"
dispatch_deploy_refused "a tree trusted only for another repository"
cp "$TEST_DIRECTORY/trusted" "$TRUST_FILE"
tree_reset "$TEST_WORKFLOW"$'\n      - run: ./deploy\n  shared:\n    uses: other/repo/.github/workflows/shared.yml@main'
"$RESPONDER" dispatch owner/repo 5 "$HEAD_SHA" tests.yaml 2>&1 >/dev/null | grep -q 'green-trust.sh' && fail "the responder offered to trust a reusable workflow of another repository"
rm -r "$HOME/.config"
tree_reset
STUB_LIST_FAILS=1 dispatch_refused "after failing to list the workflows"
STUB_STATE="open true me" dispatch_refused "on a draft"
respond dispatch owner/repo 5 "$HEAD_SHA" ../tests.yaml && fail "the responder accepted a workflow path outside the workflows folder"
respond dispatch owner/repo 5 HEAD tests.yaml && fail "the responder accepted a head that is not a sha"
[ ! -e "$STUB_POSTED" ] || fail "the responder dispatched something it refused"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "PASS: green watcher scripts"
