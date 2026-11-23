#!/bin/bash

# Checks `green-manual-tests.sh` against a stub `gh` on `PATH`, never the real
# GitHub. It moves the branch of a `manual-tests` line to the pull request head
# with a forced update, creating it when missing, and exits 6 with no line for
# the repository and workflow, so the caller keeps its needs attention line. It
# refuses a bad input, a bad or linked file, a line naming `main`, the default
# branch, a deploy target or the branch of the pull request, a pull request of
# another author, from a fork, a draft, moved, or changing `.github`, and exits 7
# without moving anything while a run of the branch is not completed.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/green-manual-tests.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

failures=0
fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

HEAD_SHA=0123456789012345678901234567890123456789
# The manual-tests file lives under `HOME`, your own must never approve a test run.
export HOME="$TEST_DIRECTORY/home"
MANUAL_FILE="$HOME/.config/green-github-prs-watcher/manual-tests"
export STUB_CALLS="$TEST_DIRECTORY/calls"
mkdir -p "$TEST_DIRECTORY/bin" "$(dirname "$MANUAL_FILE")"

# The stub logs every call and answers like `gh` for pull request 5 of
# `owner/repo`, whose default branch is `main`. `STUB_PULL_REQUEST` is the
# `<state> <draft> <author> <head> <repository> <changed files> <ref>` the script reads,
# `STUB_RUNS` the count of runs not completed, `STUB_REFS` the matching refs.
cat >"$TEST_DIRECTORY/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >>"$STUB_CALLS"
filter=""
arguments=("$@")
for index in "${!arguments[@]}"; do
  [ "${arguments[index]}" = --jq ] && filter="${arguments[index + 1]}"
done
case "$*" in
  "api user"*) echo me ;;
  "api repos/owner/repo/pulls/5 --jq .head.sha") echo "${STUB_LATER_HEAD:-0123456789012345678901234567890123456789}" ;;
  "api repos/owner/repo/pulls/5 "*)
    read -r state draft author head repository changed ref <<<"${STUB_PULL_REQUEST:-open false me 0123456789012345678901234567890123456789 owner/repo 2 fix/thing}"
    echo "$state $draft $author $head $repository $changed $ref" ;;
  "api --paginate repos/owner/repo/pulls/5/files"*) printf '%s\n' "${STUB_FILES:-a.txt}" | jq -R '[{filename: .}]' | jq -r "$filter" ;;
  "api repos/owner/repo --jq .default_branch") echo "${STUB_DEFAULT:-main}" ;;
  "run list --repo owner/repo --branch "*) echo "${STUB_RUNS:-0}" ;;
  "api repos/owner/repo/git/matching-refs/"*) printf '%s' "$STUB_REFS" ;;
  "api -X PATCH "* | "api -X POST "*) ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$TEST_DIRECTORY/bin/gh"
export PATH="$TEST_DIRECTORY/bin:$PATH"

# Writes the manual-tests file, one line per argument.
manual_file() {
  rm -f "$MANUAL_FILE"
  printf '%s\n' "$@" >"$MANUAL_FILE"
}

# Runs the script with the stub reads reset, prints nothing, leaves the exit status and the calls.
run() {
  : >"$STUB_CALLS"
  bash "$SCRIPT" "$@" >"$TEST_DIRECTORY/output" 2>"$TEST_DIRECTORY/error"
}
moved() { grep -qE 'api -X (PATCH|POST)' "$STUB_CALLS"; }

# Fails unless the run exits with the status and moves nothing.
expect_exit() {
  local expected="$1" label="$2"
  shift 2
  run "$@"
  local status=$?
  [ "$status" = "$expected" ] || fail "$label exited $status, not $expected"
  ! moved || fail "$label moved the branch"
}

manual_file 'owner/repo tests.yml ci/me'

