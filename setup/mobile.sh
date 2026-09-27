#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
MOBILE_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import functions and flags.
source "$MOBILE_SCRIPT_DIRECTORY/../helpers/logs.sh"

# Directories the `android-commandlinetools` and `flutter` casks install into.
HOMEBREW_PREFIX_DIRECTORY=$(brew --prefix)
export ANDROID_HOME="$HOMEBREW_PREFIX_DIRECTORY/share/android-commandlinetools"
FLUTTER_ROOT_DIRECTORY="$HOMEBREW_PREFIX_DIRECTORY/share/flutter"

# Devices to create, kept in step with `.config/fish/functions/emulators.fish`.
ANDROID_EMULATOR_DEVICE="pixel_10_pro"
IOS_SIMULATOR_DEVICE="iPhone 18 Pro"

if [ ! -d "$FLUTTER_ROOT_DIRECTORY" ]; then
  log_warning "'Flutter' not found at '$FLUTTER_ROOT_DIRECTORY', skipping the mobile development toolchain."
  exit 0
fi

# Read the versions out of `Flutter`, so an upgrade does not leave the SDK behind.
FLUTTER_EXTENSION="$FLUTTER_ROOT_DIRECTORY/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt"
COMPILE_SDK_VERSION=$(grep -oE 'compileSdkVersion: Int = [0-9]+' "$FLUTTER_EXTENSION" | grep -oE '[0-9]+')
NDK_VERSION=$(grep -oE 'ndkVersion: String = "[^"]+"' "$FLUTTER_EXTENSION" | grep -oE '[0-9.]+')

if [ -z "$COMPILE_SDK_VERSION" ] || [ -z "$NDK_VERSION" ]; then
  log_error "Could not read the compile SDK and NDK versions from '$FLUTTER_EXTENSION'."
  exit 1
fi

ANDROID_EMULATOR_IMAGE="system-images;android-$COMPILE_SDK_VERSION;google_apis_playstore;arm64-v8a"

# `android sdk install` also accepts each licence, which the Gradle build needs on disk.
log_info "Installing the Android SDK packages for API $COMPILE_SDK_VERSION..."
android sdk install \
  "platform-tools" \
  "platforms;android-$COMPILE_SDK_VERSION" \
  "build-tools;$COMPILE_SDK_VERSION.0.0" \
  "ndk;$NDK_VERSION" \
  "emulator" \
  "$ANDROID_EMULATOR_IMAGE"
log_divider

# `avdmanager` owns this, the `android` CLI cannot name an `AVD` or take a device profile.
if avdmanager list avd --compact 2>/dev/null | grep -qx "$ANDROID_EMULATOR_DEVICE"; then
  log_warning "'$ANDROID_EMULATOR_DEVICE' emulator already exists."
else
  log_info "Creating the '$ANDROID_EMULATOR_DEVICE' Android emulator..."

  # `avdmanager` looks for a `devices.xml` that is not there, that error is noise.
  avdmanager create avd \
    --name "$ANDROID_EMULATOR_DEVICE" \
    --package "$ANDROID_EMULATOR_IMAGE" \
    --device "$ANDROID_EMULATOR_DEVICE" \
    2> >(grep -v 'devices.xml' >&2)
fi
log_divider

if [ -d /Applications/Xcode.app ]; then

  # The bare command line tools carry no iOS `SDK`.
  if [ "$(xcode-select -p)" != "/Applications/Xcode.app/Contents/Developer" ]; then
    log_info "Selecting 'Xcode' as the active developer directory..."
    sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
  fi

  if ! xcodebuild -checkFirstLaunchStatus &>/dev/null; then
    log_info "Accepting the 'Xcode' licence and running its first launch tasks..."
    sudo xcodebuild -license accept
    sudo xcodebuild -runFirstLaunch
  fi

  # The iOS simulator runtime ships separately from `Xcode` itself.
  if ! xcrun simctl list runtimes | grep -q '^iOS'; then
    log_info "Downloading the iOS platform, this takes a while..."
    xcodebuild -downloadPlatform iOS
  fi

  if xcrun simctl list devices available | grep -q "$IOS_SIMULATOR_DEVICE ("; then
    log_warning "'$IOS_SIMULATOR_DEVICE' simulator already exists."
  else
    log_info "Creating the '$IOS_SIMULATOR_DEVICE' simulator..."
    xcrun simctl create "$IOS_SIMULATOR_DEVICE" "$IOS_SIMULATOR_DEVICE"

    # Match the system's dark appearance, which needs the device running once.
    xcrun simctl bootstatus "$IOS_SIMULATOR_DEVICE" -b >/dev/null
    xcrun simctl ui "$IOS_SIMULATOR_DEVICE" appearance dark
    xcrun simctl shutdown "$IOS_SIMULATOR_DEVICE"
  fi
else
  log_warning "'Xcode' is not installed, skipping the iOS toolchain. Install it from the 'Mac App Store' and re-run this script."
fi
log_divider

# `flutter doctor` exits non-zero on any unmet category, which must not abort the rest.
log_info "Verifying the toolchain..."
flutter doctor || true
log_divider
