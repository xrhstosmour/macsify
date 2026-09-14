#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
INSTALL_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Run from the project root so all relative paths resolve correctly.
cd "$INSTALL_SCRIPT_DIRECTORY"

# Import functions and flags.
source "$INSTALL_SCRIPT_DIRECTORY/helpers/logs.sh"
source "$INSTALL_SCRIPT_DIRECTORY/helpers/ui.sh"

# Copy the needed configuration files to the new machine.
log_info "Copying configuration files to '~/.config'..."
mkdir -p ~/.config && cp -R .config/* ~/.config/

# Give execute permission to all scripts in the directory.
chmod +x ~/.config/scripts/*.sh

# Install `Homebrew` and Brewfile dependencies before agentic setup below, its
# MCP registration steps need `opencode`/`claude`/`codex`/`copilot` actually
# installed, not just declared in the Brewfile.
log_info "Installing 'Homebrew', dependencies and applications..."
source "$INSTALL_SCRIPT_DIRECTORY/setup/homebrew.sh"
brew bundle install --file="$INSTALL_SCRIPT_DIRECTORY/packages/Brewfile" || log_warning "Some Brewfile entries failed, continuing."

# Set up agentic configuration: inject models, symlink shared content.
log_info "Setting up agentic configuration..."
bash "$INSTALL_SCRIPT_DIRECTORY/setup/agentic.sh"

# Configure `macOS`.
log_info "Starting 'macOS' configuration..."
bash "$INSTALL_SCRIPT_DIRECTORY/configure.sh"

log_success "System configuration completed!"

message="Do you want to reboot the system now?"
command="log_info 'Initiating system reboot in 10 seconds...'; log_info 'Press CTRL+C to cancel'; sleep 10; sudo reboot"
user_answer=$(ask_user_before_execution "$message" "true" "$command")
if [ "$user_answer" = "n" ]; then
  log_info "Reboot skipped. Some changes may require a restart to take effect."
fi
