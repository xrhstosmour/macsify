#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
ANTIVIRUS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import functions and flags.
source "$ANTIVIRUS_SCRIPT_DIRECTORY/../helpers/logs.sh"
source "$ANTIVIRUS_SCRIPT_DIRECTORY/../helpers/launch_agent.sh"

SCAN_SCRIPT="$HOME/.config/antivirus/scan.sh"
QUARANTINE_DIRECTORY="$HOME/.local/share/antivirus/quarantine"

if ! command -v clamscan &>/dev/null; then
    log_warning "'ClamAV' not found, skipping the antivirus setup."
    exit 0
fi

if [ ! -f "$SCAN_SCRIPT" ]; then
    log_warning "'$SCAN_SCRIPT' not found, run install.sh first."
    exit 0
fi

# `Homebrew` ships `freshclam.conf.sample` with an `Example` line that blocks every
# run, write the real file without it. An existing one is left alone.
CLAMAV_CONFIGURATION_DIRECTORY="$(brew --prefix)/etc/clamav"
if [ ! -f "$CLAMAV_CONFIGURATION_DIRECTORY/freshclam.conf" ]; then
    grep -v '^Example' "$CLAMAV_CONFIGURATION_DIRECTORY/freshclam.conf.sample" >"$CLAMAV_CONFIGURATION_DIRECTORY/freshclam.conf"
    log_success "Created 'freshclam.conf'."
fi

# The first download is the biggest, later runs are small daily updates.
log_info "Downloading the 'ClamAV' signatures..."
freshclam || log_warning "Signature download failed, the nightly update retries."

mkdir -p "$QUARANTINE_DIRECTORY"
chmod 700 "$QUARANTINE_DIRECTORY"

FRESHCLAM_PATH="$(brew --prefix)/bin/freshclam"

# Nightly signature update at 02:00.
install_launch_agent "com.local.antivirus.update" "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key><string>com.local.antivirus.update</string>
    <key>ProgramArguments</key><array><string>$FRESHCLAM_PATH</string></array>
    <key>StartCalendarInterval</key><dict><key>Hour</key><integer>2</integer><key>Minute</key><integer>0</integer></dict>
</dict>
</plist>"

# Scan what lands in `Downloads`, `Desktop` and on plugged-in drives.
install_launch_agent "com.local.antivirus.watch" "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key><string>com.local.antivirus.watch</string>
    <key>ProgramArguments</key><array><string>/bin/bash</string><string>$SCAN_SCRIPT</string><string>--recent</string><string>$HOME/Downloads</string><string>$HOME/Desktop</string><string>/Volumes</string></array>
    <key>WatchPaths</key><array><string>$HOME/Downloads</string><string>$HOME/Desktop</string><string>/Volumes</string></array>
    <key>ThrottleInterval</key><integer>30</integer>
</dict>
</plist>"

# Full scan every Sunday at 03:00.
install_launch_agent "com.local.antivirus.weekly" "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key><string>com.local.antivirus.weekly</string>
    <key>ProgramArguments</key><array><string>/bin/bash</string><string>$SCAN_SCRIPT</string><string>$HOME/Downloads</string><string>$HOME/Desktop</string><string>$HOME/Documents</string></array>
    <key>StartCalendarInterval</key><dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>
</dict>
</plist>"

# Daily startup check at 09:00, then the report of everything logged since the last one.
install_launch_agent "com.local.antivirus.startup" "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key><string>com.local.antivirus.startup</string>
    <key>ProgramArguments</key><array><string>/bin/bash</string><string>-c</string><string>$HOME/.config/antivirus/startup-difference.sh; $HOME/.config/antivirus/report.sh</string></array>
    <key>StartCalendarInterval</key><dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
</dict>
</plist>"

log_success "Antivirus set up, quarantine is '$QUARANTINE_DIRECTORY'. 'XProtect' stays on."
