#!/usr/bin/env bash
# The read-only searches of the `green-github-prs-watcher` investigation, scoped to the repository of one `resolves` worktree made by `green-worktree.sh`.
# Allowed in claude/settings.json by its path, in place of `rg`, which runs any command through `--pre`, and of a `Read` of every past session, which a comment could steer into another repository's transcripts.
# The caller gives only a pattern, never an option or a path, so `rg` runs with `--no-config` and the fixed paths below, and `sqlite3` with `-init /dev/null` so a `~/.sqliterc` runs nothing.
# Output is capped, a session line is a whole transcript record, so only the text around a match is printed.
#
# Usage: green-search.sh files <worktree>
#        green-search.sh code <worktree> <pattern>
#        green-search.sh sessions <worktree> <pattern>
#   files     lists the files of the worktree, ignored ones left out
#   code      prints the matching lines of the worktree as `<file>:<line>:<text>`
#   sessions  prints the text around each match in the `Claude Code` and `OpenCode` sessions of the checkout and its worktrees as `<session>:<text>`
# The pattern is a `rg` regular expression of one line.
# The developer directory is `~/Developer`, `REVIEW_DEVELOPER_DIRECTORY` replaces it for the tests, the session folders follow `CLAUDE_CONFIG_DIR` and `XDG_DATA_HOME` as the agents do.

set -e

usage() {
  echo "usage: green-search.sh files <worktree> | code <worktree> <pattern> | sessions <worktree> <pattern>" >&2
  exit 2
}

[ $# -ge 2 ] || usage
command="$1"
worktree="$2"
pattern="${3-}"
case "$command" in
  files) [ $# -eq 2 ] || usage ;;
  code | sessions) [ $# -eq 3 ] || usage ;;
  *) usage ;;
esac
if [ "$command" != files ] && { [ -z "$pattern" ] || [[ $pattern == *$'\n'* ]] || [ "${#pattern}" -gt 200 ]; }; then
  echo "the pattern must be one line of at most 200 characters" >&2
  exit 2
fi

# The worktree must be the top of a `resolves` worktree under the developer directory, compared as physical paths so a symlink cannot point it elsewhere.
developer="$(cd "${REVIEW_DEVELOPER_DIRECTORY:-$HOME/Developer}" && pwd -P)"
if [ ! -d "$worktree" ] || [ -L "$worktree" ]; then
  echo "not a resolves worktree: $worktree" >&2
  exit 2
fi
worktree="$(cd "$worktree" && pwd -P)"
checkout="${worktree#"$developer"/worktrees/}"
checkout="${checkout%/resolves}"
if [[ $worktree != "$developer/worktrees/$checkout/resolves" ]] || ! [[ $checkout =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "not a resolves worktree: $worktree" >&2
  exit 2
fi

search() {
  rg --no-config --no-messages --max-columns 300 --max-columns-preview "$@"
}

case "$command" in
  files)
    # The path is explicit, without one `rg` reads its standard input when that is not a terminal.
    (cd "$worktree" && search --files -- .) | sed 's|^\./||' | head -n 2000
    ;;
  code)
    (cd "$worktree" && search --line-number --max-count 20 -e "$pattern" -- .) | sed 's|^\./||' | head -n 200
    ;;
  sessions)
    # `Claude Code` names a session folder after the path with every other character turned into `-`, so worktrees of another checkout whose name starts with this one and a `-` match the folder pattern too, the `cwd` of each transcript tells them apart.
    projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
    checkout_folder="${developer}/${checkout}"
    worktrees_folder="${developer}/worktrees/${checkout}"
    folders=()
    if [ -d "$projects" ]; then
      cd "$projects"
      for folder in "${checkout_folder//[^A-Za-z0-9]/-}" "${worktrees_folder//[^A-Za-z0-9]/-}"-*; do
        if [ -d "$folder" ] && [ ! -L "$folder" ]; then
          folders+=("$folder")
        fi
      done
    fi
    transcripts=()
    if [ "${#folders[@]}" -gt 0 ]; then
      while IFS= read -r transcript; do
        transcripts+=("$transcript")
      done < <(search --files-with-matches --fixed-strings --glob '*.jsonl' -e "\"cwd\":\"$checkout_folder\"" -e "\"cwd\":\"$checkout_folder/" -e "\"cwd\":\"$worktrees_folder/" -- "${folders[@]}" || true)
    fi
    context=".{0,200}(?:$pattern).{0,200}"
    {
      if [ "${#transcripts[@]}" -gt 0 ]; then
        search --only-matching --with-filename --max-count 20 -e "$context" -- "${transcripts[@]}" | sed 's/^/claude:/' || true
      fi
      # `OpenCode` keeps its sessions in one database, a session belongs to the checkout by its folder. The query carries the folders, so one with a quote is left out, and compares a prefix with `substr`, a `LIKE` would read a `_` or `%` of the path as a wildcard.
      database="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/opencode.db"
      if [ -f "$database" ] && [[ $developer != *\'* ]]; then
        # shellcheck disable=SC2016
        sqlite3 -init /dev/null -readonly -separator ' ' "$database" \
          "SELECT part.session_id, replace(part.data, char(10), ' ') FROM part JOIN session ON session.id = part.session_id WHERE session.directory = '$checkout_folder' OR substr(session.directory, 1, length('$worktrees_folder/')) = '$worktrees_folder/' ORDER BY part.time_created" 2>/dev/null |
          search --only-matching --max-count 20 --replace 'opencode:${session}:${text}' -e "^(?P<session>\S+) .*?(?P<text>$context)" || true
      fi
    } | cut -c1-600 | head -n 100
    ;;
esac
