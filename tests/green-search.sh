#!/bin/bash

# Checks `green-search.sh`, the read-only searches of the green watcher. It
# searches only a `resolves-<slot>` worktree and the `Claude Code` and `OpenCode`
# sessions of that worktree's checkout, never those of another checkout, takes
# a pattern and never an option, runs no command through a `rg` or `sqlite3`
# configuration, and caps what it prints.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SEARCH_SCRIPT="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/green-search.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

failures=0
fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

mkdir -p "$TEST_DIRECTORY/developer/worktrees/service/resolves-2" "$TEST_DIRECTORY/home"
DEVELOPER="$(cd "$TEST_DIRECTORY/developer" && pwd -P)"
WORKTREE="$DEVELOPER/worktrees/service/resolves-2"
export REVIEW_DEVELOPER_DIRECTORY="$DEVELOPER"
export HOME="$TEST_DIRECTORY/home"
export CLAUDE_CONFIG_DIR="$TEST_DIRECTORY/claude"
export XDG_DATA_HOME="$TEST_DIRECTORY/data"

printf 'the limit is 42\n' >"$WORKTREE/a.txt"
printf 'ignored.txt\n' >"$WORKTREE/.gitignore"
printf 'the limit is 42\n' >"$WORKTREE/ignored.txt"
git init --quiet "$WORKTREE"

[ "$("$SEARCH_SCRIPT" code "$WORKTREE" 'limit is')" = "a.txt:1:the limit is 42" ] || fail "the search script did not print the matching line of the worktree"
"$SEARCH_SCRIPT" files "$WORKTREE" | grep -qx a.txt || fail "the search script did not list a file of the worktree"
"$SEARCH_SCRIPT" files "$WORKTREE" | grep -q ignored.txt && fail "the search script listed an ignored file"

# A pattern that looks like an option stays a pattern, and a `rg` configuration is never read, either could run a command through `--pre`.
# shellcheck disable=SC2016
printf '#!/bin/sh\ntouch %s/pre-ran\ncat "$1"\n' "$TEST_DIRECTORY" >"$TEST_DIRECTORY/pre.sh"
chmod +x "$TEST_DIRECTORY/pre.sh"
printf -- '--pre=%s/pre.sh\n' "$TEST_DIRECTORY" >"$TEST_DIRECTORY/ripgreprc"
RIPGREP_CONFIG_PATH="$TEST_DIRECTORY/ripgreprc" "$SEARCH_SCRIPT" code "$WORKTREE" 'limit' >/dev/null
"$SEARCH_SCRIPT" code "$WORKTREE" "--pre=$TEST_DIRECTORY/pre.sh" >/dev/null 2>&1
[ ! -e "$TEST_DIRECTORY/pre-ran" ] || fail "the search script ran a command through --pre"

"$SEARCH_SCRIPT" code "$WORKTREE" '' >/dev/null 2>&1 && fail "the search script accepted an empty pattern"
"$SEARCH_SCRIPT" code "$WORKTREE" $'limit\nis' >/dev/null 2>&1 && fail "the search script accepted a pattern of two lines"
"$SEARCH_SCRIPT" code "$WORKTREE" limit extra >/dev/null 2>&1 && fail "the search script accepted an extra argument"
mkdir -p "$DEVELOPER/worktrees/service/other" "$DEVELOPER/service"
"$SEARCH_SCRIPT" code "$DEVELOPER/worktrees/service/other" limit >/dev/null 2>&1 && fail "the search script searched a worktree that is not resolves"
for name in resolves resolves-4; do
  mkdir -p "$DEVELOPER/worktrees/service/$name"
  "$SEARCH_SCRIPT" code "$DEVELOPER/worktrees/service/$name" limit >/dev/null 2>&1 && fail "the search script searched $name, not a slot"
done
"$SEARCH_SCRIPT" code "$DEVELOPER/service" limit >/dev/null 2>&1 && fail "the search script searched a checkout"
ln -s "$WORKTREE" "$TEST_DIRECTORY/link"
"$SEARCH_SCRIPT" code "$TEST_DIRECTORY/link" limit >/dev/null 2>&1 && fail "the search script followed a symlinked worktree"

