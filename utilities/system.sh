#!/bin/bash
# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
SYSTEM_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import constant variables.
source "$SYSTEM_SCRIPT_DIRECTORY/../helpers/logs.sh"

# Function to apply System configuration.
# Usage:
#   apply_system_configuration
apply_system_configuration() {
    log_info "Applying System configuration..."

    # Enable `sudo` authentication using `Touch ID` on supported MacBooks.
    log_info "Enabling 'sudo' authentication using 'Touch ID'..."
    sed -e 's/^#auth/auth/' /etc/pam.d/sudo_local.template | sudo tee /etc/pam.d/sudo_local

    # Turn off `Bluetooth`, if you don't have a mouse/keyboard/headphone connected.
    log_info "Turning off 'Bluetooth' when not using a mouse/keyboard/headphone..."
    sudo defaults write /Library/Preferences/com.apple.Bluetooth ControllerPowerState -int 0

    # Save screenshots to the 'Desktop'.
    log_info "Saving screenshots to the 'Desktop'..."
    defaults write com.apple.screencapture location -string "${HOME}/Desktop"

    # Save screenshots in lossless `PNG` format.
    log_info "Saving screenshots in lossless 'PNG' format..."
    defaults write com.apple.screencapture type -string "png"

    # Show scroll-bars always.
    log_info "Showing scroll-bars always..."
    defaults write NSGlobalDomain AppleShowScrollBars -string "Always"

    # Disable `Siri`.
    log_info "Disabling 'Siri'..."
    defaults write com.apple.Siri StatusMenuVisible -bool false
    defaults write com.apple.assistant.support "Assistant Enabled" -bool false

    # Remove all `Widgets` from `Desktop`.
    log_info "Removing all 'Widgets' from 'Desktop'..."
    defaults write com.apple.WindowManager StandardHideWidgets -bool true

    # Disable `Spotlight` from `Menu Bar`.
    log_info "Disabling 'Spotlight' from menu bar..."
    defaults write com.apple.Spotlight MenuItemHidden -int 1

    # Disable `AirDrop`.
    log_info "Disabling 'AirDrop'..."
    defaults write com.apple.sharingd DiscoverableMode -string "Off"

    # Disabling `Reopen Windows When Logging Back`.
    log_info "Disabling 'Reopen Windows When Logging Back'..."
    defaults write com.apple.loginwindow TALLogoutSavesState -bool false

    # Disable password hints.
    log_info "Disabling password hints..."
    defaults write com.apple.loginwindow RetriesUntilHint -int 0

    # Change time and date format.
    log_info "Changing time and date format..."
    defaults write com.apple.menuextra.clock IsAnalog -bool false
    defaults write com.apple.menuextra.clock DateFormat -string "EEE d MMM HH:mm"
    defaults write .GlobalPreferences AppleICUForce24HourTime -bool true

    # Enable Firewall and stealth mode with exceptions for file sharing apps
    log_info "Enabling firewall and stealth mode with exceptions for file sharing apps..."
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

    # Allow file sharing applications through firewall.
    log_info "Exclude applications from the firewall rules..."
    for app in "LocalSend" "Syncthing"; do
        if [ -d "/Applications/$app.app" ]; then
            log_info "Adding $app to firewall exceptions..."
            sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "/Applications/$app.app"
            sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblock "/Applications/$app.app"
        fi
    done

    # ! You need to grant `Full Disk Access` to the terminal running this script.
    # Exclude applications from quarantine.
    log_info "Exclude applications from quarantine..."
    for app in "Flameshot" "LocalSend" "Syncthing"; do
        if [ -d "/Applications/$app.app" ]; then
            log_info "Exclude $app from quarantine..."
            sudo xattr -dr com.apple.quarantine "/Applications/$app.app"
        fi
    done


    # Remove unneeded default applications from the Applications folder.
    # Apps protected by `SIP` (Books, Chess, Dictionary, News, Podcasts, Stocks, TV, Music, Stickies, Siri, Reminders, Photo Booth, Games) cannot be removed.
    log_info "Removing unneeded default applications from /Applications..."
    for app in "GarageBand" "iMovie" "Keynote" "Voice Memos"; do
        # Check /Applications first.
        if [ -d "/Applications/$app.app" ]; then
            sudo rm -rf "/Applications/$app.app" 2>/dev/null && log_info "Removed $app.app from /Applications." || log_info "Could not remove $app.app from /Applications."
        fi
    done

    # Remove leftover user/library data for deleted apps.
    log_info "Removing leftover Library data for deleted apps..."
    for dir in "~/Library/Containers/com.apple.voicememos" "~/Library/Containers/com.apple.garageband" "~/Library/Containers/com.apple.iMovie" "~/Library/Containers/com.apple.iWork.Keynote"; do
        eval expanded_dir=$dir
        if [ -d "$expanded_dir" ]; then
            rm -rf "$expanded_dir"
            log_info "Removed $expanded_dir."
        fi
    done

    # Disable hot corners.
    log_info "Disabling hot corners..."
    defaults write com.apple.dock wvous-tl-corner -int 0
    defaults write com.apple.dock wvous-tr-corner -int 0
    defaults write com.apple.dock wvous-bl-corner -int 0
    defaults write com.apple.dock wvous-br-corner -int 0

    # Show all processes in `Activity Monitor`.
    log_info "Showing all processes in 'Activity Monitor'..."
    defaults write com.apple.ActivityMonitor ShowCategory -int 0

    # Show the main window when launching `Activity Monitor`.
    log_info "Showing the main window when launching 'Activity Monitor'..."
    defaults write com.apple.ActivityMonitor OpenMainWindow -bool true

    log_info "Configuring 'Login Items'..."

    # Define desired `Login Items`.
    desired_login_items=("1Password" "AeroSpace" "AltTab" "Amphetamine" "Flameshot" "Google Drive" "Maccy" "SwipeAeroSpace" "Syncthing")

    # Get all current `Login Items` names.
    current_login_items=$(osascript -e 'tell application "System Events" to get the name of every login item' | sed 's/, /\n/g')

    # Remove `Login Items` that are not in the desired list.
    while IFS= read -r current_login_item; do
        if [ -n "$current_login_item" ]; then
            # Check if the current item is in the desired list.
            item_found=false
            for desired_item in "${desired_login_items[@]}"; do
                if [ "$current_login_item" = "$desired_item" ]; then
                    item_found=true
                    break
                fi
            done

            # Remove only if not found in desired list.
            if [ "$item_found" = false ]; then
                osascript -e "tell application \"System Events\" to delete login item \"$current_login_item\""
            fi
        fi
    done <<< "$current_login_items"

    # Add desired applications to `Login Items` if not already there.
    items_to_add=0
    for application in "${desired_login_items[@]}"; do
        if [ -d "/Applications/$application.app" ]; then
            if ! osascript -e 'tell application "System Events" to get the name of every login item' | sed 's/, /\n/g' | grep -Fxq "$application"; then
                log_info "Adding '$application' to 'Login Items'..."
                osascript -e "tell application \"System Events\" to make login item at end with properties {name: \"$application\", path:\"/Applications/$application.app\", hidden:true}"
                ((items_to_add++))
            fi
        fi
    done

    if [ $items_to_add -eq 0 ]; then
        log_warning "All needed login items are already included."
    fi

    log_success "System configuration applied successfully."
    log_divider
}
