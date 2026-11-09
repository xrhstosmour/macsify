# AGENTS.md

Personal macOS dotfiles/configuration repository.
Installed on a new machine via `install.sh`, which copies `.config/*` into `~/.config/`, installs `Homebrew` and Brewfile dependencies, then runs `configure.sh` (App Store applications, developer tools, `setup/agentic.sh` once `mise` has provided `node`, `additional_packages.txt`, `setup/*.sh`, `utilities/*.sh`).
This file documents the repository itself. For the agentic (AI assistant) subsystem's own architecture, see `.config/agentic/README.md`, don't duplicate it here.

## Directory map

| Path | Purpose |
| ---- | ------- |
| `core/` | Shell constants shared across scripts |
| `helpers/` | Shared shell functions: logging (`logs.sh`), prompts (`ui.sh`), Brewfile parsing (`brewfile.sh`), work or personal profile (`profile.sh`), the testable steps of `setup/agentic.sh` (`agentic.sh`) |
| `setup/` | Installation steps, `homebrew.sh` run directly by `install.sh`, `agentic.sh` run by `configure.sh` and also copies `.config/agentic` itself so it can be rerun alone after a merge, and runs `settings/herdr.sh` for the `Herdr` app's mods, the rest (developer tools, mobile toolchain, applications, shell, macOS preferences) run by `configure.sh` |
| `utilities/` | macOS system preference scripts, one per domain (`dock.sh`, `finder.sh`, `keyboard.sh`, `trackpad.sh`, etc.) |
| `settings/` | Third-party app config/preference files restored during install (`aerospace.toml`, `flameshot.ini`, `.plist.xml` files), and the scripts that configure applications |
| `packages/` | `base.Brewfile` plus `personal.Brewfile` and `work.Brewfile` that include it (Homebrew), `store_applications_ids.txt` and `personal.store_applications_ids.txt` (Mac App Store, via `mas`), `personal.skills.txt` (agentic skills removed on a work machine), `retired.skills.txt` (renamed or removed agentic skills, removed from the installed copy on every machine), `additional_packages.txt` (arbitrary install commands) |
| `.config/` | Copied verbatim to `~/.config/` by `install.sh`, contains app configs (`fish/`, `wezterm/`, `tig/config` which `tig` reads through `XDG_CONFIG_HOME` instead of `~/.tigrc`, `starship.toml`), executable utility scripts (`scripts/`, grouped in `power/`, `displays/`, `antivirus/`, `review/` and `git/` folders, chmod'd by `install.sh`, `git/editor.sh` is the `core.editor` of `.gitconfig`, `VS Code` only while it is open, `hx` otherwise), and the `agentic/` and `opencode/` subsystems |
| `.config/herdr-app/` | Config, layout and mods for the `Herdr` desktop app, plus the `Claude Code` hooks that report to it and resume agents after a reboot. Read `.config/herdr-app/README.md` before changing any of it |
| `claude/` | Global Claude Code settings (`settings.json`, `keybindings.json`), plugin config (`plugins/claude-hud/config.json`), and built-in subagent overrides (`agents/explore.md`, model injected from `models.txt`), copied to `~/.claude/` by `setup/agentic.sh`, which also installs each plugin `settings.json` turns on that is not installed yet, since an `enabledPlugins` entry never downloads one, and installs Apple's `xcode` plugin with `claude plugin install --yes` on the personal profile only, and enables it again after each copy, since it links from the installed Xcode, allowing external agents in Xcode's Intelligence settings stays a manual step |
| `.config/opencode/` | OpenCode config and plugins. `setup/agentic.sh` also `npm install -g`s and installs the third-party `opencode-status-hud` HUD plugin into `~/.config/opencode/plugin/`, and the `browse` MCP server (`@opencode/browse`, pinned, its hourly self-update set to `notify`) that lets OpenCode drive the real `Chrome`, each of its tools asks first through `"browse_*": "ask"` in `permission`, a page it reads could try to steer it. Its extension is added and paired by hand once, `browse install` opens the Chrome Web Store and pairs it, choose no agents there since `opencode.json` already has the entry |
| `Wallpapers/` | Desktop wallpaper images |

## `Explore` override

`claude/agents/explore.md` copies the built-in `Explore` `disallowedTools` and `omitClaudeMd`, which needs Claude Code 2.1.271 or later, re-check both against the built-in on each Claude Code upgrade.
Since it skips the global instructions, its Rules carry the shell safety and privacy rules from `.config/agentic/instructions/security.md` and `privacy.md`, and the `rg` search rule from `standards.md` Context Management, change them together.

## Fish functions

`.config/fish/functions/` holds reusable helpers invoked by abbreviations in `.config/fish/conf.d/abbr.fish`. Notably `git.fish` (rebasing, worktrees, fixups, `GitHub` PR helpers) and `agentic.fish` (`claude_session_list`/`opencode_session_list` and their delete counterparts). Check there before writing new shell logic for `git`/session-management needs.

## Mobile development toolchain

`setup/mobile.sh` owns everything `Flutter` needs to build for Android and iOS. It is opt-in, `configure.sh` asks for it in the developer tools section, only when the profile's Brewfile installs `flutter`, right after `utilities/development.sh`, which is why the `Mac App Store` step runs before that section, the iOS half needs `Xcode` already installed.
It installs the Android SDK packages, accepts their licences, creates the emulator and simulator devices, and points the command line tools at `Xcode`. The `JDK` is not its business, `utilities/development.sh` owns the `Java` pin.
The Android platform, build tools and `NDK` versions are read out of the installed `Flutter`'s `FlutterExtension.kt` instead of being hardcoded, so a `Flutter` upgrade does not leave the SDK behind. Every path is derived from `brew --prefix`.
The emulator and simulator device names are the one thing duplicated, between the script's constants and the `open_android_emulator`/`open_ios_emulator` launchers in `.config/fish/functions/emulators.fish`. Change them in both.
`Xcode` 27 has no `Simulator.app`, `DeviceHub` hosts the simulator window. Its sidebar is hidden through a preference written by `utilities/system.sh`, so `open_ios_emulator` opens on the device alone. The inspector panel and window floating have no preference behind them, set those once by hand and they stay. The simulator itself is switched to the dark appearance when the script creates it, matching `utilities/appearance.sh`.
SDK packages go through the `android` CLI that replaces the deprecated `sdkmanager`. It accepts each package's licence and writes it under `licenses` as it installs, so there is no separate licence acceptance step. The CLI updates itself apart from the cask, so the script runs `android update` first, a no-op when current, and a later cask upgrade that rolls it back is updated again on the next run. `avdmanager` still creates the emulator, the `android` CLI cannot name an `AVD` or build one from a concrete device profile such as `pixel_10_pro`, only from generic categories.
The standalone `android-platform-tools` cask is deliberately absent from the Brewfile. The `platform-tools` package installs the `adb` that Gradle and `Flutter` actually invoke inside the SDK, and a second, independently versioned `adb` in `Homebrew`'s binary directory means two `adb` servers fighting over port 5037. It also lets `Flutter` resolve the wrong SDK root, but only when `ANDROID_HOME` is unset, since `Flutter` prefers the environment and falls back to walking `adb` on the `PATH`.

## Script conventions

New shell scripts should match the existing pattern (see `install.sh`, `configure.sh`, `setup/agentic.sh`):

- `set -e` at the top, `trap "exit" INT` in entrypoint scripts.
- A `*_SCRIPT_DIRECTORY` constant computed with `cd "$(dirname "$0")" && pwd` (or `"${BASH_SOURCE[0]}"`), used for all relative paths.
- Source `helpers/logs.sh` (and `helpers/ui.sh`, `helpers/brewfile.sh` where relevant) instead of re-implementing logging or Brewfile parsing.
- Use `log_info`/`log_success`/`log_error`/`log_divider` for output, not raw `echo`.
- `log_divider` belongs to orchestrators (`install.sh`, `configure.sh`, `setup/preferences.sh`, `setup/security.sh`) and goes between two steps, never first or last. Leaf scripts and `apply_*` functions print none, so a step never doubles or drops its separator.
- Comments end with a period, placed above the line they describe.

## `.config/` is copied blindly

`install.sh` does `cp -R .config/* ~/.config/`.
Anything added under `.config/` must be safe to drop onto a real home directory as-is, no machine-specific secrets or paths that only exist on this machine.

## `opencode.json` is a template

`.config/opencode/opencode.json` is copied verbatim to `~/.config/opencode/opencode.json` by `setup/agentic.sh`, which then sets its `"agent"` block (models from `.config/agentic/models.txt`) with `jq`, through `inject_opencode_agent_models` in `helpers/agentic.sh`.
Edits to this file must stay valid JSON, an `"agent"` key in it is replaced by the injection.

## Usage

A 7 day log scan (2026-10-26) put the biggest usage on long sessions (about 33%), subagents (about 21%) and large tool output (about 10%), a rough weighted estimate.
The rules for all three live in the global `standards.md` Context Management, this repo only enforces them where it can.
In `Claude Code`, `bash-output-cap.sh` caps `Bash` output and idle compaction handles stale sessions, so session age and subagent use stay a written rule.
A 31 day scan (2026-11-09) put cache reads at most of the cost, so the first-turn context is the floor every turn pays. It grew from about 60K tokens (2026-10-27) to about 81K (2026-11-05) from the account side, connectors and org skills, not this repo. `deniedMcpServers` and `skillOverrides` in `claude/settings.json` are the levers, check `/context` in a fresh session after adding a connector or org skill.

## Testing changes

`tests/` holds plain `bash` tests run by `.github/workflows/lint.yml`, `tests/README.md` says what each one guarantees, read it before changing a tested script. Everything else has no automated test.
Verify by running the specific script that changed directly, most `setup/*.sh` and `utilities/*.sh` scripts are idempotent shell scripts safe to re-run. Use `brew bundle list --all --file=packages/personal.Brewfile` and the same for `work.Brewfile` to validate Brewfile changes without installing anything, never run `brew bundle` on `base.Brewfile` alone.
`configure.sh` assumes `install.sh` already installed `Homebrew` and Brewfile dependencies, running it standalone on a machine without `Homebrew` on `PATH` stops at its own `brew` check and asks for `install.sh` first.
