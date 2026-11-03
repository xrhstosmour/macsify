#!/bin/bash

# Constant variable of the scripts' working directory to use for relative paths.
SYNCTHING_HELPER_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import log functions.
source "$SYNCTHING_HELPER_SCRIPT_DIRECTORY/logs.sh"

# Function to read the API key out of a `Syncthing` `config.xml`.
# Usage:
#   syncthing_api_key "$HOME/Library/Application Support/Syncthing/config.xml"
syncthing_api_key() {
    sed -n 's|.*<apikey>\(.*\)</apikey>.*|\1|p' "$1" | head -n 1
}

# Function to print the GUI URL on the loopback address, with the port and the
# `HTTP` or `HTTPS` scheme the configuration currently uses. Always loopback, so
# a GUI that was listening on every interface is still reached locally.
# Usage:
#   syncthing_gui_url "$HOME/Library/Application Support/Syncthing/config.xml"
syncthing_gui_url() {
    local config_file="$1"
    local scheme="http"
    local address

    grep -q '<gui [^>]*tls="true"' "$config_file" && scheme="https"
    # Only the GUI's own address, devices carry `<address>dynamic</address>` too.
    address=$(sed -n '/<gui /,/<\/gui>/s|.*<address>\(.*\)</address>.*|\1|p' "$config_file" | head -n 1)

    printf '%s://127.0.0.1:%s\n' "$scheme" "${address##*:}"
}

# Function to send a JSON body to the `Syncthing` REST API. The key goes through
# a header file and the body through standard input, so neither shows up in the
# process list. `--insecure` is only for the loopback self-signed certificate.
# Usage:
#   syncthing_request "PATCH" "https://127.0.0.1:8384" "$key" "/rest/config/options" '{"relaysEnabled":false}'
syncthing_request() {
    local method="$1"
    local gui_url="$2"
    local api_key="$3"
    local path="$4"
    local body="${5:-}"

    if [ -n "$body" ]; then
        printf '%s' "$body" | curl --silent --fail --insecure --request "$method" \
            --header @<(printf 'X-API-Key: %s' "$api_key") \
            --header 'Content-Type: application/json' \
            --data @- "$gui_url$path"
    else
        curl --silent --fail --insecure --request "$method" \
            --header @<(printf 'X-API-Key: %s' "$api_key") "$gui_url$path"
    fi
}

# Function to apply the hardened options and GUI settings. Global discovery, relays
# and `NAT` traversal are off so the Mac announces itself to no third party, devices
# connect by address (`Tailscale` or the local network). Usage reporting and crash
# reporting are off, the GUI listens on loopback only, over `HTTPS`.
# Usage:
#   harden_syncthing "https://127.0.0.1:8384" "$key"
harden_syncthing() {
    local gui_url="$1"
    local api_key="$2"

    syncthing_request PATCH "$gui_url" "$api_key" /rest/config/options \
        '{"globalAnnounceEnabled":false,"relaysEnabled":false,"natEnabled":false,"urAccepted":-1,"crashReportingEnabled":false,"startBrowser":false}'
    syncthing_request PATCH "$gui_url" "$api_key" /rest/config/gui \
        "{\"address\":\"127.0.0.1:${gui_url##*:}\",\"useTLS\":true,\"insecureAdminAccess\":false,\"insecureSkipHostcheck\":false,\"insecureAllowFrameLoading\":false}"

    log_success "Applied the hardened 'Syncthing' options and GUI settings."
}
