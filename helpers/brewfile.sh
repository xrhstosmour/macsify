#!/bin/bash

# Constant variable of the scripts' working directory to use for relative paths.
BREWFILE_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Default Brewfile location within the repository. Override by exporting
# BREWFILE_PATH before sourcing.
BREWFILE_PATH="${BREWFILE_PATH:-$BREWFILE_SCRIPT_DIRECTORY/../packages/Brewfile}"

# Function to check whether the Brewfile actively declares a package.
# Matches any uncommented declaration keyword (brew, cask, tap, mas, ...).
# Returns non-zero when the Brewfile is missing, the line is commented, or the
# package was removed entirely, so all "not wanted" cases behave the same.
# Usage:
#   brewfile_declares "opencode"
brewfile_declares() {
  local package="$1"
  [ -f "$BREWFILE_PATH" ] || return 1
  grep -qE "^[[:space:]]*[a-z_]+ [\"']${package}[\"']" "$BREWFILE_PATH"
}
