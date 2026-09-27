#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
CONFIGURE_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import functions and flags.
source "$CONFIGURE_SCRIPT_DIRECTORY/helpers/ui.sh"

# `Homebrew` and Brewfile dependencies are installed by `install.sh` before this
# script runs, agentic setup in between needs them already in place.
command -v brew &>/dev/null || { log_error "'brew' not found, run install.sh first."; exit 1; }

# Install `Mac App Store` applications, before the developer tools because the
# mobile toolchain's iOS half needs `Xcode` already installed.
# Loop through the list of app IDs in `packages/store_applications_ids.txt`.
if command -v mas &>/dev/null; then
    installed_application_ids=$(mas list | awk '{print $1}')

    while IFS= read -r application_id || [[ -n "$application_id" ]]; do
        [[ -z "$application_id" || "$application_id" =~ ^# ]] && continue

        if grep -qx "$application_id" <<<"$installed_application_ids"; then
            continue
        fi

        mas purchase "$application_id"
    done <packages/store_applications_ids.txt
fi

# Install developer tools & programming languages.
source setup/developer.sh
source utilities/development.sh

# Set up the mobile development toolchain. Asked with a no-op command and run
# afterwards, so the command substitution the answer needs does not swallow the
# script's own output.
if [ "$(ask_user_before_execution "Do you want to install the mobile development toolchain?" "true" ":")" = "y" ]; then
    bash setup/mobile.sh
fi
log_divider

# Install additional packages from various sources by executing custom installation commands.
if [[ -f packages/additional_packages.txt ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        bash -c "$line" || log_warning "Failed to run additional package command: $line"
    done <packages/additional_packages.txt
fi
log_divider

# Restore installed applications' configurations.
bash setup/applications.sh
log_divider

# Configure shell.
bash setup/shell.sh

# Configure `macOS` Preferences.
bash setup/preferences.sh
