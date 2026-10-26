#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
HOMEBREW_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import functions and flags.
source "$HOMEBREW_SCRIPT_DIRECTORY/../helpers/logs.sh"

# Declare `Homebrew` constants.
# Pinned to the `Homebrew/install` commit from 2026-10-23, `HEAD` would run whatever is pushed next.
HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/85d1a3fc80d8a63932f632aca8f787de11d14a64/install.sh"
HOMEBREW_BIN_PATH="/opt/homebrew/bin/brew"
ZPROFILE_PATH="$HOME/.zprofile"

# Install and configure `Homebrew`.
if ! command -v brew &>/dev/null; then
  log_info "Installing 'Homebrew'..."
  /bin/bash -c "$(curl -fsSL ${HOMEBREW_INSTALL_URL})"

  # Check if the environment variables are set.
  HOMEBREW_ENVIRONMENT_COMMAND="eval \"\$(${HOMEBREW_BIN_PATH} shellenv)\""
  if ! grep -qF -- "$HOMEBREW_ENVIRONMENT_COMMAND" "$ZPROFILE_PATH"; then
    log_info "Adding 'Homebrew' environment to ${ZPROFILE_PATH}..."
    echo >>"$ZPROFILE_PATH"
    echo "$HOMEBREW_ENVIRONMENT_COMMAND" >>"$ZPROFILE_PATH"
    eval "$($HOMEBREW_BIN_PATH shellenv)"
  fi
else
  log_warning "'Homebrew' is already installed."
fi

# Ensure `Homebrew` is in `PATH` for current shell session.
if [ -x "/opt/homebrew/bin/brew" ]; then
    HOMEBREW_PATH="/opt/homebrew/bin/brew"
elif [ -x "/usr/local/bin/brew" ]; then
    HOMEBREW_PATH="/usr/local/bin/brew"
fi

if [ -n "$HOMEBREW_PATH" ]; then
    CURRENT_SHELL=$(basename "$SHELL")
    case "$CURRENT_SHELL" in
        fish)
            eval "$($HOMEBREW_PATH shellenv | grep -v 'export' | sed 's/export /set -gx /')"
            ;;
        *)
            eval "$($HOMEBREW_PATH shellenv)"
            ;;
    esac
fi
log_divider
