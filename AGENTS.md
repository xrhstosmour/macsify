# AGENTS.md

Personal macOS dotfiles/configuration repository.
Installed on a new machine via `install.sh`, which copies `.config/*` into `~/.config/`, installs `Homebrew` and Brewfile dependencies, runs `setup/agentic.sh`, then `configure.sh` (developer tools, packages, `setup/*.sh`, `utilities/*.sh`).
This file documents the repository itself. For the agentic (AI assistant) subsystem's own architecture, see `.config/agentic/README.md`, don't duplicate it here.

## Directory map

| Path | Purpose |
| ---- | ------- |
| `core/` | Shell constants shared across scripts |
| `helpers/` | Shared shell functions: logging (`logs.sh`), prompts (`ui.sh`), Brewfile parsing (`brewfile.sh`), work or personal profile (`profile.sh`), the testable steps of `setup/agentic.sh` (`agentic.sh`) |
| `setup/` | Installation steps, `homebrew.sh` and `agentic.sh` run directly by `install.sh`, `agentic.sh` also copies `.config/agentic` itself first so it can be rerun alone after a merge, the rest (developer tools, mobile toolchain, applications, shell, macOS preferences) run by `configure.sh` |
| `utilities/` | macOS system preference scripts, one per domain (`dock.sh`, `finder.sh`, `keyboard.sh`, `trackpad.sh`, etc.) |
| `settings/` | Third-party app config/preference files restored during install (`aerospace.toml`, `flameshot.ini`, `.plist.xml` files) |
| `packages/` | `base.Brewfile` plus `personal.Brewfile` and `work.Brewfile` that include it (Homebrew), `store_applications_ids.txt` and `personal.store_applications_ids.txt` (Mac App Store, via `mas`), `personal.skills.txt` (agentic skills removed on a work machine), `additional_packages.txt` (arbitrary install commands) |
| `.config/` | Copied verbatim to `~/.config/` by `install.sh`, contains app configs (`fish/`, `wezterm/`, `starship.toml`), executable utility scripts (`scripts/`, chmod'd by `install.sh`), and the `agentic/` and `opencode/` subsystems |
| `.config/herdr-repo-sync/` | Local `herdr` plugin linked in place by `setup/agentic.sh`, runs the `gfrb` fetch and rebase in every `herdr` pane checked out on `main` or `master`. It runs from `~/.config` without this repository, so it carries its own logging and uses `set -u` without `set -e` to keep going past one failing repository, an exception to the script conventions below |
| `.config/herdr-worktree-cleanup/` | Local `herdr` plugin linked in place by `setup/agentic.sh`, records worktrees under `~/Developer/worktrees` that `herdr` opens and removes one with `git worktree remove` when its workspace closes, no pane is left in it, it is on a branch and it has no uncommitted or untracked changes. The branch is deleted only when merged, into the origin default branch or as the head of a merged pull request, otherwise kept. Ignored files are deleted. A worktree made outside `herdr` is tracked once a pane `cd`s into it, the fish hook in `.config/fish/conf.d/herdr-worktree-open.fish` opens it. One named `review` or `reviews`, or listed in `~/.config/herdr-worktree-cleanup/protected` by directory name or physical absolute path, is never touched. Same conventions as `herdr-repo-sync`, own logging and `set -u` without `set -e` |
| `claude/` | Global Claude Code settings (`settings.json`, `keybindings.json`), plugin config (`plugins/claude-hud/config.json`), and built-in subagent overrides (`agents/explore.md`, model injected from `models.txt`), copied to `~/.claude/` by `setup/agentic.sh` |
| `.config/opencode/` | OpenCode config and plugins. `setup/agentic.sh` also `npm install -g`s and installs the third-party `opencode-status-hud` HUD plugin into `~/.config/opencode/plugin/` |
| `Wallpapers/` | Desktop wallpaper images |

## `Explore` override

`claude/agents/explore.md` copies the built-in `Explore` `disallowedTools` and `omitClaudeMd`, which needs Claude Code 2.1.271 or later, re-check both against the built-in on each Claude Code upgrade.
Since it skips the global instructions, its Rules carry the shell safety and privacy rules from `.config/agentic/instructions/security.md` and `privacy.md`, change them together.

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
## Testing changes

`tests/` holds plain `bash` tests, `agentic.sh` (personal skills are removed whatever the line ending, and the `opencode.json` agent models are injected), `auto-session-title.sh` (the title hook stops rescanning a transcript whose answer cannot change), `bash-output-cap.sh` (the hook rewrites a command without changing its output or exit status, cuts it at the cap, and never rewrites a denied or asked command), `webfetch-guard.sh` (the `Claude Code` hook and the `opencode` plugin block the same hosts, userinfo and trailing-dot forms included), `worktree-cleanup.sh` (the cleanup keeps a worktree when `herdr`'s pane list is unreadable or it holds untracked work, and deletes its branch only when merged), `repo-sync.sh` (only a clean `main` checkout is rebased, a conflicting rebase is aborted), `profile.sh` (how the work or personal profile is picked and saved, and which Brewfiles it reads) and `dock.sh` (which `Dock` is Apple's default and where missing applications go, it needs macOS and skips on the `Linux` runner, so run it locally after a `Dock` change), all run by `.github/workflows/lint.yml` next to the `shellcheck`, `fish` and `JSON` checks. Everything else has no automated test.
Verify by running the specific script that changed directly, most `setup/*.sh` and `utilities/*.sh` scripts are idempotent shell scripts safe to re-run. Use `brew bundle list --all --file=packages/personal.Brewfile` and the same for `work.Brewfile` to validate Brewfile changes without installing anything, never run `brew bundle` on `base.Brewfile` alone.
`configure.sh` assumes `install.sh` already installed `Homebrew` and Brewfile dependencies, running it standalone on a machine without `Homebrew` on `PATH` fails inside `setup/developer.sh`.
