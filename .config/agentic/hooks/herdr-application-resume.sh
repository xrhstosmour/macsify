#!/bin/bash

# Remembers which coding agent session runs in a `Herdr` app terminal, so the
# terminal's fresh shell can bring it back after a reboot. `herdr-core` keeps a
# terminal's shell and folder across a restart but not the agent inside it, and
# the app has no event for that, so a hook records it while the agent runs and
# `.config/fish/conf.d/herdr-agent-resume.fish` reads it back. The record is a
# label on the `herdr-core` terminal, so it lives exactly as long as the terminal
# and needs no cleanup. A record that is still there when a shell starts means
# the agent never exited by itself, `Claude Code`'s `SessionEnd` hook and the
# `fish` side forget it when the agent returns. Does nothing outside an app
# terminal, which is where `HC_TERMINAL_ID` is set. Of the flags the agent was
# started with only a short list that changes how it behaves is kept, read from
# the terminal's foreground command, so `--api-key` style secrets, the first
# prompt and the resume flags themselves never reach the record.
# Usage:
#   herdr-application-resume.sh save claude          (hook payload on standard input)
#   herdr-application-resume.sh save opencode <session> <folder>
#   herdr-application-resume.sh forget
#   herdr-application-resume.sh end                  (`SessionEnd` payload on standard input)
#   herdr-application-resume.sh show <shell-pid>     (prints `agent session folder [flag...]`, tab separated)

[ -n "${HC_TERMINAL_ID:-}" ] || exit 0

LABEL="resume.record"

# The session ID is used as a command argument by the shell, so it is checked
# here, and one starting with a dash would be read as a flag.
valid_session() {
  case "$1" in
    "" | -* | *[!A-Za-z0-9_-]*) return 1 ;;
  esac
}

# The folder travels in a tab separated line, so a tab or newline in it would
# move the words after it into the flags.
valid_folder() {
  case "$1" in
    *$'\t'* | *$'\n'*) return 1 ;;
  esac
  [ -d "$1" ]
}

# Keeps the allowlisted flags of the terminal's foreground command, as a `JSON`
# array. A flag with a value keeps it only when it follows as its own word.
kept_flags() {
  hc get "$HC_TERMINAL_ID" --json 2>/dev/null | jq -c '
    (.foreground.argv // []) as $argv
    | (["--permission-mode", "--model", "-m", "--agent", "--add-dir"]) as $values
    | (["--dangerously-skip-permissions"]) as $booleans
    | [range(1; ($argv | length)) as $i
        | $argv[$i] as $word
        | if ($booleans | index($word)) then $word
          elif ($values | index($word)) and ($argv[$i + 1] | type == "string") and ($argv[$i + 1] | test("^[^-\\t\\n][^\\t\\n]*$"))
          then $word, $argv[$i + 1]
          else empty end]' 2>/dev/null || echo '[]'
}

case "${1:-}" in
  save)
    agent="${2:-}"
    case "$agent" in
      claude)
        payload=$(cat)
        session=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
        folder=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
        ;;
      opencode)
        session="${3:-}"
        folder="${4:-}"
        ;;
      *) exit 0 ;;
    esac
    valid_session "$session" || exit 0
    valid_folder "$folder" || exit 0
    flags=$(kept_flags)
    [ -n "$flags" ] || flags='[]'
    record=$(jq -nc --arg agent "$agent" --arg session "$session" --arg folder "$folder" --argjson flags "$flags" \
      '{agent: $agent, session: $session, folder: $folder, flags: $flags}') || exit 0
    hc label "$HC_TERMINAL_ID" "$LABEL=$record" >/dev/null 2>&1
    ;;
  forget)
    hc label "$HC_TERMINAL_ID" "$LABEL=" >/dev/null 2>&1
    ;;
  end)
    # `clear` ends a session to start the next one, which saves itself, and
    # anything but the person leaving, a reboot included, must keep the record.
    reason=$(jq -r '.reason // empty' 2>/dev/null)
    case "$reason" in
      prompt_input_exit | logout) hc label "$HC_TERMINAL_ID" "$LABEL=" >/dev/null 2>&1 ;;
    esac
    ;;
  show)
    # A shell started inside the terminal later is not the terminal's own and
    # must not resume anything, only the shell `herdr-core` started is. One
    # `jq` pass reads the label, checks every field and prints the line, the
    # first prompt of every terminal shell runs this.
    [ -n "${2:-}" ] || exit 0
    line=$(hc get "$HC_TERMINAL_ID" --json 2>/dev/null | jq -r --arg label "$LABEL" --arg shell "$2" '
      select((.pid | tostring) == $shell)
      | (.labels[$label] // empty | fromjson? | objects) as $record
      | select(($record.agent == "claude") or ($record.agent == "opencode"))
      | select(($record.session | type == "string") and ($record.session | test("^[A-Za-z0-9][A-Za-z0-9_-]*$")))
      | select(($record.folder | type == "string") and ($record.folder | test("[\\t\\n]") | not))
      | (($record.flags // []) | map(select(type == "string" and test("^[^\\t\\n]+$")))) as $flags
      | ([$record.agent, $record.session, $record.folder] + $flags) | join("\t")' 2>/dev/null)
    [ -n "$line" ] || exit 0
    folder=$(printf '%s' "$line" | cut -f3)
    [ -d "$folder" ] || exit 0
    printf '%s\n' "$line"
    ;;
esac
exit 0
