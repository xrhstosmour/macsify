#!/bin/bash

# Names the `Herdr` app's tab and space after the `Claude Code` session title that
# `auto-session-title.sh` (or `/rename`) wrote, so both read the same and short
# enough to fit the sidebar. Runs on `Stop`, the title usually exists from the
# second turn on. Does nothing outside an app terminal, where `HC_TERMINAL_ID` is set.
#
# A name the person set is never touched. `LAST_FILE` remembers what this hook put
# there, a tab or space whose name is anything else was renamed by hand and stays.
# Without a record only an automatic name is taken over: a tab called by its number
# or `folder · Claude Code` (the `tab-names` mod), a space Herdr named itself.
# Reads the `Stop` hook payload on standard input.

[ -n "${HC_TERMINAL_ID:-}" ] || exit 0
[ "${HERDR_ENV:-}" != "1" ] || exit 0

MAX_LENGTH=28
COLORS=("🔴" "🟡" "🟢")
LAST_FILE="${TMPDIR:-/tmp}/herdr-application-title-${HC_TERMINAL_ID}"

transcript_path=$(jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$transcript_path" ] && [ -f "$transcript_path" ] || exit 0

title=$(grep '"type":"custom-title"' "$transcript_path" | tail -n 1 | jq -r '.customTitle // empty' 2>/dev/null)
[ -n "$title" ] || exit 0
[ "${#title}" -le "$MAX_LENGTH" ] || title="${title:0:$((MAX_LENGTH - 1))}…"

IFS=$'\t' read -r space_id space_name space_named tab_id tab_name < <(
  herdr-app ls 2>/dev/null | jq -r --arg terminal "$HC_TERMINAL_ID" '
    .spaces[] as $space | $space.tabs[] | select(any(.terminals[]; .terminal == $terminal))
    | [$space.id, $space.name, ($space.named // false | tostring), .id, .name] | @tsv'
)
[ -n "${tab_id:-}" ] || exit 0

last_tab=""
last_space=""
has_record="false"
if [ -f "$LAST_FILE" ]; then
  has_record="true"
  { IFS= read -r last_tab; IFS= read -r last_space; } <"$LAST_FILE"
fi

# A leading color is added by `herdr_tab_color`, kept across the rename.
color=""
bare_tab_name="$tab_name"
for candidate in "${COLORS[@]}"; do
  if [[ "$tab_name" == "$candidate "* ]]; then
    color="$candidate "
    bare_tab_name="${tab_name#"$candidate "}"
  fi
done

rename_tab="false"
rename_space="false"
if [ "$has_record" = "true" ]; then
  [ "$bare_tab_name" = "$last_tab" ] && rename_tab="true"
  [ "$space_name" = "$last_space" ] && rename_space="true"
else
  [[ "$bare_tab_name" =~ ^[0-9]+$ || "$bare_tab_name" == *" · Claude Code" ]] && rename_tab="true"
  [ "$space_named" = "false" ] && rename_space="true"
fi

[ "$rename_tab" = "true" ] && [ "$bare_tab_name" != "$title" ] && herdr-app "do" tab.rename --id "$tab_id" --name "${color}${title}" >/dev/null 2>&1
[ "$rename_space" = "true" ] && [ "$space_name" != "$title" ] && herdr-app "do" space.rename --id "$space_id" --name "$title" >/dev/null 2>&1

# Remember only what was applied, a side left alone keeps its old record or none.
{
  if [ "$rename_tab" = "true" ]; then echo "$title"; else echo "$last_tab"; fi
  if [ "$rename_space" = "true" ]; then echo "$title"; else echo "$last_space"; fi
} >"$LAST_FILE"
exit 0
