#!/bin/bash

# Checks the `Dock` helpers of `utilities/dock.sh` against temporary property lists,
# never the real `Dock`: which `Dock` counts as Apple's default, and where
# `add_missing_dock_applications` puts the missing applications while it keeps every
# existing item. Needs `PlistBuddy`, so it is skipped off macOS.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOCK_UTILITY="$TESTS_SCRIPT_DIRECTORY/../utilities/dock.sh"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

if [ ! -x "$PLIST_BUDDY" ]; then
  echo "SKIP: Dock helpers, PlistBuddy needs macOS"
  exit 0
fi

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

APPLICATIONS_DIRECTORY="$TEST_DIRECTORY/Applications"
DOCK_PLIST="$TEST_DIRECTORY/dock.plist"
DOCK_READ_OUTPUT="$TEST_DIRECTORY/dock-read.txt"
mkdir -p "$APPLICATIONS_DIRECTORY/A.app" "$APPLICATIONS_DIRECTORY/B.app" "$APPLICATIONS_DIRECTORY/C.app" "$APPLICATIONS_DIRECTORY/Café & Co.app"
failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# Stands in for `defaults`, `export` and `import` copy the temporary property list,
# `read` prints the prepared output or fails when there is none.
defaults() {
  case "$1" in
    export) cp "$DOCK_PLIST" "$3" ;;
    import) cp "$3" "$DOCK_PLIST" ;;
    read) [ -f "$DOCK_READ_OUTPUT" ] && cat "$DOCK_READ_OUTPUT" ;;
  esac
}

# shellcheck disable=SC1090
source "$DOCK_UTILITY"
set +e

# Starts a `Dock` with the given `_CFURLString` values, an empty one is a spacer.
new_dock() {
  local index=0 url
  rm -f "$DOCK_PLIST"
  "$PLIST_BUDDY" -c "Add :persistent-apps array" "$DOCK_PLIST" >/dev/null
  for url in "$@"; do
    "$PLIST_BUDDY" -c "Add :persistent-apps:${index} dict" "$DOCK_PLIST"
    if [ -z "$url" ]; then
      "$PLIST_BUDDY" -c "Add :persistent-apps:${index}:tile-type string spacer-tile" "$DOCK_PLIST"
    else
      "$PLIST_BUDDY" \
        -c "Add :persistent-apps:${index}:tile-data dict" \
        -c "Add :persistent-apps:${index}:tile-data:file-data dict" \
        -c "Add :persistent-apps:${index}:tile-data:file-data:_CFURLString string ${url}" \
        "$DOCK_PLIST"
    fi
    index=$((index + 1))
  done
}

# Prints the `Dock` as one line, application names in order and `_` for a spacer.
dock_order() {
  local index=0 url order=""
  while "$PLIST_BUDDY" -c "Print :persistent-apps:${index}" "$DOCK_PLIST" &>/dev/null; do
    url=$("$PLIST_BUDDY" -c "Print :persistent-apps:${index}:tile-data:file-data:_CFURLString" "$DOCK_PLIST" 2>/dev/null) || url="_"
    url="${url%/}"
    url="${url##*/}"
    order="$order ${url%.app}"
    index=$((index + 1))
  done
  echo "${order# }"
}

add_test_applications() {
  add_missing_dock_applications "$APPLICATIONS_DIRECTORY/A.app" "$APPLICATIONS_DIRECTORY/B.app" "$APPLICATIONS_DIRECTORY/C.app" "/Applications/Missing.app" "$APPLICATIONS_DIRECTORY/Café & Co.app" >/dev/null 2>&1
}

# A `Dock` of Apple's applications only, or with none saved, is the default.
printf '%s\n' '"bundle-identifier" = "com.apple.Safari";' '"_CFURLString" = "file:///Applications/Safari.app/";' >"$DOCK_READ_OUTPUT"
dock_is_default || fail "a Dock of Apple applications only was not the default"
printf '%s\n' '"bundle-identifier" = "com.apple.Safari";' '"_CFURLString" = "file:///Applications/Safari.app/";' '"bundle-identifier" = "com.google.Chrome";' '"_CFURLString" = "file:///Applications/Google%20Chrome.app/";' >"$DOCK_READ_OUTPUT"
! dock_is_default || fail "a Dock with a third party application was the default"
rm -f "$DOCK_READ_OUTPUT"
dock_is_default || fail "a Dock with no saved applications was not the default"

# Existing items, a spacer and a foreign application stay, the missing ones go next to
# their neighbours, the uninstalled one is left out.
new_dock "file://$APPLICATIONS_DIRECTORY/B.app/" "" "file:///Applications/Company%20VPN.app/"
add_test_applications
[ "$(dock_order)" = "A B C Café & Co _ Company%20VPN" ] || fail "missing applications were not placed next to their neighbours, got '$(dock_order)'"

# A rerun finds every application, also the percent encoded one, and adds nothing.
new_dock "file://$APPLICATIONS_DIRECTORY/A.app/" "file://$APPLICATIONS_DIRECTORY/B.app/" "file://$APPLICATIONS_DIRECTORY/C.app/" "file://$APPLICATIONS_DIRECTORY/Caf%C3%A9%20%26%20Co.app/"
add_test_applications
[ "$(dock_order)" = "A B C Caf%C3%A9%20%26%20Co" ] || fail "a rerun changed a Dock that had every application, got '$(dock_order)'"

# An empty `Dock` gets the whole list in order.
new_dock
add_test_applications
[ "$(dock_order)" = "A B C Café & Co" ] || fail "an empty Dock did not get the list in order, got '$(dock_order)'"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "PASS: Dock helpers"
