#!/bin/bash

# Lists what starts by itself and logs anything new since the saved baseline, the
# one thing a file scanner cannot see: a program that is not known bad yet but
# quietly made itself permanent. The first run only saves the baseline. A new item
# is logged as `CHECK`, the baseline then absorbs it so it is reported once.

set -u

DATA_DIRECTORY="${ANTIVIRUS_DATA_DIRECTORY:-$HOME/.local/share/antivirus}"
LOG_FILE="${ANTIVIRUS_LOG_FILE:-$DATA_DIRECTORY/scan.log}"
BASELINE_FILE="$DATA_DIRECTORY/startup.baseline"
STARTUP_DIRECTORIES="${ANTIVIRUS_STARTUP_DIRECTORIES:-$HOME/Library/LaunchAgents:/Library/LaunchAgents:/Library/LaunchDaemons}"

mkdir -p "$DATA_DIRECTORY"

current=$(mktemp)
trap 'rm -f "$current"' EXIT

# Launch agent and daemon property lists, one path per line.
IFS=':' read -r -a directories <<<"$STARTUP_DIRECTORIES"
for directory in "${directories[@]}"; do
    [ -d "$directory" ] && find "$directory" -maxdepth 1 -name '*.plist' -print
done >"$current"

# Login items, skipped where `osascript` is not available.
if [ -z "${ANTIVIRUS_STARTUP_DIRECTORIES:-}" ] && command -v osascript >/dev/null 2>&1; then
    osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null |
        tr ',' '\n' | sed 's/^ *//; s/^/login item: /' | grep -v '^login item: $' >>"$current"
fi

sort -u -o "$current" "$current"

if [ ! -f "$BASELINE_FILE" ]; then
    cp "$current" "$BASELINE_FILE"
    printf '%s INFO saved the startup baseline, %s items\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(wc -l <"$current" | tr -d ' ')" >>"$LOG_FILE"
    exit 0
fi

while IFS= read -r item; do
    printf '%s CHECK new startup item: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$item" >>"$LOG_FILE"
done < <(comm -13 "$BASELINE_FILE" "$current")

# Merge instead of replace, so an item that went away and returns is not reported twice.
sort -u "$BASELINE_FILE" "$current" -o "$BASELINE_FILE"
