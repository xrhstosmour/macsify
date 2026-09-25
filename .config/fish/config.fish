# Add `Homebrew`'s binary directory to the `PATH` environment variable.
fish_add_path "/opt/homebrew/bin/"

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

# Opt out of `Hyperframes` usage telemetry, which otherwise reports on an
# opt-out basis and links usage to a `HeyGen` account once signed in.
# Compared against the literal string `1`.
set -gx HYPERFRAMES_NO_TELEMETRY 1

# Make `Node.js` read the system keychain instead of its own bundled CA list, so
# `Node` ecosystem tools (`npm`, `yarn`, `npx`) trust whatever certificates are
# installed there, such as one presented by a proxy or VPN that terminates TLS.
set -gx NODE_USE_SYSTEM_CA 1

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

# Puppeteer configuration for `M` series `MacBooks`.
set -gx PUPPETEER_SKIP_CHROMIUM_DOWNLOAD true
set -gx PUPPETEER_EXECUTABLE_PATH (which chromium)

# Add `SDKMAN` support for `Fish` shell only at the end of this file.
# Only in interactive shells, `bash -i` needs a real terminal and otherwise
# prints "no job control" noise into non-interactive subshells (eg. `fzf` previews).
set -gx SDKMAN_DIR "$HOME/.sdkman"
if status is-interactive
    test -s "$HOME/.sdkman/bin/sdkman-init.sh" && bash -i -c 'source "$HOME/.sdkman/bin/sdkman-init.sh"'
end
