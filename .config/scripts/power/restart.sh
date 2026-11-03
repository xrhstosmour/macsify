#!/bin/bash
# ! You need to grant `System Settings → Privacy & Security → Accessibility` permissions to the application running this script for it to work properly.

# Kill any stuck `osascript` processes first.
pkill -f "System Events" 2>/dev/null

# Small delay to ensure clean state.
sleep 0.1

# Restart by sending restart command using `AppleScript`.
osascript -e 'tell application "System Events" to restart' &
