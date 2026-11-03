#!/bin/bash
# ! You need to grant `System Settings → Privacy & Security → Accessibility` permissions to the application running this script for it to work properly.

# Kill any stuck `osascript` processes first.
pkill -f "System Events" 2>/dev/null

# Small delay to ensure clean state.
sleep 0.1

# Lock screen by sending `Control+Command+Q` using `AppleScript`.
osascript -e 'tell application "System Events" to key code 12 using {control down, command down}' &