# Sessions of the checkout and its worktrees are searched, those of another checkout are not, even one whose name starts with this one.
encode() {
  printf '%s' "${1//[^A-Za-z0-9]/-}"
}
transcript() {
  local folder="$1" name="$2" text="$3"
  mkdir -p "$CLAUDE_CONFIG_DIR/projects/$(encode "$folder")"
  printf '{"cwd":"%s","text":"%s"}\n' "$folder" "$text" >>"$CLAUDE_CONFIG_DIR/projects/$(encode "$folder")/$name.jsonl"
}
transcript "$DEVELOPER/service" one "checkout figure 17 came from the export"
transcript "$DEVELOPER/worktrees/service/fix-thing" two "worktree figure 17 came from the export"
transcript "$DEVELOPER/other" three "other figure 17 came from the export"
# The folder of a `service-api` worktree reads like one of `service`, only its `cwd` tells them apart.
transcript "$DEVELOPER/worktrees/service-api/fix" four "other lookalike figure 17 came from the export"
# A long transcript record is cut around the match.
transcript "$DEVELOPER/service" one "$(printf 'x%.0s' {1..2000}) long figure 17 $(printf 'y%.0s' {1..2000})"

mkdir -p "$XDG_DATA_HOME/opencode"
sqlite3 "$XDG_DATA_HOME/opencode/opencode.db" <<EOF
CREATE TABLE session (id text PRIMARY KEY, directory text NOT NULL);
CREATE TABLE part (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, data text NOT NULL);
INSERT INTO session VALUES ('ses_service', '$DEVELOPER/worktrees/service/fix-thing'), ('ses_other', '$DEVELOPER/other');
INSERT INTO part VALUES ('one', 'ses_service', 1, '{"text":"opencode figure 17 came from the export"}'), ('two', 'ses_other', 2, '{"text":"other opencode figure 17"}');
EOF
# A `~/.sqliterc` would run its commands before the query.
printf '.shell touch %s/sqliterc-ran\n' "$TEST_DIRECTORY" >"$HOME/.sqliterc"

"$SEARCH_SCRIPT" sessions "$WORKTREE" 'figure 17' >"$TEST_DIRECTORY/sessions" 2>&1
grep -q 'claude:.*one.jsonl:.*checkout figure 17' "$TEST_DIRECTORY/sessions" || fail "the search script missed a session of the checkout"
grep -q 'claude:.*two.jsonl:.*worktree figure 17' "$TEST_DIRECTORY/sessions" || fail "the search script missed a session of a worktree of the checkout"
grep -q 'opencode:ses_service:.*opencode figure 17' "$TEST_DIRECTORY/sessions" || fail "the search script missed an OpenCode session of the checkout"
grep -q other "$TEST_DIRECTORY/sessions" && fail "the search script printed a session of another checkout"
grep -q 'long figure 17' "$TEST_DIRECTORY/sessions" || fail "the search script missed the match in a long record"
awk 'length > 600 { found = 1 } END { exit !found }' "$TEST_DIRECTORY/sessions" && fail "the search script printed a whole long record"
[ ! -e "$TEST_DIRECTORY/sqliterc-ran" ] || fail "the search script ran a command of ~/.sqliterc"

# A `_` in the checkout is a plain character, not a wildcard that would take in `myxapp`.
mkdir -p "$DEVELOPER/worktrees/my_app/resolves-1"
sqlite3 "$XDG_DATA_HOME/opencode/opencode.db" <<EOF
INSERT INTO session VALUES ('ses_my_app', '$DEVELOPER/worktrees/my_app/fix'), ('ses_lookalike', '$DEVELOPER/worktrees/myxapp/fix');
INSERT INTO part VALUES ('three', 'ses_my_app', 3, '{"text":"my app figure 17"}'), ('four', 'ses_lookalike', 4, '{"text":"lookalike figure 17"}');
EOF
"$SEARCH_SCRIPT" sessions "$DEVELOPER/worktrees/my_app/resolves-1" 'figure 17' >"$TEST_DIRECTORY/underscore" 2>&1
grep -q 'opencode:ses_my_app:' "$TEST_DIRECTORY/underscore" || fail "the search script missed an OpenCode session of a checkout with a _"
grep -q ses_lookalike "$TEST_DIRECTORY/underscore" && fail "the search script read a _ of the checkout as a wildcard"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "PASS: green search script"
