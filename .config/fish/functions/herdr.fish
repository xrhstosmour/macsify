# Functions for opening `herdr`, coloring the current tab, and moving it between workspaces (`herdr`'s
# own sidebar-grouped concept, not a macOS Space or an `AeroSpace` workspace,
# `herdr`'s socket API has no way to reach either of those). Guarded on
# `$HERDR_ENV`/`$HERDR_PANE_ID` since those only exist inside a live `herdr`
# pane, moving a pane that doesn't exist would just error out.

# Color emojis `herdr_tab_color` prefixes onto a tab's label. Keep this list
# in sync with the `hasr`/`hasy`/`hasg` abbreviations in `abbr.fish`, which
# each hardcode one of these colors.
set -g HERDR_TAB_COLORS 🔴 🟡 🟢

# Prints a field of the calling pane, read live from `herdr`. The inherited
# `$HERDR_TAB_ID`/`$HERDR_WORKSPACE_ID` go stale once the pane is moved to
# another workspace or tab, a move hands out new IDs and the old tab ID stops
# resolving (`tab_not_found`).
# Usage:
#   _herdr_current_pane_field <tab_id|workspace_id>
function _herdr_current_pane_field
    herdr pane current --current | jq -re ".result.pane.$argv[1] // empty"
end

# Function to move the current tab into a brand-new herdr workspace.
# Usage:
#   herdr_move_to_new_workspace [label]
function herdr_move_to_new_workspace
    if not test "$HERDR_ENV" = 1; or not test -n "$HERDR_PANE_ID"
        log_error "Not inside a herdr pane!"
        return 1
    end

    set -l label "$argv[1]"
    if test -n "$label"
        herdr pane move "$HERDR_PANE_ID" --new-workspace --label "$label" --focus
    else
        herdr pane move "$HERDR_PANE_ID" --new-workspace --focus
    end
end

# Function to fzf-pick an existing herdr workspace and move the current tab into it.
# Usage:
#   herdr_move_to_workspace
function herdr_move_to_workspace
    if not test "$HERDR_ENV" = 1; or not test -n "$HERDR_PANE_ID"
        log_error "Not inside a herdr pane!"
        return 1
    end

    set -l current_workspace_id (_herdr_current_pane_field workspace_id)
    if test -z "$current_workspace_id"
        log_error "Could not resolve the current workspace! (see any herdr error above)"
        return 1
    end
    set -l workspace_data (herdr workspace list | jq -re --arg current "$current_workspace_id" '.result.workspaces[] | select(.workspace_id != $current) | "\(.workspace_id)|\(.label)"')
    if test -z "$workspace_data"
        log_error "No other herdr workspaces found! (see any herdr error above)"
        return 1
    end

    set -l selected (printf '%s\n' $workspace_data | env SHELL=/bin/bash fzf --ansi --layout=reverse -d'|' --with-nth=2)
    if test -z "$selected"
        return 0
    end

    set -l workspace_id (echo "$selected" | cut -d'|' -f1)
    herdr pane move "$HERDR_PANE_ID" --new-tab --workspace "$workspace_id" --focus
end

# Function to prefix the current herdr tab's label with a color emoji.
# Strips a color emoji this function previously added so colors don't stack.
# Renaming a tab opts it out of herdr-automatic-rename's live naming from then
# on, an accepted tradeoff since herdr has no other way to color a tab.
# Usage:
#   herdr_tab_color <emoji>
function herdr_tab_color
    if test -z "$argv[1]"
        log_error "Usage: herdr_tab_color <emoji>"
        return 1
    end
    if not test "$HERDR_ENV" = 1; or not test -n "$HERDR_PANE_ID"
        log_error "Not inside a herdr pane!"
        return 1
    end

    set -l tab_id (_herdr_current_pane_field tab_id)
    if test -z "$tab_id"
        log_error "Could not resolve the current tab! (see any herdr error above)"
        return 1
    end

    set -l emoji "$argv[1]"
    set -l current_label (herdr tab get "$tab_id" | jq -re '.result.tab.label // empty')
    if test -z "$current_label"
        log_error "Could not read the current tab's label! (see any herdr error above)"
        return 1
    end

    for color in $HERDR_TAB_COLORS
        set -l previous_emoji "$color "
        if string match -q -- "$previous_emoji*" "$current_label"
            set current_label (string sub -s (math (string length -- "$previous_emoji") + 1) -- "$current_label")
            break
        end
    end

    herdr tab rename "$tab_id" "$emoji $current_label"
end
