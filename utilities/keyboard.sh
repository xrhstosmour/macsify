#!/bin/bash
# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
KEYBOARD_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import constant variables.
source "$KEYBOARD_SCRIPT_DIRECTORY/../helpers/logs.sh"
source "$KEYBOARD_SCRIPT_DIRECTORY/../helpers/launch_agent.sh"

# Function to apply Keyboard configuration.
#
# More details:
#   - https://hidutil-generator.netlify.app/
#   - https://apple.stackexchange.com/questions/467341/hidutil-stopped-working-on-macos-14-2-update
#
# Usage:
#   apply_keyboard_configuration
apply_keyboard_configuration() {
    log_info "Applying Keyboard configuration..."

    # Enable full keyboard access for all controls.
    log_info "Enabling full keyboard access for all controls..."
    defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

    # Disable `Smart Quotes` when typing code.
    log_info "Disabling 'Smart Quotes' when typing code..."
    defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

    # Disable `Smart Dashes` when typing code.
    log_info "Disabling 'Smart Dashes' when typing code..."
    defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

    # Disable auto-correct.
    log_info "Disabling auto-correct..."
    defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

    # Disable `Emoji` picker.
    log_info "Disabling 'Emoji' picker..."
    defaults write com.apple.HIToolbox AppleFnUsageType -int 0

    # Disable press & hold for accents.
    log_info "Disabling press & hold for accents..."
    defaults write -g ApplePressAndHoldEnabled -bool false

    # Clear existing `hidutil` mappings and apply new ones.
    keyboard_clear_hidutil_mappings
    keyboard_apply_special_key_mappings

    # Configure keyboard shortcuts (Mission Control, Spotlight, Input Source).
    keyboard_apply_symbolic_hotkeys

    log_success "Keyboard configuration applied successfully."
    log_divider
}

# Function to configure keyboard shortcuts via `AppleSymbolicHotKeys`.
# Disables all `Mission Control` shortcuts and sets `Show Spotlight search`/`Select the previous input source`
# to `Key 2 + .` / `Key 2 + Space`.
#
# Usage:
#   keyboard_apply_symbolic_hotkeys
keyboard_apply_symbolic_hotkeys() {
    log_info "Configuring keyboard shortcuts..."

    local symbolic_hotkeys_plist="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"

    # Disable all `Mission Control` shortcuts (each pair is the default-key /
    # dedicated-key variant):
    #   32/34 Mission Control, 33/35 Application windows, 36/37 Show Desktop,
    #   79/80 Move left a space, 81/82 Move right a space, 118-121 Switch to Desktop 1-4.
    log_info "Disabling all 'Mission Control' shortcuts..."
    for hotkey_id in 32 33 34 35 36 37 79 80 81 82 118 119 120 121; do
        /usr/libexec/PlistBuddy -c "Delete :AppleSymbolicHotKeys:${hotkey_id}" "$symbolic_hotkeys_plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:${hotkey_id}:enabled bool false" "$symbolic_hotkeys_plist"
    done

    # Set `Show Spotlight search` to `Key 2 + .` (physical Control key, remapped to Option).
    log_info "Setting 'Show Spotlight search' shortcut to 'Key 2 + .'..."
    /usr/libexec/PlistBuddy -c "Delete :AppleSymbolicHotKeys:64" "$symbolic_hotkeys_plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy \
        -c "Add :AppleSymbolicHotKeys:64:enabled bool true" \
        -c "Add :AppleSymbolicHotKeys:64:value:type string standard" \
        -c "Add :AppleSymbolicHotKeys:64:value:parameters array" \
        -c "Add :AppleSymbolicHotKeys:64:value:parameters:0 integer 46" \
        -c "Add :AppleSymbolicHotKeys:64:value:parameters:1 integer 47" \
        -c "Add :AppleSymbolicHotKeys:64:value:parameters:2 integer 524288" \
        "$symbolic_hotkeys_plist"

    # Set `Select the previous input source` to `Key 2 + Space` (physical Control key, remapped to Option).
    log_info "Setting 'Select the previous input source' shortcut to 'Key 2 + Space'..."
    /usr/libexec/PlistBuddy -c "Delete :AppleSymbolicHotKeys:60" "$symbolic_hotkeys_plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy \
        -c "Add :AppleSymbolicHotKeys:60:enabled bool true" \
        -c "Add :AppleSymbolicHotKeys:60:value:type string standard" \
        -c "Add :AppleSymbolicHotKeys:60:value:parameters array" \
        -c "Add :AppleSymbolicHotKeys:60:value:parameters:0 integer 32" \
        -c "Add :AppleSymbolicHotKeys:60:value:parameters:1 integer 49" \
        -c "Add :AppleSymbolicHotKeys:60:value:parameters:2 integer 524288" \
        "$symbolic_hotkeys_plist"

    killall cfprefsd 2>/dev/null || true

    log_warning "Keyboard shortcut changes require logging out (or restarting) to take effect."
    log_success "Keyboard shortcuts configured successfully."
}

