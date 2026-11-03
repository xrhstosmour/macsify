#!/bin/bash

# Checks `.config/scripts/arrange_displays.sh`: the compiled placer runs only when no
# external keyboard is connected, and not at all when it is not compiled yet. The
# placer's own geometry is `CoreGraphics` and is checked by hand on a real setup.
# `ioreg` and the placer are stubs, `HOME` is a temporary directory.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/arrange_displays.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

export HOME="$TEST_DIRECTORY/home"
mkdir -p "$HOME/.config/scripts" "$TEST_DIRECTORY/bin"
export PATH="$TEST_DIRECTORY/bin:$PATH"
export CALLS="$TEST_DIRECTORY/calls"
failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# `ioreg` prints one HID keyboard of the transport in `$KEYBOARD_TRANSPORT`.
cat >"$TEST_DIRECTORY/bin/ioreg" <<'STUB'
#!/bin/bash
printf '+-o Keyboard  <class IOHIDDevice>\n  {\n    "Transport" = "%s"\n    "PrimaryUsagePage" = 1\n    "PrimaryUsage" = 6\n  }\n' "$KEYBOARD_TRANSPORT"
STUB
chmod +x "$TEST_DIRECTORY/bin/ioreg"

run() {
  : >"$CALLS"
  bash "$SCRIPT"
}

# Not compiled yet, nothing happens and nothing fails.
KEYBOARD_TRANSPORT="FIFO" run || fail "failed without the compiled placer"

printf '#!/bin/bash\necho placed >>"$CALLS"\n' >"$HOME/.config/scripts/arrange_displays"
chmod +x "$HOME/.config/scripts/arrange_displays"

KEYBOARD_TRANSPORT="FIFO" run
grep -q placed "$CALLS" || fail "the placer did not run with only the built-in keyboard"

KEYBOARD_TRANSPORT="USB" run
[ ! -s "$CALLS" ] || fail "the placer ran with a USB keyboard connected"

KEYBOARD_TRANSPORT="Bluetooth" run
[ ! -s "$CALLS" ] || fail "the placer ran with a Bluetooth keyboard connected"

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: Arrange displays"
