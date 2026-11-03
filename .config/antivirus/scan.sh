#!/bin/bash

# Scans files with `ClamAV` and moves anything infected into a quarantine folder
# next to a note saying where it came from, when and why. Never deletes, a false
# alarm stays recoverable. `macOS`'s own `XProtect` stays on, this is an extra layer.
#
# Usage:
#   scan.sh path...             Scan every file under the paths.
#   scan.sh --recent path...    Scan only files changed in the last 10 minutes, for the
#                               folder watchers, `launchd` does not say which file changed.

# `launchd` starts agents with a bare `PATH`, `Homebrew` is not on it.
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

set -u

QUARANTINE_DIRECTORY="${ANTIVIRUS_QUARANTINE_DIRECTORY:-$HOME/.local/share/antivirus/quarantine}"
LOG_FILE="${ANTIVIRUS_LOG_FILE:-$HOME/.local/share/antivirus/scan.log}"
RECENT_MINUTES=10

recent="false"
if [ "${1:-}" = "--recent" ]; then
    recent="true"
    shift
fi

mkdir -p "$QUARANTINE_DIRECTORY" "$(dirname "$LOG_FILE")"
chmod 700 "$QUARANTINE_DIRECTORY"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG_FILE"
}

# Move an infected file into quarantine with its note, execute bits removed.
quarantine() {
    local file="$1"
    local signature="$2"
    local name
    local target

    name="$(date '+%Y%m%d%H%M%S')-$(basename "$file")"
    target="$QUARANTINE_DIRECTORY/$name"

    mv "$file" "$target" || { log "ERROR could not quarantine '$file'"; return 1; }
    chmod a-x "$target"
    printf 'Origin: %s\nQuarantined: %s\nReason: %s\n' "$file" "$(date '+%Y-%m-%d %H:%M:%S')" "$signature" >"$target.note"
    log "QUARANTINED '$file' as '$target', $signature"
}

scan_file() {
    local file="$1"
    local output
    local status

    output=$(clamscan --no-summary "$file" 2>&1)
    status=$?

    case "$status" in
    0) ;;
    1) quarantine "$file" "$(sed -n 's|^.*: \(.*\) FOUND$|\1|p' <<<"$output" | head -n 1)" ;;
    *) log "ERROR scanning '$file': $output" ;;
    esac
}

if ! command -v clamscan >/dev/null 2>&1; then
    log "ERROR clamscan not found"
    exit 2
fi

for path in "$@"; do
    [ -e "$path" ] || { log "SKIPPED missing path '$path'"; continue; }

    # Dependency and repository folders hold thousands of files and test fixtures
    # that look like malware to a signature, nothing in them arrives from outside.
    find_arguments=("$path" \( -name node_modules -o -name .git -o -name .venv \) -prune -o -type f -not -path "$QUARANTINE_DIRECTORY/*")
    [ "$recent" = "true" ] && find_arguments+=(-mmin "-$RECENT_MINUTES")
    find_arguments+=(-print0)

    while IFS= read -r -d '' file; do
        scan_file "$file"
    done < <(find "${find_arguments[@]}")
done

log "FINISHED scan of: $*"
