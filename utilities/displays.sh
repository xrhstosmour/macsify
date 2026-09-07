#!/bin/bash
# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
DISPLAYS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import constant variables.
source "$DISPLAYS_SCRIPT_DIRECTORY/../helpers/logs.sh"
source "$DISPLAYS_SCRIPT_DIRECTORY/../helpers/launch_agent.sh"

# Function to apply Display configuration.
# Usage:
#   apply_displays_configuration
apply_displays_configuration() {
    log_info "Applying Display Watcher configuration..."

    if displays_create_launch_agent; then
        log_success "Display Watcher configuration applied successfully."
    else
        log_warning "Display Watcher configuration skipped."
    fi

    log_divider
}

# Function to compile the `display_watcher.swift` source into a standalone binary.
# Skips recompiling when the existing binary is already newer than the source.
# Usage:
#   displays_compile_watcher
displays_compile_watcher() {
    local source_path="$DISPLAYS_SCRIPT_DIRECTORY/../.config/scripts/display_watcher.swift"
    local binary_path="$HOME/.config/scripts/display_watcher"

    if [ -f "$binary_path" ] && [ "$binary_path" -nt "$source_path" ]; then
        log_info "Display watcher already up to date, skipping compile."
        return 0
    fi

    log_info "Compiling display watcher..."

    if ! command -v swiftc &>/dev/null; then
        log_warning "'swiftc' not found, skipping display watcher (install Xcode Command Line Tools to enable it)."
        return 1
    fi

    if ! swiftc -O "$source_path" -o "$binary_path"; then
        log_error "Failed to compile display watcher."
        return 1
    fi

    log_success "Display watcher compiled."
}

# Function to create a launch agent that runs the compiled display watcher, an
# event-driven daemon that reloads the `AeroSpace` environment whenever a display
# is physically connected or disconnected. Unlike polling, it is blocked on
# `CoreGraphics`'s own reconfiguration notification and costs nothing while idle.
# Usage:
#   displays_create_launch_agent
displays_create_launch_agent() {
    log_info "Creating launch agent for display change detection..."

    # Remove the existing launch agent before compiling, an agent still holding
    # the binary open would make `swiftc` fail to overwrite it.
    remove_launch_agent "com.local.DisplayWatcher"

    displays_compile_watcher || return 1

    # `KeepAlive` restarts the daemon if it ever exits/crashes, there is no
    # `StartInterval` since the daemon itself blocks on the display
    # reconfiguration callback instead of being polled. `StandardErrorPath`
    # gives the daemon and the reload script it launches somewhere to log to.
    local plist_content
    plist_content=$(
        cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.DisplayWatcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HOME/.config/scripts/display_watcher</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/DisplayWatcher.log</string>
</dict>
</plist>
EOF
    )

    install_launch_agent "com.local.DisplayWatcher" "$plist_content"
}
