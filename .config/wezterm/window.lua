local wezterm = require 'wezterm'

-- Define the function that applies window configuration.
local function apply_configuration(configuration)
    configuration.initial_rows = 40
    configuration.initial_cols = 120
    configuration.window_background_opacity = 0.75
    configuration.window_close_confirmation = "NeverPrompt"
    configuration.window_padding = {left = 5, right = 5, top = 5, bottom = 5}

    -- Large centered resize for a `herdr` console, triggered by the `OSC 1337
    -- SetUserVar` that the `hamx` abbreviation and `herdr_open` (`ha`) send. It
    -- takes a fraction of the active screen instead of maximizing, so the status
    -- bar stays visible, and it does not leave the current `AeroSpace`/macOS Space.
    local herdr_window_scale = 0.7

    wezterm.on(
        "user-var-changed",
        function(window, pane, name, value)
            if name == "herdr_maximize" then
                local screen = wezterm.gui.screens().active
                local margin = (1 - herdr_window_scale) / 2
                window:set_inner_size(screen.width * herdr_window_scale, screen.height * herdr_window_scale)
                window:set_position(screen.x + screen.width * margin, screen.y + screen.height * margin)
            end
        end
    )
end

return apply_configuration
