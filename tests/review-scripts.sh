#!/bin/bash

# Checks the `review-github-prs-watcher` scripts against a stub `gh` on `PATH`,
# never the real GitHub. The detector reports a requested review, and a pull
# request reviewed without approving after a push or an answer in a thread of the
# viewer, never an approved one, once while its review runs and until it is
# marked done, leaves out the merge queue, and rejects a scope that could carry
# a search qualifier. The poster rejects a bad repository, number,
# commit, event or comment shape, refuses a pull request that moved to another
# commit or one it already reviewed at that commit, and otherwise posts one review with the validated payload.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WATCHER="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/watch-review-requests.sh"
POSTER="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/post-pr-review.sh"

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
export STUB_HEAD_SHA="$HEAD_SHA"
export STUB_POSTED_FILE="$TEST_DIRECTORY/posted.json"

# The stub answers the calls the scripts make: the search, the pull request state
# read, the viewer and their reviews, and the review POST, whose standard input
# it keeps.
cat >"$TEST_DIRECTORY/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
  "api graphql"*)
    # Answers the two searches with the nodes the test set, plus a queued pull
    # request when the query does not leave the merge queue out, then applies
    # the `--jq` filter the way `gh` does.
    requested="${STUB_REQUESTED:-[]}"
    case "$*" in
      *-is:queued*) ;;
      *) requested="$(jq -c '. + [{number: 9, url: "https://github.com/owner/repo/pull/9", headRefOid: "'"$STUB_HEAD_SHA"'", repository: {nameWithOwner: "owner/repo"}}]' <<<"$requested")" ;;
    esac
    while [ $# -gt 0 ]; do
      [ "$1" = "--jq" ] && filter="$2"
      shift
    done
    jq -n --argjson requested "$requested" --argjson reviewed "${STUB_REVIEWED:-[]}" \
      '{data: {viewer: {login: "me"}, requested: {nodes: $requested}, reviewed: {nodes: $reviewed}}}' | jq -r "$filter" ;;
  *"--method POST"*) cat >"$STUB_POSTED_FILE"; echo "https://github.com/owner/repo/pull/5#review" ;;
  "api user"*) echo "me" ;;
  *"/reviews"*) [ -z "$STUB_REVIEWS_FAIL" ] || exit 1; echo "${STUB_REVIEWS:-[]}" ;;
  *) echo "${STUB_STATE:-open false $STUB_HEAD_SHA}" ;;
esac
STUB
chmod +x "$TEST_DIRECTORY/bin/gh"
export PATH="$TEST_DIRECTORY/bin:$PATH"

