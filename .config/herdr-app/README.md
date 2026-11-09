# `Herdr` app configuration

Config for the `Herdr` desktop app, the `herdr-app` cask in `packages/base.Brewfile`. `setup/agentic.sh` runs `settings/herdr.sh`, which copies the community mods at pinned commits, reviewed before each bump, and checks them. The app rewrites its own `AGENTS.md` on start, read that for the key, command and mod reference.

## Files

- `settings.json`, `themes/wezterm.json` (the `WezTerm` palette).
- `keys.json` is the whole key map, the app does not merge it with its defaults, so it holds the shipped `keys.macos.json` (snapshot of 2026-11-03) plus our keys, compare it after an app update.
- `layouts/workbench.json` is the shipped `main` layout with the `space-folders` sidebar, a hidden right panel holding `pull-request` and `git-graph`, and four invisible blocks that run the `worktree-cleanup`, `repository-sync` and `tab-names` mods and the `pull-request` watcher. A mod runs only as a block of the active layout, so those four stop while another layout is selected.
- `settings/herdr.sh` selects the `workbench` layout with `layout.switch` while the app is running, and sets the `layout` key of the app's `shared.json` with `jq` while it is closed. A file that is not valid `JSON` is left alone and `ctrl-shift-l` stays the fallback.

## Vendored mods

Vendored with small edits, because the app replaces shipped mods on every start and a community mod is not ours to patch in place. A bump of any means diffing upstream again, `agents-compact` and `tabs-inline` against the shipped `agents` and `tabs` of the app version in their header and `mod.json`.

- `mods/tmux-prefix`, its `BINDINGS` hold our `tmux`-style prefix keys.
- `mods/space-folders`, upstream at a pinned commit, repo and branch text hidden, a space named like its folder shows its branch. A branch button next to a folder's + opens `mods/worktree-developer`, a clone of the shipped `worktree` whose `ROOT` is `~/Developer/worktrees`. The shipped one behind the space menu is covered by a `~/.herdr/worktrees` link to it that `settings/herdr.sh` makes.
- `mods/agents-compact`, a clone of the shipped `agents`, program name hidden, a row shows only the agent's own title, the space name only when it has none. `layouts/workbench.json` uses it.
- `mods/tabs-inline`, a clone of the shipped `tabs`, the + right after the last tab instead of at the far right and opening a terminal instead of the new menu. It adds a GitHub button next to Files and Changes that opens the `pull-request` panel, shown only while the branch of the focused terminal has an open pull request, and a Graph button for the `git-graph` block. `layouts/workbench.json` uses it.

## Our mods

- `mods/worktree-cleanup` watches `panes()` (the app has no workspace-closed event) and removes a clean linked worktree under `~/Developer/worktrees` or `~/.herdr/worktrees` 10 seconds after its last terminal is gone, only when its branch is merged (an ancestor of the origin default branch, or the tip of a merged pull request) or pushed in full (every commit is on its own origin branch as of the last fetch), and deletes that branch. A detached HEAD goes only when its commit is on the origin default branch. Worktrees made by agents or another terminal never get a pane, so both roots are scanned every 10 minutes for them, and those go only when a commit was made in them and is merged, not merely pushed, and nothing at their top or in their git directory changed for an hour, an agent outside the app may still work there. `review`, `reviews`, `resolves`, `playground`, `trivial`, `trivials` and the names or physical absolute paths listed one per line in `~/.config/herdr-app/worktree-cleanup-protected` are never touched, an unmerged and unpushed worktree stays whole. Its decisions are in `logic.js`, covered by `tests/worktree-cleanup-application.sh`.
- `mods/repository-sync` hands each new pane folder to its `repository-sync.sh`, which fetches and rebases a clean `main` or `master` checkout, throttled per checkout, logs to `~/.cache/herdr-app/repository-sync/sync.log`. It runs from `~/.config` without this repository, so it carries its own logging and uses `set -u` without `set -e` to keep going past one failing repository, an exception to the script conventions of the root `AGENTS.md`. Covered by `tests/repository-sync.sh`.
- `mods/tab-names` names tabs (`folder · program`, the program left out when it has an icon, a tab the person renamed is left alone, a leading 🔴 🟡 🟢 from `herdr_tab_color` is kept). Its rules are in `logic.js`, covered by `tests/tab-names.sh`.
- `mods/pull-request`, its invisible `pull-request-watch` block asks `gh` for an open pull request of the focused terminal's branch, which shows the GitHub button, and its panel block draws that pull request natively like github.com from `gh` data, with its comment, review, merge box and other buttons. The header of its `main.js` says what each does and why. Its rules are in `logic.js`, covered by `tests/pull-request.sh`.

## Agents in the app

- `herdr-core` does not recognise agents by name, they must report over `OSC 7501`, so `.config/agentic/hooks/herdr-application-status.sh` (wired in `claude/settings.json`, covered by `tests/herdr-application-status.sh`) reports `Claude Code`'s state from inside an app terminal. `OpenCode`, `Codex` and `Copilot CLI` do not report to the app yet.
- Agents do not survive a reboot, `herdr-core` brings back a terminal's `fish` and folder only. So `.config/agentic/hooks/herdr-application-resume.sh` (the `Claude Code` `SessionStart` hook and the `OpenCode` plugin `opencode-herdr-resume.js`, linked by `setup/agentic.sh`) records the session as a `resume.record` label on the `herdr-core` terminal. It goes with the terminal, `Claude Code`'s `SessionEnd` hook forgets it when the person leaves.
- `.config/fish/conf.d/herdr-agent-resume.fish` resumes it at the terminal's own first prompt, forgetting it when the agent returns by itself. Only `--permission-mode`, `--model`, `-m`, `--agent` and `--add-dir` of the flags the agent started with are kept and replayed, checked again when read by one shared filter. `--dangerously-skip-permissions` is never replayed and `--permission-mode` only with `default`, `acceptEdits`, `plan` or `auto`, a reboot must not turn a bypass back on unasked. Covered by `tests/herdr-application-resume.sh`.
- The fish helpers `herdr_tab_color` and `_herdr_open_worktree_pane` detect the app by `HC_TERMINAL_ID`.
