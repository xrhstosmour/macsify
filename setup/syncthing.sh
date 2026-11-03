#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
SYNCTHING_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import functions and flags.
source "$SYNCTHING_SCRIPT_DIRECTORY/../helpers/logs.sh"
source "$SYNCTHING_SCRIPT_DIRECTORY/../helpers/syncthing.sh"

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