# Function to clear existing hidutil mappings and launch agent.
# Usage:
#   keyboard_clear_hidutil_mappings
keyboard_clear_hidutil_mappings() {
    log_info "Clearing existing 'hidutil' mappings..."

    # Clear `hidutil` mappings.
    /usr/bin/hidutil property --set '{"UserKeyMapping":[]}' >/dev/null 2>&1

    remove_launch_agent "com.local.KeyRemapping"

    log_success "'hidutil' mappings cleared."
}

# Function to configure password-less `sudo` for `hidutil`.
# Required for `LaunchAgent` to run `hidutil` without password prompt.
# Usage:
#   configure_password_less_sudo
configure_password_less_sudo() {
    log_info "Configuring password-less 'sudo' for 'hidutil'..."

    # Check if already configured.
    if sudo grep -q "^$USER ALL=(ALL) NOPASSWD: /usr/bin/hidutil$" /etc/sudoers.d/hidutil-mapping 2>/dev/null; then
        log_info "Password-less 'sudo' for 'hidutil' already configured."
        return
    fi

    # Create or append to the file safely.
    echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/hidutil" | sudo tee -a /etc/sudoers.d/hidutil-mapping >/dev/null
    sudo chmod 440 /etc/sudoers.d/hidutil-mapping
    log_success "Password-less 'sudo' configured for 'hidutil'."
}

# Function to apply special key mappings via `hidutil`.
# Maps Section Sign → Tilde and Right Shift → Delete.
# These mappings cannot be configured via System Settings.
# Usage:
#   keyboard_apply_special_key_mappings
keyboard_apply_special_key_mappings() {
    log_info "Applying Section Sign → Tilde and Right Shift → Delete mappings..."

    # Configure password-less `sudo`, required for `LaunchAgent`.
    configure_password_less_sudo

    # Apply mappings immediately for this session.
    sudo /usr/bin/hidutil property --set '{"UserKeyMapping":[
        {
          "HIDKeyboardModifierMappingSrc": 0x700000064,
          "HIDKeyboardModifierMappingDst": 0x700000035
        },
        {
          "HIDKeyboardModifierMappingSrc": 0x7000000E5,
          "HIDKeyboardModifierMappingDst": 0x70000004C
        }
    ]}' >/dev/null 2>&1

    # Create launch agent for persistence.
    keyboard_create_launch_agent

    log_success "Special key mappings applied (Section Sign → Tilde, Right Shift → Delete)."
}

# Function to create launch agent for `hidutil` persistence.
# Creates a launch agent that will reapply `hidutil` mappings on system startup.
# Usage:
#   keyboard_create_launch_agent
keyboard_create_launch_agent() {
    log_info "Creating launch agent for 'hidutil' persistence..."

    # Build the launch agent plist with the correct `hidutil` mappings.
    local plist_content
    plist_content=$(
        cat <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.KeyRemapping</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/sudo</string>
        <string>/usr/bin/hidutil</string>
        <string>property</string>
        <string>--set</string>
        <string>{"UserKeyMapping":[
            {
              "HIDKeyboardModifierMappingSrc": 0x700000064,
              "HIDKeyboardModifierMappingDst": 0x700000035
            },
            {
              "HIDKeyboardModifierMappingSrc": 0x7000000E5,
              "HIDKeyboardModifierMappingDst": 0x70000004C
            }
        ]}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
    )

    install_launch_agent "com.local.KeyRemapping" "$plist_content"
}
