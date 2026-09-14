# Function to start an indefinite `Amphetamine` session to prevent sleep.
# Usage:
#   disable_sleep
function disable_sleep --description "Start an indefinite Amphetamine session to prevent sleep."
    osascript -e 'tell application "Amphetamine" to start new session with options {duration:0, interval:0, displaySleepAllowed:false}'
end

# Function to end the active `Amphetamine` session to allow sleep.
# Usage:
#   enable_sleep
function enable_sleep --description "End the active Amphetamine session to allow sleep."
    osascript -e 'if application "Amphetamine" is running then tell application "Amphetamine" to end session'
end