# Bad inputs are rejected before anything is read.
expect_exit 2 "a bad repository" 'owner/repo;x' 5 "$HEAD_SHA" tests.yml
expect_exit 2 "a bad number" owner/repo 5x "$HEAD_SHA" tests.yml
expect_exit 2 "a short head" owner/repo 5 0123 tests.yml
expect_exit 2 "an uppercase head" owner/repo 5 "${HEAD_SHA//0/A}" tests.yml
expect_exit 2 "a workflow path" owner/repo 5 "$HEAD_SHA" ../tests.yml
expect_exit 2 "a workflow without yml" owner/repo 5 "$HEAD_SHA" tests.sh
expect_exit 2 "a missing argument" owner/repo 5 "$HEAD_SHA"
[ ! -s "$STUB_CALLS" ] || fail "a bad input reached gh"

# No file or no line for the repository and workflow is exit 6.
rm -f "$MANUAL_FILE"
expect_exit 6 "a missing file" owner/repo 5 "$HEAD_SHA" tests.yml
manual_file 'owner/repo other.yml ci/me' 'other/repo tests.yml ci/me'
expect_exit 6 "no line for the workflow" owner/repo 5 "$HEAD_SHA" tests.yml
[ ! -s "$STUB_CALLS" ] || fail "a missing line reached gh"

# A bad file or line fails closed, whichever line is bad.
for bad in 'owner/repo tests.yml' 'owner/repo tests.yml ci/me extra' 'owner/repo tests.yml -ci' 'owner/repo tests.yml ci/../me' 'owner/repo tests.yml ci/me.lock' 'owner/repo .github/workflows/tests.yml ci/me' '# a note'; do
  manual_file 'other/repo tests.yml ci/me' "$bad"
  expect_exit 1 "the line '$bad'" owner/repo 5 "$HEAD_SHA" tests.yml
done
manual_file 'owner/repo tests.yml ci/me'
cp "$MANUAL_FILE" "$TEST_DIRECTORY/real"
rm "$MANUAL_FILE"
ln -s "$TEST_DIRECTORY/real" "$MANUAL_FILE"
expect_exit 1 "a linked file" owner/repo 5 "$HEAD_SHA" tests.yml
rm "$MANUAL_FILE"

# A line naming a branch the script must never move is refused.
for branch in main master MAIN release/x production prod-ci deploy/me fix/thing; do
  manual_file "owner/repo tests.yml $branch"
  expect_exit 1 "the branch $branch" owner/repo 5 "$HEAD_SHA" tests.yml
done
manual_file 'owner/repo tests.yml trunk'
STUB_DEFAULT=trunk expect_exit 1 "the default branch" owner/repo 5 "$HEAD_SHA" tests.yml

# The pull request must be yours, open, ready, in this repository, at the head and free of `.github` changes.
manual_file 'owner/repo tests.yml ci/me'
export STUB_REFS="refs/heads/ci/me"
STUB_PULL_REQUEST="open false other $HEAD_SHA owner/repo 2 fix/thing" expect_exit 1 "a pull request of another author" owner/repo 5 "$HEAD_SHA" tests.yml
STUB_PULL_REQUEST="closed false me $HEAD_SHA owner/repo 2 fix/thing" expect_exit 1 "a closed pull request" owner/repo 5 "$HEAD_SHA" tests.yml
STUB_PULL_REQUEST="open true me $HEAD_SHA owner/repo 2 fix/thing" expect_exit 1 "a draft" owner/repo 5 "$HEAD_SHA" tests.yml
STUB_PULL_REQUEST="open false me $HEAD_SHA fork/repo 2 fix/thing" expect_exit 1 "a fork" owner/repo 5 "$HEAD_SHA" tests.yml
STUB_PULL_REQUEST="open false me 1111111111111111111111111111111111111111 owner/repo 2 fix/thing" expect_exit 1 "a pull request that moved" owner/repo 5 "$HEAD_SHA" tests.yml
STUB_PULL_REQUEST="open false me $HEAD_SHA owner/repo 3001 fix/thing" expect_exit 1 "too many files" owner/repo 5 "$HEAD_SHA" tests.yml
STUB_LATER_HEAD=1111111111111111111111111111111111111111 expect_exit 1 "a head that moved while it ran" owner/repo 5 "$HEAD_SHA" tests.yml
STUB_FILES=$'a.txt\n.github/workflows/tests.yml' expect_exit 1 "a change to .github" owner/repo 5 "$HEAD_SHA" tests.yml
STUB_PULL_REQUEST="open false me $HEAD_SHA owner/repo 2 ci/me" expect_exit 1 "the branch of the pull request" owner/repo 5 "$HEAD_SHA" tests.yml

