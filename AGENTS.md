# AGENTS.md

Personal macOS dotfiles/configuration repository.
Installed on a new machine via `install.sh`, which copies `.config/*` into `~/.config/`, runs `setup/agentic.sh`, then `configure.sh` (Homebrew, packages, `setup/*.sh`, `utilities/*.sh`).
This file documents the repository itself. For the agentic (AI assistant) subsystem's own architecture, see `.config/agentic/README.md`, don't duplicate it here.

## Directory map

| Path | Purpose |
| ---- | ------- |
| `core/` | Shell constants shared across scripts |
| `helpers/` | Shared shell functions: logging (`logs.sh`), prompts (`ui.sh`), Brewfile parsing (`brewfile.sh`) |
| `setup/` | Installation steps run by `configure.sh` (Homebrew, developer tools, applications, shell, macOS preferences, agentic config) |
| `utilities/` | macOS system preference scripts, one per domain (`dock.sh`, `finder.sh`, `keyboard.sh`, `trackpad.sh`, etc.) |
| `settings/` | Third-party app config/preference files restored during install (`aerospace.toml`, `flameshot.ini`, `.plist.xml` files) |
| `packages/` | `Brewfile` (Homebrew), `store_applications_ids.txt` (Mac App Store, via `mas`), `additional_packages.txt` (arbitrary install commands) |
| `.config/` | Copied verbatim to `~/.config/` by `install.sh`, contains app configs (`fish/`, `wezterm/`, `starship.toml`) and the `agentic/` and `opencode/` subsystems |
| `claude/` | Global Claude Code settings (`settings.json`, `keybindings.json`), copied to `~/.claude/` by `setup/agentic.sh` |
| `Wallpapers/` | Desktop wallpaper images |

## Script conventions

New shell scripts should match the existing pattern (see `install.sh`, `configure.sh`, `setup/agentic.sh`):

- `set -e` at the top, `trap "exit" INT` in entrypoint scripts.
- A `*_SCRIPT_DIRECTORY` constant computed with `cd "$(dirname "$0")" && pwd` (or `"${BASH_SOURCE[0]}"`), used for all relative paths.
- Source `helpers/logs.sh` (and `helpers/ui.sh`, `helpers/brewfile.sh` where relevant) instead of re-implementing logging or Brewfile parsing.
- Use `log_info`/`log_success`/`log_error`/`log_divider` for output, not raw `echo`.
- Comments end with a period, placed above the line they describe.

## `.config/` is copied blindly

`install.sh` does `cp -R .config/* ~/.config/`.
Anything added under `.config/` must be safe to drop onto a real home directory as-is, no machine-specific secrets or paths that only exist on this machine.

## `opencode.json` is a template

`.config/opencode/opencode.json` is copied verbatim to `~/.config/opencode/opencode.json` by `setup/agentic.sh`, which then injects an `"agent"` block (models from `.config/agentic/models.txt`) via `sed`.
Edits to this file must stay valid JSON before that injection, and must not touch the line containing `"default_agent": "leader",` in a way that breaks the `sed` insertion anchor.

## Testing changes

No test suite.
Verify by running the specific script that changed directly, most `setup/*.sh` and `utilities/*.sh` scripts are idempotent shell scripts safe to re-run. Use `brew bundle check --file=packages/Brewfile` to validate Brewfile changes without installing anything.
