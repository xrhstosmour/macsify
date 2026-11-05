# Function for coloring the current tab of the `Herdr` desktop app. Guarded on
# `$HC_TERMINAL_ID`, which only exists in the app's terminals.

# Color emojis `herdr_tab_color` prefixes onto a tab's name. Keep this list
# in sync with the `hasr`/`hasy`/`hasg` abbreviations in `abbr.fish`, which
# each hardcode one of these colors.
set -g HERDR_TAB_COLORS 🔴 🟡 🟢

# Function to prefix the current tab's name with a color emoji.
# Strips a color emoji this function previously added so colors don't stack.
# The app's `tab-names` mod keeps the color across its automatic renames.
# Usage:
#   herdr_tab_color <emoji>
function herdr_tab_color
    if test -z "$argv[1]"
        log_error "Usage: herdr_tab_color <emoji>"
        return 1
    end
    if test -z "$HC_TERMINAL_ID"
        log_error "Not inside a Herdr app terminal!"
        return 1
    end

    set -l app_tab (herdr-app ls | jq -r --arg terminal "$HC_TERMINAL_ID" '.spaces[].tabs[] | select(any(.terminals[]; .terminal == $terminal)) | "\(.id)\t\(.name)"' | string split \t)
    set -l tab_id $app_tab[1]
    set -l current_label $app_tab[2]
    if test -z "$tab_id"
        log_error "Could not resolve the current tab! (see any herdr error above)"
        return 1
    end

    set -l emoji "$argv[1]"
    if test -z "$current_label"
        log_error "Could not read the current tab's name! (see any herdr error above)"
        return 1
    end

    for color in $HERDR_TAB_COLORS
        set -l previous_emoji "$color "
        if string match -q -- "$previous_emoji*" "$current_label"
            set current_label (string sub -s (math (string length -- "$previous_emoji") + 1) -- "$current_label")
            break
        end
    end

    herdr-app do tab.rename --id "$tab_id" --name "$emoji $current_label" >/dev/null
end
