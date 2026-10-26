#!/bin/bash

# Constant variable of the scripts' working directory to use for relative paths.
PROFILE_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import log functions.
source "$PROFILE_SCRIPT_DIRECTORY/logs.sh"

# Where the chosen profile is saved, outside the repository, so a later run of
# any script keeps it. Override by exporting PROFILE_FILE_PATH before sourcing.
PROFILE_FILE_PATH="${PROFILE_FILE_PATH:-$HOME/.config/macsify/profile}"

# Function to check whether a profile name is one this repository knows.
# Usage:
#   profile_is_valid "work"
profile_is_valid() {
  [ "$1" = "work" ] || [ "$1" = "personal" ]
}

# Function to resolve the machine's profile into an exported MACSIFY_PROFILE.
# Reads MACSIFY_PROFILE first, then the saved file, then asks. With no terminal
# to ask on, it falls back to `personal` with a warning for this run only, so a
# later run with a terminal still asks. An unknown value fails instead of
# guessing. A chosen profile is saved for later runs.
# Usage:
#   profile_resolve
profile_resolve() {
  local profile="${MACSIFY_PROFILE:-}"
  local save="true"

  if [ -z "$profile" ] && [ -f "$PROFILE_FILE_PATH" ]; then
    profile=$(tr -d '[:space:]' <"$PROFILE_FILE_PATH")
  fi

  if [ -n "$profile" ] && ! profile_is_valid "$profile"; then
    log_error "Unknown profile '$profile', expected 'work' or 'personal'."
    return 1
  fi

  if [ -z "$profile" ]; then
    if [ -t 0 ]; then
      while :; do
        log_question "Is this a work or a personal machine? [work/personal]: "
        # End of input, `CTRL` + `D`, would otherwise repeat the question forever.
        if ! read -r profile; then
          log_error "No profile chosen."
          return 1
        fi
        profile=$(printf '%s' "$profile" | tr '[:upper:]' '[:lower:]')
        profile_is_valid "$profile" && break
        log_error "Invalid choice!"
      done
    else
      profile="personal"
      save="false"
      log_warning "No profile set and no terminal to ask, using 'personal' for this run. Export MACSIFY_PROFILE to choose."
    fi
  fi

  if [ "$save" = "true" ]; then
    mkdir -p "$(dirname "$PROFILE_FILE_PATH")"
    printf '%s\n' "$profile" >"$PROFILE_FILE_PATH"
  fi
  export MACSIFY_PROFILE="$profile"
  log_info "Using the '$profile' profile."
}