OLD_SHA=1111111111111111111111111111111111111111
# One search node. The viewer's reviews come from the optional state and commit, or from a
# JSON array of [state, commit] pairs as the sixth argument, oldest first. The threads are a
# JSON array of arrays of [login, time, type, association], the last two default to a
# person who is a member.
node() {
  jq -nc --argjson number "$1" --arg sha "$2" --arg state "${3:-}" --arg commit "${4:-}" --argjson threads "${5:-[]}" --argjson reviews "${6:-[]}" '
    {number: $number, url: "https://github.com/owner/repo/pull/\($number)", headRefOid: $sha, repository: {nameWithOwner: "owner/repo"},
     reviews: {nodes: ((if $state == "" then [] else [[$state, $commit]] end) + $reviews | map({author: {login: "me"}, state: .[0], commit: {oid: .[1]}}))},
     reviewThreads: {nodes: [$threads[] | {comments: {nodes: [.[] | {author: (if .[0] == null then null else {__typename: (.[2] // "User"), login: .[0]} end), authorAssociation: (.[3] // "MEMBER"), createdAt: .[1]}]}}]}}'
}
# Sets the nodes one search returns, a stub variable named by the first argument.
set_nodes() {
  printf -v "$1" '[%s]' "$2"
  export "${1?}"
}
detect() {
  "$WATCHER" owner --once
}
reset_state() {
  rm -rf "$XDG_CACHE_HOME"
}

# A dry run reports and claims nothing.
KEY="owner/repo#5@$HEAD_SHA"
set_nodes STUB_REQUESTED "$(node 5 "$HEAD_SHA")"
[ -n "$("$WATCHER" owner --once --dry-run)" ] || fail "the detector did not report on a dry run"
[ -n "$("$WATCHER" owner --once --dry-run)" ] || fail "a dry run claimed a pull request"

# A review request is reported, claimed, not recorded as done, and reported again only when the claim expires.
[ "$(detect)" = "$KEY https://github.com/owner/repo/pull/5 requested" ] || fail "the detector did not report a review request"
[ ! -s "$XDG_CACHE_HOME/review-github-prs-watcher/seen" ] || fail "the detector recorded a pull request before its review was done"
[ -z "$(detect)" ] || fail "the detector started a review that is still running twice"
echo "$(($(date +%s) - 7300)) $KEY" >"$XDG_CACHE_HOME/review-github-prs-watcher/claimed"
[ -n "$(detect)" ] || fail "the detector dropped a pull request whose claim expired"
echo "$(date +%s) $KEY" >"$XDG_CACHE_HOME/review-github-prs-watcher/claimed"
# A mark waits while the detector rewrites the state files, an append to a file being replaced would be lost.
mkdir "$XDG_CACHE_HOME/review-github-prs-watcher/state.lock"
REVIEW_LOCK_ATTEMPTS=1 "$WATCHER" --mark "$KEY" 2>/dev/null && fail "the detector marked a pull request while its state files were locked"
rmdir "$XDG_CACHE_HOME/review-github-prs-watcher/state.lock"
"$WATCHER" --mark "$KEY" || fail "the detector refused to mark a pull request done"
[ ! -e "$XDG_CACHE_HOME/review-github-prs-watcher/state.lock" ] || fail "the detector kept the state lock after a mark"
echo "0 $KEY" >"$XDG_CACHE_HOME/review-github-prs-watcher/claimed"
[ -z "$(detect)" ] || fail "the detector reported a marked head commit again"
set_nodes STUB_REQUESTED "$(node 5 "$OLD_SHA")"
[ -n "$(detect)" ] || fail "the detector missed a push to a requested pull request"

# The merge queue stays out, the stub adds a queued pull request to any query that does not exclude it.
reset_state
export STUB_REQUESTED="[]"
[ -z "$(detect)" ] || fail "the detector reported a pull request in the merge queue"

# A pull request that was reviewed without approving comes back after a push.
reset_state
export STUB_REQUESTED="[]"
set_nodes STUB_REVIEWED "$(node 6 "$HEAD_SHA" COMMENTED "$OLD_SHA")"
[ "$(detect)" = "owner/repo#6@$HEAD_SHA https://github.com/owner/repo/pull/6 pushed" ] || fail "the detector missed a push after a review without approval"

# An approved pull request stays out, a push included, until the review is requested again.
reset_state
set_nodes STUB_REVIEWED "$(node 6 "$HEAD_SHA" APPROVED "$OLD_SHA")"
[ -z "$(detect)" ] || fail "the detector reported a pull request the viewer approved"
set_nodes STUB_REQUESTED "$(node 6 "$HEAD_SHA" APPROVED "$OLD_SHA")"
[ -n "$(detect)" ] || fail "the detector missed a new review request on an approved pull request"
export STUB_REQUESTED="[]"

# An answer in a thread the viewer took part in comes back, keyed by its time, a bot or the viewer last does not.
reset_state
set_nodes STUB_REVIEWED "$(node 6 "$HEAD_SHA" COMMENTED "$HEAD_SHA" '[[["me","2026-11-05T10:00:00Z"],["author","2026-11-05T11:00:00Z"]]]')"
EPOCH="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' 2026-11-05T11:00:00Z +%s 2>/dev/null || date -u -d 2026-11-05T11:00:00Z +%s)"
[ "$(detect)" = "owner/repo#6@$HEAD_SHA+$EPOCH https://github.com/owner/repo/pull/6 reply" ] || fail "the detector missed an answer in a thread of the viewer"
"$WATCHER" --mark "owner/repo#6@$HEAD_SHA+$EPOCH" || fail "the detector refused to mark an answer done"
echo "0 owner/repo#6@$HEAD_SHA+$EPOCH" >"$XDG_CACHE_HOME/review-github-prs-watcher/claimed"
[ -z "$(detect)" ] || fail "the detector reported an answer already handled"
reset_state
set_nodes STUB_REVIEWED "$(node 6 "$HEAD_SHA" COMMENTED "$HEAD_SHA" '[[["me","2026-11-05T10:00:00Z"],["github-actions","2026-11-05T11:00:00Z","Bot"]],[["author","2026-11-05T09:00:00Z"],["me","2026-11-05T10:00:00Z"]]]')"
[ -z "$(detect)" ] || fail "the detector reported a bot answer or a thread the viewer answered last"
reset_state
set_nodes STUB_REVIEWED "$(node 6 "$HEAD_SHA" COMMENTED "$HEAD_SHA" '[[["me","2026-11-05T10:00:00Z"],["stranger","2026-11-05T11:00:00Z","User","NONE"]],[["me","2026-11-05T10:00:00Z"],[null,"2026-11-05T11:00:00Z"]]]')"
[ -z "$(detect)" ] || fail "the detector reported an answer from an outsider or a deleted author"

# A reply creates a COMMENTED review, it must not make an approved pull request look unapproved after a push.
reset_state
set_nodes STUB_REVIEWED "$(node 6 "$HEAD_SHA" "" "" '[]' "[[\"APPROVED\",\"$OLD_SHA\"],[\"COMMENTED\",\"$OLD_SHA\"]]")"
[ -z "$(detect)" ] || fail "the detector reported an approved pull request after a reply review and a push"
unset STUB_REQUESTED STUB_REVIEWED

"$WATCHER" --mark 'owner/repo#5@abc' >/dev/null 2>&1 && fail "the detector marked a malformed key"
"$WATCHER" --mark "$(printf 'owner/repo#5@%s\nx' "$HEAD_SHA")" >/dev/null 2>&1 && fail "the detector marked a key with a newline"
"$WATCHER" "$(printf 'owner\nauthor:someone')" --once >/dev/null 2>&1 && fail "the detector accepted a scope with a newline"
"$WATCHER" 'owner author:someone' --once >/dev/null 2>&1 && fail "the detector accepted a scope with a search qualifier"
"$WATCHER" owner --interval ten --once >/dev/null 2>&1 && fail "the detector accepted a non numeric interval"

echo "body" >"$TEST_DIRECTORY/body.txt"
echo '[{"path":"a.rb","line":3,"body":"nit"}]' >"$TEST_DIRECTORY/comments.json"
echo '[{"path":"a.rb","line":3,"body":"nit","side":"LEFT"}]' >"$TEST_DIRECTORY/extra.json"
post() {
  "$POSTER" "${1:-owner/repo}" "${2:-5}" "${3:-$HEAD_SHA}" "${4:-COMMENT}" "$TEST_DIRECTORY/body.txt" "${5:-$TEST_DIRECTORY/comments.json}" 2>/dev/null
}

post 'owner/repo extra' && fail "the poster accepted a repository with a space"
post owner/repo x && fail "the poster accepted a non numeric pull request"
post owner/repo 5 abc && fail "the poster accepted a short commit"
post owner/repo 5 "$HEAD_SHA" DISMISS && fail "the poster accepted an unknown event"
# An approval needs a fresh claim of the detector for this very pull request and commit.
mkdir -p "$XDG_CACHE_HOME/review-github-prs-watcher"
: >"$XDG_CACHE_HOME/review-github-prs-watcher/claimed"
post owner/repo 5 "$HEAD_SHA" APPROVE && fail "the poster approved a pull request the watcher never claimed"
echo "$(date +%s) owner/repo#6@$HEAD_SHA" >"$XDG_CACHE_HOME/review-github-prs-watcher/claimed"
post owner/repo 5 "$HEAD_SHA" APPROVE && fail "the poster approved with the claim of another pull request"
echo "$(($(date +%s) - 7300)) owner/repo#5@$HEAD_SHA" >"$XDG_CACHE_HOME/review-github-prs-watcher/claimed"
post owner/repo 5 "$HEAD_SHA" APPROVE && fail "the poster approved with an expired claim"
echo "$(date +%s) owner/repo#5@$HEAD_SHA" >"$XDG_CACHE_HOME/review-github-prs-watcher/claimed"
post owner/repo 5 "$HEAD_SHA" APPROVE >/dev/null || fail "the poster refused an approval the watcher claimed"
echo "$(date +%s) owner/repo#5@$HEAD_SHA+1700000000" >"$XDG_CACHE_HOME/review-github-prs-watcher/claimed"
post owner/repo 5 "$HEAD_SHA" APPROVE >/dev/null || fail "the poster refused an approval claimed with a reply epoch"
rm -f "$STUB_POSTED_FILE"
post owner/repo 5 "$HEAD_SHA" COMMENT "$TEST_DIRECTORY/extra.json" && fail "the poster accepted an unexpected comment field"
STUB_STATE="open false 2222222222222222222222222222222222222222" post && fail "the poster posted on a moved pull request"
STUB_STATE="open true $HEAD_SHA" post && fail "the poster posted on a draft"
STUB_REVIEWS="[{\"user\":{\"login\":\"me\"},\"commit_id\":\"$HEAD_SHA\"}]" post && fail "the poster reviewed a commit twice"
# Pages come one array each, a review on the first page counts with a later page present.
STUB_REVIEWS="[{\"user\":{\"login\":\"me\"},\"commit_id\":\"$HEAD_SHA\"}]"$'\n'"[]" post && fail "the poster ignored a review on an earlier page"
STUB_REVIEWS_FAIL=1 post && fail "the poster posted when the reviews could not be read"
post "$(printf 'owner/repo\nx/y')" && fail "the poster accepted a repository with a newline"
# Only files in a temporary directory are read, never another file or a link to one.
# The reason is checked too, so an earlier refusal cannot make these pass. The caller's `TMPDIR` never makes another folder a temporary one.
refused() {
  local message
  message="$("$POSTER" owner/repo 5 "$HEAD_SHA" COMMENT "$1" "$2" 2>&1 >/dev/null)" && return 1
  [[ $message == *"$3"* ]]
}
OUTSIDE_FILE="$TESTS_SCRIPT_DIRECTORY/review-scripts.sh"
refused "$OUTSIDE_FILE" "$TEST_DIRECTORY/comments.json" "temporary directory" || fail "the poster posted a file outside a temporary directory as the body"
refused "$TEST_DIRECTORY/body.txt" "$OUTSIDE_FILE" "temporary directory" || fail "the poster read a file outside a temporary directory as the comments"
TMPDIR="$TESTS_SCRIPT_DIRECTORY" refused "$OUTSIDE_FILE" "$TEST_DIRECTORY/comments.json" "temporary directory" || fail "the poster let the caller make another folder a temporary one"
ln -s "$TEST_DIRECTORY/body.txt" "$TEST_DIRECTORY/link.txt"
refused "$TEST_DIRECTORY/link.txt" "$TEST_DIRECTORY/comments.json" "symlinks" || fail "the poster accepted a symlink as the body"
ln "$TEST_DIRECTORY/body.txt" "$TEST_DIRECTORY/hard.txt"
refused "$TEST_DIRECTORY/hard.txt" "$TEST_DIRECTORY/comments.json" "one link" || fail "the poster accepted a hard linked file as the body"
rm "$TEST_DIRECTORY/hard.txt"
[ ! -e "$STUB_POSTED_FILE" ] || fail "a refused review was still posted"
post >/dev/null || fail "the poster refused a valid review"
[ "$(jq -r '.event, .commit_id, .comments[0].path' "$STUB_POSTED_FILE" | tr '\n' ' ')" = "COMMENT $HEAD_SHA a.rb " ] || fail "the posted payload is wrong"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "PASS: review requested watcher scripts"
