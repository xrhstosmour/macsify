#!/bin/bash

# Weekly speed log for the `audit-home-network` Speed mode. Measures with
# `networkQuality`, appends one row to a CSV the user chose, and posts a
# notification when the last three rows are all below half the contracted
# download speed. Drafting the complaint is left to the skill, a script cannot
# write a fair one. Installed as a launch agent only by the skill, after the
# user approves it, never by `setup/`, so it never lands on a work profile.
# The CSV holds speeds and the interface type only, never an address or SSID.
# Usage:
#   speed-log.sh <csv-path> <contracted-download-mbps> <contracted-upload-mbps>

# `launchd` starts agents with a bare `PATH`, `Homebrew` is not on it.
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

set -eu

CSV_FILE="${1:?CSV path required}"
CONTRACTED_DOWNLOAD="${2:?contracted download in Mbps required}"
CONTRACTED_UPLOAD="${3:?contracted upload in Mbps required}"
HEADER="date,download_mbps,upload_mbps,latency_ms,contracted_download_mbps,contracted_upload_mbps,download_percent,interface,transmit_rate_mbps,status"
STREAK=3

for speed in "$CONTRACTED_DOWNLOAD" "$CONTRACTED_UPLOAD"; do
    if ! [[ "$speed" =~ ^[1-9][0-9]*$ ]]; then
        echo "Contracted speeds are whole Mbps above zero, got '$speed'." >&2
        exit 1
    fi
done

if [ ! -s "$CSV_FILE" ]; then
    mkdir -p "$(dirname "$CSV_FILE")"
    echo "$HEADER" >"$CSV_FILE"
fi

# Fail before the measurement, a CSV that cannot be written would waste it.
if [ ! -w "$CSV_FILE" ]; then
    echo "Cannot write to '$CSV_FILE'." >&2
    exit 1
fi

date=$(date '+%Y-%m-%d %H:%M')

# A failed run is logged as failed and breaks the streak, an offline laptop is
# not evidence against the provider.
if ! result=$(networkQuality -c 2>/dev/null) || [ "$(jq -r '.dl_throughput // empty' <<<"$result")" = "" ]; then
    echo "$date,,,,$CONTRACTED_DOWNLOAD,$CONTRACTED_UPLOAD,,,,failed" >>"$CSV_FILE"
    exit 0
fi

download=$(jq -r '.dl_throughput / 1000000 | floor' <<<"$result")
upload=$(jq -r '(.ul_throughput // 0) / 1000000 | floor' <<<"$result")
latency=$(jq -r '(.base_rtt // 0) | floor' <<<"$result")
interface=$(jq -r '(.other["interface-type"] // {}) | keys | first // "unknown"' <<<"$result")
percent=$((download * 100 / CONTRACTED_DOWNLOAD))

# Over Wi-Fi a slow week can be the Wi-Fi, the transmit rate tells the two apart.
transmit_rate=""
if [ "$interface" = "wifi" ]; then
    transmit_rate=$(system_profiler SPAirPortDataType 2>/dev/null | awk -F': ' '/Transmit Rate/ { print $2; exit }')
fi

echo "$date,$download,$upload,$latency,$CONTRACTED_DOWNLOAD,$CONTRACTED_UPLOAD,$percent,$interface,$transmit_rate,measured" >>"$CSV_FILE"

below=$(tail -n "$STREAK" "$CSV_FILE" | awk -F, '$10 == "measured" && $7 < 50 { count++ } END { print count + 0 }')
if [ "$below" -ge "$STREAK" ]; then
    osascript -e 'display notification "Three weeks below half the contracted speed. Run /audit-home-network to draft the complaint." with title "Speed log"' 2>/dev/null || true
    echo "streak"
fi
