# Functions for moving the current `herdr` tab between workspaces (`herdr`'s
# own sidebar-grouped concept, not a macOS Space or an `AeroSpace` workspace,
# `herdr`'s socket API has no way to reach either of those). Guarded on
# `$HERDR_ENV`/`$HERDR_PANE_ID` since those only exist inside a live `herdr`
# pane, moving a pane that doesn't exist would just error out.

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

    set -l workspace_data (herdr workspace list | jq -re '.result.workspaces[] | select(.workspace_id != env.HERDR_WORKSPACE_ID) | "\(.workspace_id)|\(.label)"')
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
