#!/bin/bash
# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
DOCK_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import functions and flags.
source "$DOCK_SCRIPT_DIRECTORY/../helpers/logs.sh"

# Function to check whether the `Dock` still holds only Apple's applications, the
# default of a machine nobody has set up yet. A `Dock` with no saved applications
# counts as the default too.
# Usage:
#   dock_is_default
dock_is_default() {
    local dock_applications
    dock_applications=$(defaults read com.apple.dock persistent-apps 2>/dev/null) || return 0
    [ "$(grep -c '"_CFURLString" =' <<<"$dock_applications")" -eq "$(grep -c '"bundle-identifier" = "com\.apple\.' <<<"$dock_applications")" ]
}

# Function to print the position of a path in the `dock_paths` array of the caller,
# or -1 when it is not there.
# Usage:
#   dock_path_position "/Applications/WezTerm.app"
dock_path_position() {
    local index
    for index in "${!dock_paths[@]}"; do
        if [ "${dock_paths[$index]}" = "$1" ]; then
            echo "$index"
            return
        fi
    done
    echo -1
}

# Function to add the given applications that the `Dock` lacks, keeping every item
# already in it where it is. A missing application goes right after the closest
# application before it in the given list that the `Dock` already has, else right
# before the closest one after it, else at the end, so the list order holds as far
# as the `Dock` allows.
# Usage:
#   add_missing_dock_applications "/Applications/WezTerm.app" ...
add_missing_dock_applications() {
    local dock_plist url insert_at position app_path following_path passed_current
    local index_count=0
    local dock_paths=()

    # Edit an exported copy and import it back, so `cfprefsd` sees the change.
    dock_plist=$(mktemp)
    defaults export com.apple.dock "$dock_plist"
    /usr/libexec/PlistBuddy -c "Print :persistent-apps" "$dock_plist" &>/dev/null || /usr/libexec/PlistBuddy -c "Add :persistent-apps array" "$dock_plist"

    # Read the current order as plain paths, a spacer has no path and stays an empty entry.
    while /usr/libexec/PlistBuddy -c "Print :persistent-apps:${index_count}" "$dock_plist" &>/dev/null; do
        url=$(/usr/libexec/PlistBuddy -c "Print :persistent-apps:${index_count}:tile-data:file-data:_CFURLString" "$dock_plist" 2>/dev/null) || url=""
        # Decode every percent escape of a file `URL`, so a path with any special
        # character matches its list entry and is not added again on every run.
        url="${url#file://}"
        url=$(printf '%b' "${url//%/\\x}")
        dock_paths+=("${url%/}")
        index_count=$((index_count + 1))
    done

    insert_at=""
    for app_path in "$@"; do
        position=$(dock_path_position "$app_path")
        if [ "$position" -ge 0 ]; then
            insert_at=$((position + 1))
            continue
        fi

        # An application that is not installed is left out quietly, a profile skips some on purpose.
        [ -d "$app_path" ] || continue

        # No earlier application of the list is in the `Dock`, look for a later one.
        if [ -z "$insert_at" ]; then
            insert_at=${#dock_paths[@]}
            passed_current="false"
            for following_path in "$@"; do
                if [ "$passed_current" = "true" ]; then
                    position=$(dock_path_position "$following_path")
                    if [ "$position" -ge 0 ]; then
                        insert_at=$position
                        break
                    fi
                elif [ "$following_path" = "$app_path" ]; then
                    passed_current="true"
                fi
            done
        fi

        log_info "Adding '$(basename "$app_path" .app)' to the 'Dock'..."
        /usr/libexec/PlistBuddy \
            -c "Add :persistent-apps:${insert_at} dict" \
            -c "Add :persistent-apps:${insert_at}:tile-data dict" \
            -c "Add :persistent-apps:${insert_at}:tile-data:file-data dict" \
            -c "Add :persistent-apps:${insert_at}:tile-data:file-data:_CFURLString string ${app_path}" \
            -c "Add :persistent-apps:${insert_at}:tile-data:file-data:_CFURLStringType integer 0" \
            "$dock_plist"
        dock_paths=("${dock_paths[@]:0:$insert_at}" "$app_path" "${dock_paths[@]:$insert_at}")
        insert_at=$((insert_at + 1))
    done

    defaults import com.apple.dock "$dock_plist"
    rm -f "$dock_plist"
}

# Function to apply `Dock` configuration. Pass "true" when the `Dock` is still the
# default, only then it is cleared and rebuilt, otherwise the missing applications
# are added to it and everything already in it stays.
# Usage:
#   apply_dock_configuration "false"
apply_dock_configuration() {
    local dock_was_default="${1:-false}"

    log_info "Applying 'Dock' configuration..."

    dock_apps=(
        "$HOME/Applications/Chrome Apps.localized/Google Photos.app"
        "/Applications/Google Chrome.app"
        "/Applications/Brave Browser.app"
        "$HOME/Applications/Chrome Apps.localized/Messages.app"
        "/Applications/Viber.app"
        "/Applications/Visual Studio Code.app"
        "/Applications/DataGrip.app"
        "/Applications/Docker.app"
        "/Applications/Bruno.app"
        "/Applications/Spotify.app"
        "/Applications/LocalSend.app"
        "/Applications/AirSync.app"
        "/Applications/Obsidian.app"
        "/Applications/1Password.app"
        "/Applications/NordVPN.app"
        "/Applications/WezTerm.app"
        "/System/Applications/Utilities/Activity Monitor.app"
        "/System/Applications/System Settings.app"
    )

    if [ "$dock_was_default" = "true" ]; then
        log_info "Clearing the default 'Dock'..."
        defaults delete com.apple.dock persistent-apps 2>/dev/null || true
        defaults delete com.apple.dock persistent-others 2>/dev/null || true
    else
        log_info "Keeping the existing 'Dock' items..."
    fi

    # On a cleared `Dock` this adds every application in order.
    log_info "Adding missing applications to the 'Dock'..."
    add_missing_dock_applications "${dock_apps[@]}"

    # Disable single application mode.
    log_info "Disabling single application mode..."
    defaults write com.apple.dock single-app -bool false

    # Disable animation when opening applications.
    log_info "Disabling animation when opening applications..."
    defaults write com.apple.dock launchanim -bool false

    # Automatically hide and show the `Dock`.
    log_info "Automatically hiding and showing the 'Dock'..."
    sudo defaults write /Library/Preferences/com.apple.dock autohide -bool true
    defaults write com.apple.dock autohide -bool true
    defaults write com.apple.dock autohide-delay -float 0

    # Show indicator lights for open applications in the `Dock`.
    log_info "Showing indicator lights for open applications in the 'Dock'..."
    defaults write com.apple.dock show-process-indicators -bool true

    # Change `Minimize/Maximize` window effect to `Scale`.
    log_info "Changing 'Minimize/Maximize' window effect to 'Scale'..."
    defaults write com.apple.dock mineffect -string "scale"

    # Hide recent applications.
    log_info "Hiding recent applications in the 'Dock'..."
    defaults write com.apple.dock show-recents -bool false

    # Minimize windows into application icon.
    log_info "Minimizing windows into application icon in the 'Dock'..."
    defaults write com.apple.dock minimize-to-application -bool true

    log_success "'Dock' configuration applied successfully."
    log_divider
}
