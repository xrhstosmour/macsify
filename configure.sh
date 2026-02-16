#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
CONFIGURE_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import functions and flags.
source "$CONFIGURE_SCRIPT_DIRECTORY/helpers/logs.sh"

# Install and configure `Homebrew`.
source setup/homebrew.sh

# Install developer tools & programming languages.
source setup/developer.sh
source utilities/development.sh

# Install dependencies and applications.
log_info "Installing needed dependencies and applications..."
brew bundle install --file=packages/Brewfile

# Install `Mac App Store` applications.
# Loop through the list of app IDs in `packages/store_applications_ids.txt`.
if command -v mas &>/dev/null; then
    while IFS= read -r application_id || [[ -n "$application_id" ]]; do
        # Skip empty lines and comments.
        [[ -z "$application_id" || "$application_id" =~ ^# ]] && continue

        mas purchase "$application_id"
    done <packages/store_applications_ids.txt
fi

# Install `PWA` applications using `pake` package.
# Loop through the list of `PWA` apps in `packages/pwa_applications.txt`.
if command -v pake &>/dev/null; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments.
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        IFS='|' read -r name url icon <<< "$line"
        name="$(echo "$name" | xargs)"
        url="$(echo "$url" | xargs)"
        icon="$(echo "$icon" | xargs)"

        pake_args=("$url" --name "$name" --width 1200 --height 800 --dark-mode --new-window --enable-drag-drop --force-internal-navigation --wasm)
        if [[ -n "$icon" ]]; then
            pake_args+=(--icon "$icon")
        fi

        PAKE_CREATE_APP=1 pake "${pake_args[@]}"

        app_source="$PWD/${name}.app"
        if [ -d "$app_source" ]; then
            log_info "Moving '${name}.app' to 'macOS' Applications folder..."
            sudo mv "$app_source" "/Applications/${name}.app"
        fi
    done <packages/pwa_applications.txt
fi


# Restore installed applications' configurations.
sh setup/applications.sh
log_divider

# Configure shell.
sh setup/shell.sh

# Configure `macOS` Preferences.
sh setup/preferences.sh
