#!/bin/bash

# With only the built-in screen and one external screen, and no external keyboard
# connected (the laptop's own keyboard is in front of you), puts the external screen
# above the built-in one, centered. The placing is done by the compiled
# `arrange_displays.swift`, which leaves any other number of screens alone. With an
# external keyboard nothing is touched, the arrangement stays as the person set it.
# Run on every display change by `reload_environment.sh`, before `AeroSpace`
# distributes workspaces.

ARRANGE_BINARY="$HOME/.config/scripts/displays/arrange_displays"
[ -x "$ARRANGE_BINARY" ] || exit 0

# True when a keyboard that is not the built-in one is connected, any HID keyboard
# whose transport is not the internal `FIFO`.
external_keyboard_connected() {
    ioreg -r -c IOHIDDevice -l 2>/dev/null | awk '
        /\+-o / { if (page == 1 && usage == 6 && transport != "FIFO" && transport != "") found = 1; transport = ""; page = ""; usage = "" }
        /"Transport" = / { split($0, a, "\""); transport = a[4] }
        /"PrimaryUsagePage" = / { page = $NF }
        /"PrimaryUsage" = / { usage = $NF }
        END { if (page == 1 && usage == 6 && transport != "FIFO" && transport != "") found = 1; exit !found }'
}

external_keyboard_connected && exit 0

"$ARRANGE_BINARY"
