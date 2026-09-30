local wezterm = require 'wezterm'

-- Define the function that applies window configuration.
local function apply_configuration(configuration)
    configuration.initial_rows = 40
    configuration.initial_cols = 120
    configuration.window_background_opacity = 0.75
    configuration.window_close_confirmation = "NeverPrompt"
    configuration.window_padding = {left = 5, right = 5, top = 5, bottom = 5}

    -- Manual "full window" resize for a `herdr` console, triggered by the `hamx`
    -- fish abbreviation's `OSC 1337 SetUserVar`. `window:maximize()` fills the
    -- current screen without leaving the current `AeroSpace`/macOS Space, unlike
    -- `AeroSpace`'s own `fullscreen` command on a floating window.
    wezterm.on(
        "user-var-changed",
        function(window, pane, name, value)
            if name == "herdr_maximize" then
                window:maximize()
            end
        end
    )
end

return apply_configuration
