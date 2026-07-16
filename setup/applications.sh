#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e


# Constant variable of the scripts' working directory to use for relative paths.
APPLICATIONS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import functions and flags.
source "$APPLICATIONS_SCRIPT_DIRECTORY/../helpers/logs.sh"

# Declare application configuration sources, destinations and names.
APPLICATIONS_SOURCES=(
  "$APPLICATIONS_SCRIPT_DIRECTORY/../settings/aerospace.toml"
  "$APPLICATIONS_SCRIPT_DIRECTORY/../settings/com.if.Amphetamine.plist.xml"
  "$APPLICATIONS_SCRIPT_DIRECTORY/../settings/com.sanyamgarg.switch.plist.xml"
  "$APPLICATIONS_SCRIPT_DIRECTORY/../settings/org.p0deje.Maccy.plist.xml"
  "$APPLICATIONS_SCRIPT_DIRECTORY/../settings/pl.maketheweb.TopNotch.plist.xml"
  "$APPLICATIONS_SCRIPT_DIRECTORY/../settings/flameshot.ini"
)

APPLICATIONS_DESTINATIONS=(
  "$HOME/.config/aerospace/aerospace.toml"
  "$HOME/Library/Containers/com.if.Amphetamine/Data/Library/Preferences/com.if.Amphetamine.plist"
  "$HOME/Library/Preferences/com.sanyamgarg.switch.plist"
  "$HOME/Library/Containers/org.p0deje.Maccy/Data/Library/Preferences/org.p0deje.Maccy.plist"
  "$HOME/Library/Preferences/pl.maketheweb.TopNotch.plist"
  "$HOME/.config/flameshot/flameshot.ini"
)

APPLICATIONS_NAMES=(
  "Aerospace"
  "Amphetamine"
  "Switch"
  "Maccy"
  "TopNotch"
  "Flameshot"
)

# Loop over all arrays in parallel.
for i in "${!APPLICATIONS_SOURCES[@]}"; do
  source="${APPLICATIONS_SOURCES[$i]}"
  destination="${APPLICATIONS_DESTINATIONS[$i]}"
  process_name="${APPLICATIONS_NAMES[$i]}"

  # Check if the source configuration file exists.
  if [ -f "$source" ]; then
    log_info "Restoring '$process_name' configuration..."
    killall "$process_name" 2>/dev/null || true

    # Create destination directory.
    mkdir -p "$(dirname "$destination")"

    # If the source is a `.plist.xml`, convert to binary `plist`.
    if [[ "$source" == *.plist.xml ]]; then
      plutil -convert binary1 -o "$destination" "$source"
    elif [[ "$source" == *.ini ]]; then
      # If the source is a `.ini` file, expand variables before copying.
      envsubst < "$source" > "$destination"
    else
      # For regular files, just copy them to their destination.
      cp "$source" "$destination"
    fi

    killall cfprefsd 2>/dev/null || true
  fi
done

log_success "All applications configurations restored successfully."
