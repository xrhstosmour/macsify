#!/bin/bash

# Constant variable of the scripts' working directory to use for relative paths.
LAUNCH_AGENT_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import constant variables.
source "$LAUNCH_AGENT_SCRIPT_DIRECTORY/logs.sh"

# Function to unload and remove an existing `launchd` LaunchAgent, if present.
# Usage:
#   remove_launch_agent "com.local.Example"
remove_launch_agent() {
    local label="$1"
    local plist_path="$HOME/Library/LaunchAgents/${label}.plist"

    if [ -f "$plist_path" ]; then
        log_info "Removing existing launch agent..."
        launchctl unload "$plist_path" 2>/dev/null || true
        rm -f "$plist_path"
    fi
}

# Function to write and load a `launchd` LaunchAgent plist, replacing any
# existing agent registered under the same label first.
# Usage:
#   install_launch_agent "com.local.Example" "$plist_content"
install_launch_agent() {
    local label="$1"
    local plist_content="$2"
    local plist_path="$HOME/Library/LaunchAgents/${label}.plist"

    remove_launch_agent "$label"

    mkdir -p ~/Library/LaunchAgents
    printf '%s\n' "$plist_content" >"$plist_path"
    launchctl load -w "$plist_path" 2>/dev/null || true

    log_success "Launch agent created and loaded for '$label'."
}
