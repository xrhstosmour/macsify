#!/bin/bash

# Reports `Claude Code`'s state to the `Herdr` app so its sidebar shows
# working, blocked and done. `herdr-core` does not recognise agents by name, a
# program has to say it with an `OSC 7501` escape on its terminal. Does nothing
# outside an app terminal, which is where `HC_TERMINAL_ID` is set. Hooks have no
# terminal of their own, so the escape goes to the controlling one, or to the
# parent's when there is none.
# Usage:
#   herdr-application-status.sh <working|done|idle|clear|notification>
# `notification` reads the hook payload on standard input and reports `blocked`
# only for a permission or question prompt, other notifications change nothing.

[ -n "${HC_TERMINAL_ID:-}" ] || exit 0

state="${1:-}"
fields=""

case "$state" in
  working | done | idle | clear) ;;
  notification)
    notification_type=$(jq -r '.notification_type // empty' 2>/dev/null)
    case "$notification_type" in
      permission_prompt) fields=":kind=permission" ;;
      elicitation_dialog) fields=":kind=question" ;;
      *) exit 0 ;;
    esac
    state="blocked"
    ;;
  *) exit 0 ;;
esac

# `HERDR_APPLICATION_STATUS_TTY` points the test at a file instead of a terminal.
terminal="${HERDR_APPLICATION_STATUS_TTY:-/dev/tty}"
if ! { printf '\033]7501;state=%s:app=claude-code%s\033\\' "$state" "$fields" >"$terminal"; } 2>/dev/null; then
  parent_terminal=$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ')
  case "$parent_terminal" in
    "" | "?" | "??") exit 0 ;;
  esac
  printf '\033]7501;state=%s:app=claude-code%s\033\\' "$state" "$fields" >"/dev/$parent_terminal" 2>/dev/null || true
fi
exit 0
