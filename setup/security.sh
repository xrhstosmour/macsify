#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
SECURITY_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import functions and flags.
source "$SECURITY_SCRIPT_DIRECTORY/../helpers/logs.sh"
source "$SECURITY_SCRIPT_DIRECTORY/../helpers/brewfile.sh"

# Security tooling, each part only on a profile whose Brewfile installs it.
if brewfile_declares syncthing-app; then
  bash "$SECURITY_SCRIPT_DIRECTORY/../settings/syncthing.sh"
fi

if brewfile_declares clamav; then
  # Only between the two parts, not when `Syncthing` was skipped.
  if brewfile_declares syncthing-app; then
    log_divider
  fi
  bash "$SECURITY_SCRIPT_DIRECTORY/../settings/clamav.sh"
fi
