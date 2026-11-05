#!/bin/bash

# Checks the `review-github-pr-watcher` scripts against a stub `gh` on `PATH`,
# never the real GitHub. The detector reports a pull request once per head
# commit, again after a push, never with `--dry-run`, and rejects a scope that
# could carry a search qualifier. The poster rejects a bad repository, number,
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
  "api graphql"*) echo "owner/repo 5 $STUB_HEAD_SHA https://github.com/owner/repo/pull/5" ;;
  *"--method POST"*) cat >"$STUB_POSTED_FILE"; echo "https://github.com/owner/repo/pull/5#review" ;;
  "api user"*) echo "me" ;;
  *"/reviews"*) [ -z "$STUB_REVIEWS_FAIL" ] || exit 1; echo "${STUB_REVIEWS:-[]}" ;;
  *) echo "${STUB_STATE:-open false $STUB_HEAD_SHA}" ;;
esac
STUB
chmod +x "$TEST_DIRECTORY/bin/gh"
export PATH="$TEST_DIRECTORY/bin:$PATH"

[ "$("$WATCHER" owner --once --dry-run)" = "owner/repo#5@$HEAD_SHA https://github.com/owner/repo/pull/5" ] || fail "the detector did not report a new pull request"
[ ! -s "$XDG_CACHE_HOME/review-github-pr-watcher/seen" ] || fail "a dry run recorded a pull request"
"$WATCHER" owner --once >/dev/null
[ -z "$("$WATCHER" owner --once)" ] || fail "the detector reported the same head commit twice"
export STUB_HEAD_SHA=1111111111111111111111111111111111111111
[ -n "$("$WATCHER" owner --once)" ] || fail "the detector missed a push to a reviewed pull request"
export STUB_HEAD_SHA="$HEAD_SHA"
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
post owner/repo 5 "$HEAD_SHA" COMMENT "$TEST_DIRECTORY/extra.json" && fail "the poster accepted an unexpected comment field"
STUB_STATE="open false 2222222222222222222222222222222222222222" post && fail "the poster posted on a moved pull request"
STUB_STATE="open true $HEAD_SHA" post && fail "the poster posted on a draft"
STUB_REVIEWS="[{\"user\":{\"login\":\"me\"},\"commit_id\":\"$HEAD_SHA\"}]" post && fail "the poster reviewed a commit twice"
# Pages come one array each, a review on the first page counts with a later page present.
STUB_REVIEWS="[{\"user\":{\"login\":\"me\"},\"commit_id\":\"$HEAD_SHA\"}]"$'\n'"[]" post && fail "the poster ignored a review on an earlier page"
STUB_REVIEWS_FAIL=1 post && fail "the poster posted when the reviews could not be read"
post "$(printf 'owner/repo\nx/y')" && fail "the poster accepted a repository with a newline"
[ ! -e "$STUB_POSTED_FILE" ] || fail "a refused review was still posted"
post >/dev/null || fail "the poster refused a valid review"
[ "$(jq -r '.event, .commit_id, .comments[0].path' "$STUB_POSTED_FILE" | tr '\n' ' ')" = "COMMENT $HEAD_SHA a.rb " ] || fail "the posted payload is wrong"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "PASS: review requested watcher scripts"
