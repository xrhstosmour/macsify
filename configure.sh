#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
CONFIGURE_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import functions and flags.
source "$CONFIGURE_SCRIPT_DIRECTORY/helpers/ui.sh"
source "$CONFIGURE_SCRIPT_DIRECTORY/helpers/profile.sh"
source "$CONFIGURE_SCRIPT_DIRECTORY/helpers/brewfile.sh"

# `install.sh` already chose the profile, a standalone run reads the saved one.
profile_resolve

# `Homebrew` and Brewfile dependencies are installed by `install.sh` before this
# script runs, agentic setup below needs them already in place.
command -v brew &>/dev/null || { log_error "'brew' not found, run install.sh first."; exit 1; }

# Install `Mac App Store` applications, before the developer tools because the
# mobile toolchain's iOS half needs `Xcode` already installed.
# Loop through the list of app IDs in `packages/store_applications_ids.txt`, then in the
# active profile's `packages/<profile>.store_applications_ids.txt` when it has one.
if command -v mas &>/dev/null; then
    installed_application_ids=$(mas list | awk '{print $1}')

    for application_ids_file in packages/store_applications_ids.txt "packages/${MACSIFY_PROFILE:-personal}.store_applications_ids.txt"; do
        [[ -f "$application_ids_file" ]] || continue

        while IFS= read -r application_id || [[ -n "$application_id" ]]; do
            [[ -z "$application_id" || "$application_id" =~ ^# ]] && continue

            if grep -qx "$application_id" <<<"$installed_application_ids"; then
                continue
            fi

            # A Mac not signed into the App Store fails here, keep going so the rest of the setup still runs.
            mas purchase "$application_id" || log_warning "Failed to install App Store application '$application_id', sign in to the App Store and rerun."
        done <"$application_ids_file"
    done
fi

# Install developer tools & programming languages.
source setup/developer.sh
log_divider
source utilities/development.sh

# Set up agentic configuration: inject models, symlink shared content. Runs once,
# here, because its `npm` plugin installs need the `node` and `npm` that `mise`
# provides in the step above.
log_divider
log_info "Setting up agentic configuration..."
bash setup/agentic.sh

# Set up the mobile development toolchain. Asked with a no-op command and run
# afterwards, so the command substitution the answer needs does not swallow the
# script's own output. Skipped when the profile does not install `flutter`.
if brewfile_declares flutter; then
    log_divider
    if [ "$(ask_user_before_execution "Do you want to install the mobile development toolchain?" "true" ":")" = "y" ]; then
        bash setup/mobile.sh
    fi
fi

# Install additional packages from various sources by executing custom installation commands.
if [[ -f packages/additional_packages.txt ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        bash -c "$line" || log_warning "Failed to run additional package command: $line"
    done <packages/additional_packages.txt
fi

# Restore installed applications' configurations.
log_divider
bash setup/applications.sh

# Configure shell.
log_divider
bash setup/shell.sh

# Configure `macOS` Preferences.
log_divider
bash setup/preferences.sh

# Set up security tooling and applications hardening.
log_divider
bash setup/security.sh
