#!/bin/bash

# `herdr-automatic-rename` overrides. See the plugin's `config.example.sh` for
# every knob (https://github.com/qu8n/herdr-automatic-rename), only what
# diverges from its defaults lives here. Consumed by `automatic-rename.sh`
# when it sources this file, not directly by anything in this repo.
# shellcheck disable=SC2034

# Looser budgets than the defaults (20/28/12): trimming a name away was
# costing the detail that told two tabs apart, so these lean toward keeping
# the whole name over keeping the row short.
MAX_NAME_LEN=40
MAX_TITLE_LEN=48
MAX_CONTEXT_LEN=24

# Keep the task's keywords instead of showing the agent's sentence with the
# tail cut off at MAX_TITLE_LEN, that tail is usually where the detail that
# actually tells tabs apart lives.
TITLE_CONDENSE=1

# The sidebar and tab bar already show tabs/agents/workspaces in their sorted
# order, a `[1]`/`[2]` jump-key prefix on every row repeats what the position
# already says. `AUTO_INDEX_TABS`/`_AGENTS`/`_WORKSPACES` default to this and
# override it individually, left at the single "number nothing" knob here.
AUTO_INDEX=0

# Match `.config/wezterm/tabs.lua`'s own `format-tab-title` style (`program ·
# path`, no branch): same separator, branch left out. The join order itself
# is hardcoded in the plugin's `ar_compose` (`naming.sh`) as path-then-program,
# not configurable, so this comes out as `path · program`, reversed from
# `WezTerm`'s `program · path`, rather than an exact match.
CONTEXT_SEP=' · '
SHOW_BRANCH=0
