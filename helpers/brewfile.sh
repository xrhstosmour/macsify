#!/bin/bash

# Constant variable of the scripts' working directory to use for relative paths.
BREWFILE_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Directory holding `base.Brewfile` and one Brewfile per profile. Override by
# exporting BREWFILE_DIRECTORY before sourcing.
BREWFILE_DIRECTORY="${BREWFILE_DIRECTORY:-$BREWFILE_SCRIPT_DIRECTORY/../packages}"

# Function to print the Brewfile of the active profile, `personal` unless
# MACSIFY_PROFILE says otherwise. It includes `base.Brewfile` itself.
# Usage:
#   brewfile_path
brewfile_path() {
  printf '%s\n' "$BREWFILE_DIRECTORY/${MACSIFY_PROFILE:-personal}.Brewfile"
}

# Function to check whether the active profile actively declares a package.
# Matches any uncommented declaration keyword (brew, cask, tap, mas, ...) in
# `base.Brewfile` and the profile's Brewfile, the profile file only includes the
# base one through Ruby, so a plain search has to read both.
# Returns non-zero when the Brewfiles are missing, the line is commented, or the
# package was removed entirely, so all "not wanted" cases behave the same.
# Usage:
#   brewfile_declares "anomalyco/tap/opencode"
brewfile_declares() {
  local package="$1"
  local file
  for file in "$BREWFILE_DIRECTORY/base.Brewfile" "$(brewfile_path)"; do
    [ -f "$file" ] || continue
    grep -qE "^[[:space:]]*[a-z_]+ [\"']${package}[\"']" "$file" && return 0
  done
  return 1
}
