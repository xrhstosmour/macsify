#!/bin/bash

# End any active Amphetamine session so it doesn't block sleep.
osascript -e 'if application "Amphetamine" is running then tell application "Amphetamine" to end session' 2>/dev/null

# Sleep the machine immediately.
pmset sleepnow
