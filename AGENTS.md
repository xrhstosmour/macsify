# AGENTS.md

Personal macOS dotfiles/configuration repository.
Installed on a new machine via `install.sh`, which copies `.config/*` into `~/.config/`, installs `Homebrew` and Brewfile dependencies, runs `setup/agentic.sh`, then `configure.sh` (developer tools, packages, `setup/*.sh`, `utilities/*.sh`).
This file documents the repository itself. For the agentic (AI assistant) subsystem's own architecture, see `.config/agentic/README.md`, don't duplicate it here.

## Directory map

| Path | Purpose |
| ---- | ------- |
| `core/` | Shell constants shared across scripts |
| `helpers/` | Shared shell functions: logging (`logs.sh`), prompts (`ui.sh`), Brewfile parsing (`brewfile.sh`) |
| `setup/` | Installation steps, `homebrew.sh` and `agentic.sh` run directly by `install.sh`, the rest (developer tools, mobile toolchain, applications, shell, macOS preferences) run by `configure.sh` |
| `utilities/` | macOS system preference scripts, one per domain (`dock.sh`, `finder.sh`, `keyboard.sh`, `trackpad.sh`, etc.) |
| `settings/` | Third-party app config/preference files restored during install (`aerospace.toml`, `flameshot.ini`, `.plist.xml` files) |
| `packages/` | `Brewfile` (Homebrew), `store_applications_ids.txt` (Mac App Store, via `mas`), `additional_packages.txt` (arbitrary install commands) |
| `.config/` | Copied verbatim to `~/.config/` by `install.sh`, contains app configs (`fish/`, `wezterm/`, `starship.toml`), executable utility scripts (`scripts/`, chmod'd by `install.sh`), and the `agentic/` and `opencode/` subsystems |
| `claude/` | Global Claude Code settings (`settings.json`, `keybindings.json`) and plugin config (`plugins/claude-hud/config.json`), copied to `~/.claude/` by `setup/agentic.sh` |
| `.config/opencode/` | OpenCode config and plugins. `setup/agentic.sh` also `npm install -g`s and installs the third-party `opencode-status-hud` HUD plugin into `~/.config/opencode/plugin/` |
| `Wallpapers/` | Desktop wallpaper images |

## Fish functions

`.config/fish/functions/` holds reusable helpers invoked by abbreviations in `.config/fish/conf.d/abbr.fish`. Notably `git.fish` (rebasing, worktrees, fixups, `GitHub` PR helpers) and `agentic.fish` (`claude_session_list`/`opencode_session_list` and their delete counterparts). Check there before writing new shell logic for `git`/session-management needs.

## Mobile development toolchain

`setup/mobile.sh` owns everything `Flutter` needs to build for Android and iOS. It is opt-in, `configure.sh` asks for it in the developer tools section, right after `utilities/development.sh`, which is why the `Mac App Store` step runs before that section, the iOS half needs `Xcode` already installed.
It installs the Android SDK packages, accepts their licences, creates the emulator and simulator devices, and points the command line tools at `Xcode`. The `JDK` is not its business, `utilities/development.sh` owns the `Java` pin.
The Android platform, build tools and `NDK` versions are read out of the installed `Flutter`'s `FlutterExtension.kt` instead of being hardcoded, so a `Flutter` upgrade does not leave the SDK behind. Every path is derived from `brew --prefix`.
The emulator and simulator device names are the one thing duplicated, between the script's constants and the `open_android_emulator`/`open_ios_emulator` launchers in `.config/fish/functions/emulators.fish`. Change them in both.
`Xcode` 27 has no `Simulator.app`, `DeviceHub` hosts the simulator window. Its sidebar is hidden through a preference written by `utilities/system.sh`, so `open_ios_emulator` opens on the device alone. The inspector panel and window floating have no preference behind them, set those once by hand and they stay. The simulator itself is switched to the dark appearance when the script creates it, matching `utilities/appearance.sh`.
SDK packages go through the `android` CLI that replaces the deprecated `sdkmanager`. It accepts each package's licence and writes it under `licenses` as it installs, so there is no separate licence acceptance step. `avdmanager` still creates the emulator, the `android` CLI cannot name an `AVD` or build one from a concrete device profile such as `pixel_10_pro`, only from generic categories.
The standalone `android-platform-tools` cask is deliberately absent from the Brewfile. The `platform-tools` package installs the `adb` that Gradle and `Flutter` actually invoke inside the SDK, and a second, independently versioned `adb` in `Homebrew`'s binary directory means two `adb` servers fighting over port 5037. It also lets `Flutter` resolve the wrong SDK root, but only when `ANDROID_HOME` is unset, since `Flutter` prefers the environment and falls back to walking `adb` on the `PATH`.

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
`configure.sh` assumes `install.sh` already installed `Homebrew` and Brewfile dependencies, running it standalone on a machine without `Homebrew` on `PATH` fails inside `setup/developer.sh`.
