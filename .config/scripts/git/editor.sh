#!/usr/bin/env bash
# Git's `core.editor`: `VS Code` while it is running, so a rebase todo list or a commit message opens next to the code and its diff, otherwise `hx` in the terminal, so a git command never starts `VS Code` just to edit one file.
# It runs from ~/.config without the macsify repository, so it has no shared helpers. `vi` is the last resort on a machine where `Helix` is not installed yet.

set -e

if pgrep -x Code >/dev/null 2>&1 && command -v code >/dev/null 2>&1; then
  exec code --wait "$@"
fi
if command -v hx >/dev/null 2>&1; then
  exec hx "$@"
fi
exec vi "$@"