# A branch with a run not completed is exit 7 and is never moved.
STUB_RUNS=1 expect_exit 7 "a busy branch" owner/repo 5 "$HEAD_SHA" tests.yml
grep -qF -- 'run list --repo owner/repo --branch ci/me --json status' "$STUB_CALLS" || fail "the busy check read another branch"

# A busy try is recorded, the next one within five minutes waits without calling `gh`, `due` says the same.
TRIES_FILE="$HOME/.cache/green-github-prs-watcher/manual-tries"
[ "$(grep -c " owner/repo#5 $HEAD_SHA tests.yml$" "$TRIES_FILE")" = 1 ] || fail "the busy try was not recorded"
expect_exit 7 "a try under five minutes after a busy one" owner/repo 5 "$HEAD_SHA" tests.yml
[ ! -s "$STUB_CALLS" ] || fail "a try under five minutes reached gh"
expect_exit 7 "due under five minutes" due owner/repo 5 "$HEAD_SHA" tests.yml
expect_exit 0 "due for another head" due owner/repo 5 1111111111111111111111111111111111111111 tests.yml
# Older tries let the next one run, the sixth busy try ends it with exit 8.
old=$(($(date +%s) - 600))
printf '%s owner/repo#5 %s tests.yml\n' "$old" "$HEAD_SHA" "$old" "$HEAD_SHA" "$old" "$HEAD_SHA" "$old" "$HEAD_SHA" "$old" "$HEAD_SHA" >"$TRIES_FILE"
expect_exit 0 "due after five minutes" due owner/repo 5 "$HEAD_SHA" tests.yml
[ ! -s "$STUB_CALLS" ] || fail "due reached gh"
STUB_RUNS=1 expect_exit 7 "the sixth busy try" owner/repo 5 "$HEAD_SHA" tests.yml
expect_exit 8 "a seventh try" owner/repo 5 "$HEAD_SHA" tests.yml
expect_exit 8 "due after six busy tries" due owner/repo 5 "$HEAD_SHA" tests.yml
rm -f "$TRIES_FILE"

# An idle branch is forced to the head, a missing one is created at it.
run owner/repo 5 "$HEAD_SHA" tests.yml || fail "the script refused an idle branch"
[ "$(cat "$TEST_DIRECTORY/output")" = "ci/me $HEAD_SHA" ] || fail "the script printed $(cat "$TEST_DIRECTORY/output")"
grep -qxF -- "api -X PATCH repos/owner/repo/git/refs/heads/ci/me -f sha=$HEAD_SHA -F force=true" "$STUB_CALLS" || fail "the script did not force the branch to the head"
! grep -q -- 'api -X POST' "$STUB_CALLS" || fail "the script created a branch that exists"
STUB_REFS="refs/heads/ci/me-other" run owner/repo 5 "$HEAD_SHA" tests.yml || fail "the script refused a missing branch"
grep -qxF -- "api -X POST repos/owner/repo/git/refs -f ref=refs/heads/ci/me -f sha=$HEAD_SHA" "$STUB_CALLS" || fail "the script did not create the branch at the head"
! grep -q -- 'api -X PATCH' "$STUB_CALLS" || fail "the script moved a branch that another name prefixes"

# The first line of the repository and workflow wins.
manual_file 'owner/repo tests.yml ci/first' 'owner/repo tests.yml ci/second'
STUB_REFS="refs/heads/ci/first" run owner/repo 5 "$HEAD_SHA" tests.yml
[ "$(cat "$TEST_DIRECTORY/output")" = "ci/first $HEAD_SHA" ] || fail "the script did not take the first line"

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "green-manual-tests.sh: all checks passed"
