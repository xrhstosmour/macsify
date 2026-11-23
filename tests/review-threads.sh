#!/bin/bash

# Checks `review-threads.sh` against a stub `gh` on `PATH`, never the real GitHub.
# A review read prints the threads that are not outdated, a `--comments` read every
# thread with all its comments. It fails on more than 100 threads, more than 50
# comments in a thread for `--comments`, or a failed read, and rejects a bad
# repository or number before calling `gh`.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
READER="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/review-threads.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

failures=0
fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

export STUB_CALLED_FILE="$TEST_DIRECTORY/called.txt"
mkdir -p "$TEST_DIRECTORY/bin"

# The stub answers the one GraphQL read with the response the test set and keeps a mark that it ran.
cat >"$TEST_DIRECTORY/bin/gh" <<'STUB'
#!/bin/bash
touch "$STUB_CALLED_FILE"
[ -z "$STUB_FAIL" ] || exit 1
echo "$STUB_RESPONSE"
STUB
chmod +x "$TEST_DIRECTORY/bin/gh"
export PATH="$TEST_DIRECTORY/bin:$PATH"

# The first thread holds a reply, its comment count is the second argument.
response() {
  jq -nc --argjson total "$1" --argjson comments "$2" '{data: {repository: {pullRequest: {reviewThreads: {totalCount: $total, nodes: [
    {id: "T1", path: "a.rb", line: 1, isResolved: false, isOutdated: false, comments: {totalCount: $comments, nodes: [
      {databaseId: 11, author: {__typename: "User", login: "reviewer"}, body: "Rename this.", createdAt: "2026-01-01T00:00:00Z", path: "a.rb", line: 1, originalCommit: {oid: "abc"}},
      {databaseId: 12, author: {__typename: "User", login: "me"}, body: "Done.", createdAt: "2026-01-02T00:00:00Z", path: "a.rb", line: 1, originalCommit: {oid: "abc"}}
    ]}},
    {id: "T2", path: "b.rb", line: 2, isResolved: true, isOutdated: true, comments: {totalCount: 1, nodes: [
      {databaseId: 21, author: {__typename: "User", login: "reviewer"}, body: "Gone.", createdAt: "2026-01-03T00:00:00Z", path: "b.rb", line: 2, originalCommit: {oid: "abc"}}
    ]}},
    {id: "T3", path: "c.rb", line: 3, isResolved: true, isOutdated: false, comments: {totalCount: 1, nodes: [
      {databaseId: 31, author: {__typename: "Bot", login: "ci"}, body: "Lint.", createdAt: "2026-01-04T00:00:00Z", path: "c.rb", line: 3, originalCommit: {oid: "def"}}
    ]}}
  ]}}}}}'
}

export STUB_RESPONSE
STUB_RESPONSE="$(response 3 2)"
output="$("$READER" owner/repo 5 2>/dev/null)" || fail "the review read failed on a valid pull request"
[ "$(wc -l <<<"$output" | tr -d ' ')" = 2 ] || fail "the review read did not leave out the outdated thread: $output"
jq -e -s '.[0] == {path: "a.rb", line: 1, isResolved: false, author: "reviewer", bot: false, body: "Rename this."} and .[1].bot == true' <<<"$output" >/dev/null ||
  fail "the review read printed the wrong thread shape: $output"

output="$("$READER" --comments owner/repo 5 2>/dev/null)" || fail "the comments read failed on a valid pull request"
[ "$(wc -l <<<"$output" | tr -d ' ')" = 3 ] || fail "the comments read did not print every thread: $output"
jq -e -s '.[0] == {id: "T1", isResolved: false, comments: [
    {databaseId: 11, author: "reviewer", body: "Rename this.", createdAt: "2026-01-01T00:00:00Z", path: "a.rb", line: 1, originalCommit: "abc"},
    {databaseId: 12, author: "me", body: "Done.", createdAt: "2026-01-02T00:00:00Z", path: "a.rb", line: 1, originalCommit: "abc"}
  ]}' <<<"$output" >/dev/null ||
  fail "the comments read printed the wrong thread shape: $output"

STUB_RESPONSE="$(response 101 2)"
"$READER" owner/repo 5 >/dev/null 2>&1 && fail "the review read dropped threads past the first 100 without failing"
"$READER" --comments owner/repo 5 >/dev/null 2>&1 && fail "the comments read dropped threads past the first 100 without failing"

STUB_RESPONSE="$(response 3 51)"
"$READER" --comments owner/repo 5 >/dev/null 2>&1 && fail "the comments read dropped comments past the first 50 without failing"

STUB_RESPONSE="$(response 3 2)"
STUB_FAIL=1 "$READER" owner/repo 5 >/dev/null 2>&1 && fail "the reader succeeded on a failed read"

rm -f "$STUB_CALLED_FILE"
"$READER" 'owner/repo;x' 5 >/dev/null 2>&1 && fail "the reader accepted a bad repository"
"$READER" owner/repo 5x >/dev/null 2>&1 && fail "the reader accepted a bad number"
"$READER" owner/repo >/dev/null 2>&1 && fail "the reader accepted a missing number"
"$READER" --other owner/repo 5 >/dev/null 2>&1 && fail "the reader accepted an unknown option"
[ -e "$STUB_CALLED_FILE" ] && fail "the reader called gh with a bad input"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "PASS: review threads script"
