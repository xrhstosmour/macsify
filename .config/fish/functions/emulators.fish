# Function to disable audio for all existing `Android` emulators.
# Usage:
#   disable_android_emulators_audio
function disable_android_emulators_audio
    for line in (find ~/.android/avd -name "config.ini")
        grep -v "^audio" "$line" > /tmp/android_config_tmp
        and mv /tmp/android_config_tmp "$line"
        and echo "hw.audioInput = no" >> "$line"
        and echo "hw.audioOutput = no" >> "$line"
    end
end

# Function to launch the `Android` emulator created by `setup/mobile.sh`.
# Usage:
#   open_android_emulator
function open_android_emulator
    # The same `AVD` cannot run twice, `Flutter` errors out instead of focusing
    # the window that is already open.
    if not pgrep -qf "qemu-system.* -avd pixel_10_pro"
        flutter emulators --launch pixel_10_pro
    end
end

# Function to boot the iOS simulator created by `setup/mobile.sh` and bring its
# window to the front.
# Usage:
#   open_ios_emulator
function open_ios_emulator
    # Booting an already booted device is an error worth ignoring.
    xcrun simctl boot "iPhone 18 Pro" 2>/dev/null

    # `Xcode` 27 dropped `Simulator.app`, `DeviceHub` hosts the simulator window
    # in its place. Opened by bundle identifier so the `Xcode` location does not
    # matter.
    open -b com.apple.dt.Devices
end
