#!/bin/bash

# Checks `post-thread-reply.sh` against a stub `gh` on `PATH`, never the real
# GitHub. It replies once, to the first comment of the thread, when the comment is
# the newest of a thread the viewer took part in and was written by a person, and
# refuses a bot, the viewer's own comment, a comment that is not the newest, a
# thread the viewer is not in, a pull request that is closed or a draft, a failed
# read, and a bad repository, number or body.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPLIER="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/post-thread-reply.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

failures=0
fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

export STUB_POSTED_FILE="$TEST_DIRECTORY/posted.json"
export STUB_POSTED_ENDPOINT="$TEST_DIRECTORY/endpoint.txt"
mkdir -p "$TEST_DIRECTORY/bin"

# The stub answers the calls the script makes, the pull request state, the viewer,
# the comments and the reply POST, whose endpoint and standard input it keeps.
cat >"$TEST_DIRECTORY/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
  *"--method POST"*) echo "$2" >"$STUB_POSTED_ENDPOINT"; cat >"$STUB_POSTED_FILE"; echo "https://github.com/owner/repo/pull/5#discussion_r3" ;;
  "api user"*) echo "me" ;;
  *"/comments"*) [ -z "$STUB_COMMENTS_FAIL" ] || exit 1; echo "${STUB_COMMENTS:-[]}" ;;
  *) echo "${STUB_STATE:-open false}" ;;
esac
STUB
chmod +x "$TEST_DIRECTORY/bin/gh"
export PATH="$TEST_DIRECTORY/bin:$PATH"

# Thread 1 is mine then an answer, 3 is an answer then my reply then a newer answer, 10 is two others, 20 is mine then a bot, 30 is mine then an outsider.
THREADS='[
  {"id":1,"created_at":"2026-01-01T00:00:00Z","user":{"login":"me","type":"User"}},
  {"id":2,"created_at":"2026-01-01T00:01:00Z","in_reply_to_id":1,"author_association":"MEMBER","user":{"login":"author","type":"User"}},
  {"id":3,"created_at":"2026-01-01T00:00:00Z","author_association":"MEMBER","user":{"login":"author","type":"User"}},
  {"id":4,"created_at":"2026-01-01T00:01:00Z","in_reply_to_id":3,"user":{"login":"me","type":"User"}},
  {"id":5,"created_at":"2026-01-01T00:02:00Z","in_reply_to_id":3,"author_association":"MEMBER","user":{"login":"author","type":"User"}},
  {"id":10,"created_at":"2026-01-01T00:00:00Z","author_association":"MEMBER","user":{"login":"other","type":"User"}},
  {"id":11,"created_at":"2026-01-01T00:01:00Z","in_reply_to_id":10,"author_association":"MEMBER","user":{"login":"author","type":"User"}},
  {"id":20,"created_at":"2026-01-01T00:00:00Z","user":{"login":"me","type":"User"}},
  {"id":21,"created_at":"2026-01-01T00:01:00Z","in_reply_to_id":20,"author_association":"NONE","user":{"login":"ci","type":"Bot"}},
  {"id":30,"created_at":"2026-01-01T00:00:00Z","user":{"login":"me","type":"User"}},
  {"id":31,"created_at":"2026-01-01T00:01:00Z","in_reply_to_id":30,"author_association":"NONE","user":{"login":"stranger","type":"User"}}
]'
export STUB_COMMENTS="$THREADS"
echo "Fixed, thanks." >"$TEST_DIRECTORY/body.txt"
: >"$TEST_DIRECTORY/empty.txt"
reply() {
  "$REPLIER" "${1:-owner/repo}" "${2:-5}" "${3:-2}" "${4:-$TEST_DIRECTORY/body.txt}" 2>/dev/null
}

reply owner/repo 5 3 && fail "the replier answered a comment that is not the newest of its thread"
reply owner/repo 5 4 && fail "the replier answered the viewer's own comment"
reply owner/repo 5 11 && fail "the replier answered a thread the viewer is not in"
reply owner/repo 5 21 && fail "the replier answered a bot"
reply owner/repo 5 99 && fail "the replier answered a comment that does not exist"
reply owner/repo 5 31 && fail "the replier answered an outsider"
# Four of the viewer's comments in the last day are the limit for one thread.
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STUB_COMMENTS="[{\"id\":40,\"created_at\":\"$now\",\"user\":{\"login\":\"me\",\"type\":\"User\"}},{\"id\":41,\"created_at\":\"$now\",\"in_reply_to_id\":40,\"user\":{\"login\":\"me\",\"type\":\"User\"}},{\"id\":42,\"created_at\":\"$now\",\"in_reply_to_id\":40,\"user\":{\"login\":\"me\",\"type\":\"User\"}},{\"id\":43,\"created_at\":\"$now\",\"in_reply_to_id\":40,\"user\":{\"login\":\"me\",\"type\":\"User\"}},{\"id\":44,\"created_at\":\"$now\",\"in_reply_to_id\":40,\"author_association\":\"MEMBER\",\"user\":{\"login\":\"author\",\"type\":\"User\"}}]" reply owner/repo 5 44 && fail "the replier answered a thread that reached its daily limit"
# Only a file in a temporary directory is read as a body, never another file or a link to one.
[ -e "$HOME/.zshrc" ] && reply owner/repo 5 2 "$HOME/.zshrc" && fail "the replier posted a file outside a temporary directory"
ln -s "$TEST_DIRECTORY/body.txt" "$TEST_DIRECTORY/link.txt"
reply owner/repo 5 2 "$TEST_DIRECTORY/link.txt" && fail "the replier accepted a symlink as the body"
STUB_STATE="closed false" reply && fail "the replier answered on a closed pull request"
STUB_STATE="open true" reply && fail "the replier answered on a draft"
STUB_COMMENTS_FAIL=1 reply && fail "the replier answered when the comments could not be read"
reply 'owner/repo extra' && fail "the replier accepted a repository with a space"
reply "$(printf 'owner/repo\nx/y')" && fail "the replier accepted a repository with a newline"
reply owner/repo x && fail "the replier accepted a non numeric pull request"
reply owner/repo 5 x && fail "the replier accepted a non numeric comment"
reply owner/repo 5 2 "$TEST_DIRECTORY/empty.txt" && fail "the replier accepted an empty body"
reply owner/repo 5 2 "$TEST_DIRECTORY/missing.txt" && fail "the replier accepted a missing body file"
head -c 70000 /dev/zero | tr '\0' a >"$TEST_DIRECTORY/long.txt"
reply owner/repo 5 2 "$TEST_DIRECTORY/long.txt" && fail "the replier accepted a body that is too long"
[ ! -e "$STUB_POSTED_FILE" ] || fail "a refused reply was still posted"

[ "$(reply owner/repo 5 5)" = "https://github.com/owner/repo/pull/5#discussion_r3" ] || fail "the replier refused a valid reply"
[ "$(cat "$STUB_POSTED_ENDPOINT")" = "repos/owner/repo/pulls/5/comments/3/replies" ] || fail "the reply did not go to the first comment of the thread"
[ "$(jq -r .body "$STUB_POSTED_FILE")" = "Fixed, thanks." ] || fail "the posted body is wrong"
reply owner/repo 5 2 >/dev/null || fail "the replier refused the newest comment of a thread of two"
[ "$(cat "$STUB_POSTED_ENDPOINT")" = "repos/owner/repo/pulls/5/comments/1/replies" ] || fail "the reply to a thread of two did not go to its first comment"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "PASS: review thread reply script"
