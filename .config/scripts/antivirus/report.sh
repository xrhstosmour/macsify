#!/bin/bash

# Turns the scan log into a short plain-English report, newest findings since the
# last report. Every finding says how bad it is (HIGH, CHECK, OK), what it is and
# what to do. Written as a template, no model and no network call.

# `launchd` starts agents with a bare `PATH`, `Homebrew` is not on it.
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

set -u

DATA_DIRECTORY="${ANTIVIRUS_DATA_DIRECTORY:-$HOME/.local/share/antivirus}"
LOG_FILE="${ANTIVIRUS_LOG_FILE:-$DATA_DIRECTORY/scan.log}"
REPORT_DIRECTORY="${ANTIVIRUS_REPORT_DIRECTORY:-$HOME/Documents/antivirus-reports}"
MARKER_FILE="$DATA_DIRECTORY/report.marker"

mkdir -p "$REPORT_DIRECTORY"
[ -f "$LOG_FILE" ] || touch "$LOG_FILE"

total=$(wc -l <"$LOG_FILE" | tr -d ' ')
seen=$(cat "$MARKER_FILE" 2>/dev/null || echo 0)
[ "$seen" -gt "$total" ] && seen=0
new=$(tail -n +"$((seen + 1))" "$LOG_FILE")

high=$(grep -c ' QUARANTINED ' <<<"$new")
check=$(grep -c ' CHECK ' <<<"$new")
report="$REPORT_DIRECTORY/$(date '+%Y-%m-%d-%H%M%S').txt"

{
    echo "$high threat(s) quarantined, $check item(s) to check"
    grep ' QUARANTINED ' <<<"$new" | while IFS= read -r line; do
        echo "HIGH: ${line#* QUARANTINED }. Look at the note next to it in quarantine, delete it if you do not know it."
    done
    grep ' CHECK ' <<<"$new" | while IFS= read -r line; do
        echo "CHECK: ${line#* CHECK }. Did you install something this week? If not, remove it."
    done
    grep ' ERROR ' <<<"$new" | while IFS= read -r line; do
        echo "CHECK: ${line#* ERROR }. The scan could not finish, run it again."
    done
    [ "$high" -eq 0 ] && [ "$check" -eq 0 ] && echo "OK: nothing found."
    echo "Signatures last updated: $(stat -f '%Sm' "$(brew --prefix 2>/dev/null)/var/lib/clamav/daily.cld" 2>/dev/null || echo unknown)"
} >"$report"

echo "$total" >"$MARKER_FILE"
echo "$report"
