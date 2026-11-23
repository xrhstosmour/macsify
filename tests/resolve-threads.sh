#!/bin/bash

# Checks `resolve-threads.sh` against a stub `gh` on `PATH`, never the real GitHub.
# It prints every thread with its comments, fails on more than 100 threads, more than
# 50 comments in a thread or a failed read, and rejects a bad repository or number
# before calling `gh`.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
READER="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/resolve-threads.sh"

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

response() {
  jq -nc --argjson threads "$1" --argjson comments "$2" '{data: {repository: {pullRequest: {reviewThreads: {totalCount: $threads, nodes: [
    {id: "T1", isResolved: false, comments: {totalCount: $comments, nodes: [
      {databaseId: 11, author: {login: "reviewer"}, body: "Rename this.", createdAt: "2026-01-01T00:00:00Z", path: "a.rb", line: 1, originalCommit: {oid: "abc"}},
      {databaseId: 12, author: {login: "me"}, body: "Done.", createdAt: "2026-01-02T00:00:00Z", path: "a.rb", line: 1, originalCommit: {oid: "abc"}}
    ]}},
    {id: "T2", isResolved: true, comments: {totalCount: 1, nodes: [
      {databaseId: 21, author: {login: "ci"}, body: "Lint.", createdAt: "2026-01-03T00:00:00Z", path: "b.rb", line: null, originalCommit: {oid: "def"}}
    ]}}
  ]}}}}}'
}

export STUB_RESPONSE
STUB_RESPONSE="$(response 2 2)"
output="$("$READER" owner/repo 5 2>/dev/null)" || fail "the reader failed on a valid pull request"
[ "$(wc -l <<<"$output" | tr -d ' ')" = 2 ] || fail "the reader did not print one line per thread: $output"
jq -e -s '.[0] == {id: "T1", isResolved: false, comments: [
    {databaseId: 11, author: "reviewer", body: "Rename this.", createdAt: "2026-01-01T00:00:00Z", path: "a.rb", line: 1, originalCommit: "abc"},
    {databaseId: 12, author: "me", body: "Done.", createdAt: "2026-01-02T00:00:00Z", path: "a.rb", line: 1, originalCommit: "abc"}
  ]} and .[1].isResolved == true' <<<"$output" >/dev/null ||
  fail "the reader printed the wrong thread shape: $output"

STUB_RESPONSE="$(response 101 2)"
"$READER" owner/repo 5 >/dev/null 2>&1 && fail "the reader dropped threads past the first 100 without failing"

STUB_RESPONSE="$(response 2 51)"
"$READER" owner/repo 5 >/dev/null 2>&1 && fail "the reader dropped comments past the first 50 without failing"

STUB_RESPONSE="$(response 2 2)"
STUB_FAIL=1 "$READER" owner/repo 5 >/dev/null 2>&1 && fail "the reader succeeded on a failed read"

rm -f "$STUB_CALLED_FILE"
"$READER" 'owner/repo;x' 5 >/dev/null 2>&1 && fail "the reader accepted a bad repository"
"$READER" owner/repo 5x >/dev/null 2>&1 && fail "the reader accepted a bad number"
"$READER" owner/repo >/dev/null 2>&1 && fail "the reader accepted a missing number"
[ -e "$STUB_CALLED_FILE" ] && fail "the reader called gh with a bad input"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "PASS: resolve threads script"
