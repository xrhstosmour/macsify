# Add `Homebrew`'s binary directory to the `PATH` environment variable.
fish_add_path "/opt/homebrew/bin/"

# Add `adb` and `fastboot`, which live under the Android SDK root.
fish_add_path "/opt/homebrew/share/android-commandlinetools/platform-tools"

# Add `dart`, which the `flutter` cask does not symlink.
fish_add_path "/opt/homebrew/share/flutter/bin"

# Disable `Homebrew` environment update hints.
set -gx HOMEBREW_NO_ENV_HINTS 1

# Use `1Password` as the `SSH` agent.
set -gx SSH_AUTH_SOCK ~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock

# Enable `Starship` as `Fish` prompt.
starship init fish | source

# Enable `Zoxide` at `Fish` shell.
zoxide init fish | source

# Enable and configure `Atuin` at `Fish` shell.
set -gx ATUIN_NOBIND "true"
atuin init fish | source
bind \ch _atuin_search
bind -M insert \ch _atuin_search

# Disable welcome message.
set -U fish_greeting

# Stop `OpenCode` from re-scanning `~/.claude/skills`, it already finds every skill
# through its own `~/.config/opencode/skills` symlink, both point at the same
# `~/.config/agentic/skills` directory, so scanning both just doubles skill discovery.
set -gx OPENCODE_DISABLE_CLAUDE_CODE_SKILLS 1

# Make `Node.js` read the system keychain instead of its own bundled CA list, so
# `Node` ecosystem tools (`npm`, `yarn`, `npx`) trust whatever certificates are
# installed there, such as one presented by a proxy or VPN that terminates TLS.
set -gx NODE_USE_SYSTEM_CA 1

# Point the Android tooling at the SDK root, a cask cannot export it itself.
set -gx ANDROID_HOME /opt/homebrew/share/android-commandlinetools

# Activate `mise` environment for `Fish` shell.
mise activate fish | source

# Source needed `Fish` constants.
source $HOME/.config/fish/constants/colors.fish

# Source needed `Fish` functions.
source $HOME/.config/fish/functions/files.fish
source $HOME/.config/fish/functions/git.fish
source $HOME/.config/fish/functions/logs.fish
source $HOME/.config/fish/functions/emulators.fish
source $HOME/.config/fish/functions/sleep.fish
source $HOME/.config/fish/functions/keybindings.fish
source $HOME/.config/fish/functions/aliases.fish
source $HOME/.config/fish/functions/agentic.fish
source $HOME/.config/fish/functions/herdr.fish

# Puppeteer configuration for `M` series `MacBooks`.
set -gx PUPPETEER_SKIP_CHROMIUM_DOWNLOAD true
set -gx PUPPETEER_EXECUTABLE_PATH (which chromium)

# Add `SDKMAN` candidates to the `PATH`. Its init script is bash only, running it in a child
# `bash -i` changes nothing in `Fish` and costs a shell spawn on every new terminal.
# An unmatched wildcard in a `for` loop is silently empty.
set -gx SDKMAN_DIR "$HOME/.sdkman"
for candidate_bin in $SDKMAN_DIR/candidates/*/current/bin
    fish_add_path -g $candidate_bin
end
