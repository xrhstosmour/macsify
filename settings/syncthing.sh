#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
SYNCTHING_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import functions and flags.
source "$SYNCTHING_SCRIPT_DIRECTORY/../helpers/logs.sh"

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

# Run only when executed, `tests/syncthing.sh` sources this file for the functions.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  SYNCTHING_CONFIG_FILE="$HOME/Library/Application Support/Syncthing/config.xml"

  if [ ! -d "/Applications/Syncthing.app" ]; then
      log_warning "'Syncthing' not found, skipping its hardening."
      exit 0
  fi

  # The first start writes the configuration, wait for it.
  if [ ! -f "$SYNCTHING_CONFIG_FILE" ]; then
      log_info "Starting 'Syncthing' once to create its configuration..."
      open -g -a Syncthing

      for _ in $(seq 1 30); do
          [ -f "$SYNCTHING_CONFIG_FILE" ] && break
          sleep 1
      done
  fi

  if [ ! -f "$SYNCTHING_CONFIG_FILE" ]; then
      log_warning "'Syncthing' did not create its configuration, start it and rerun this script."
      exit 0
  fi

  api_key=$(syncthing_api_key "$SYNCTHING_CONFIG_FILE")
  gui_url=$(syncthing_gui_url "$SYNCTHING_CONFIG_FILE")

  # The REST API only answers while the application runs.
  if ! syncthing_request GET "$gui_url" "$api_key" /rest/system/ping >/dev/null 2>&1; then
      log_warning "'Syncthing' is not answering at '$gui_url', start it and rerun this script."
      exit 0
  fi

  harden_syncthing "$gui_url" "$api_key"

  # Saving the GUI settings restarts its listener, read the new address and scheme.
  sleep 3
  gui_url=$(syncthing_gui_url "$SYNCTHING_CONFIG_FILE")

  # The GUI password is asked for, never stored in this repository. An existing
  # user means it was set already, so a rerun does not ask again.
  gui_user=$(syncthing_request GET "$gui_url" "$api_key" /rest/config/gui | jq -r '.user')

  if [ -n "$gui_user" ] && [ "$gui_user" != "null" ]; then
      log_info "'Syncthing' GUI user '$gui_user' already set, keeping it."
  elif [ -t 0 ]; then
      read -r -p "'Syncthing' GUI username: " gui_user
      read -r -s -p "'Syncthing' GUI password: " gui_password
      echo

      if [ -n "$gui_user" ] && [ -n "$gui_password" ]; then
          syncthing_request PATCH "$gui_url" "$api_key" /rest/config/gui \
              "$(gui_user="$gui_user" gui_password="$gui_password" jq -n '{user: env.gui_user, password: env.gui_password}')"
          log_success "Set the 'Syncthing' GUI credentials."
      else
          log_warning "Empty username or password, the 'Syncthing' GUI stays without credentials."
      fi
  else
      log_warning "No terminal to ask for the 'Syncthing' GUI password, rerun this script from one."
  fi
fi
