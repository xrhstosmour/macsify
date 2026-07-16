#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
PREFERENCES_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import functions and flags.
source "$PREFERENCES_SCRIPT_DIRECTORY/../helpers/logs.sh"
source "$PREFERENCES_SCRIPT_DIRECTORY/../utilities/finder.sh"
source "$PREFERENCES_SCRIPT_DIRECTORY/../utilities/dock.sh"
source "$PREFERENCES_SCRIPT_DIRECTORY/../utilities/menu_bar.sh"
source "$PREFERENCES_SCRIPT_DIRECTORY/../utilities/keyboard.sh"
source "$PREFERENCES_SCRIPT_DIRECTORY/../utilities/trackpad.sh"
source "$PREFERENCES_SCRIPT_DIRECTORY/../utilities/sound.sh"
source "$PREFERENCES_SCRIPT_DIRECTORY/../utilities/appearance.sh"
source "$PREFERENCES_SCRIPT_DIRECTORY/../utilities/system.sh"

apply_finder_configuration
apply_dock_configuration
apply_menu_bar_configuration
apply_keyboard_configuration
apply_trackpad_configuration
apply_sound_configuration
apply_appearance_configuration
apply_system_configuration
