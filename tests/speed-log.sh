#!/bin/bash

# Checks the `audit-home-network` speed log: a measured row lands in the CSV
# with no address, a failed measurement is logged as failed and breaks the
# streak, the streak fires only after three measured rows below half the
# contracted download, and a bad contracted speed is rejected.
# `networkQuality`, `system_profiler` and `osascript` are stubbed.

set -e

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SPEED_LOG_SCRIPT="$TESTS_SCRIPT_DIRECTORY/../.config/agentic/skills/audit-home-network/scripts/speed-log.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

mkdir -p "$TEST_DIRECTORY/bin"
cat >"$TEST_DIRECTORY/bin/networkQuality" <<'STUB'
#!/bin/bash
[ -f "$SPEED_STUB_FAIL" ] && exit 1
echo "{\"dl_throughput\": $SPEED_STUB_DOWNLOAD, \"ul_throughput\": 20000000, \"base_rtt\": 12.7, \"interface_name\": \"en0\", \"other\": {\"interface-type\": {\"wifi\": 2}}}"
STUB
cat >"$TEST_DIRECTORY/bin/system_profiler" <<'STUB'
#!/bin/bash
echo "          Current Network Information:"
echo "              Transmit Rate: 780"
STUB
cat >"$TEST_DIRECTORY/bin/osascript" <<'STUB'
#!/bin/bash
echo notified >>"$SPEED_STUB_NOTIFIED"
STUB
chmod +x "$TEST_DIRECTORY/bin/"*

export PATH="$TEST_DIRECTORY/bin:$PATH"
export SPEED_STUB_FAIL="$TEST_DIRECTORY/fail"
export SPEED_STUB_NOTIFIED="$TEST_DIRECTORY/notified"
CSV_FILE="$TEST_DIRECTORY/log/speed.csv"

run() {
  bash "$SPEED_LOG_SCRIPT" "$CSV_FILE" 500 50
}

SPEED_STUB_DOWNLOAD=450000000 run >/dev/null
row=$(tail -n 1 "$CSV_FILE")
[[ "$row" == *",450,20,12,500,50,90,wifi,780,measured" ]] || fail "measured row is wrong: $row"
[[ "$row" != *"en0"* ]] || fail "row holds the interface name"

touch "$SPEED_STUB_FAIL"
SPEED_STUB_DOWNLOAD=0 run >/dev/null
rm "$SPEED_STUB_FAIL"
[[ "$(tail -n 1 "$CSV_FILE")" == *",failed" ]] || fail "failed measurement was not logged as failed"

export SPEED_STUB_DOWNLOAD=100000000
run >/dev/null
run >/dev/null
[ ! -f "$SPEED_STUB_NOTIFIED" ] || fail "streak fired after two slow weeks behind a failed one"
[ "$(run)" = "streak" ] || fail "streak did not fire after three slow weeks"
[ -f "$SPEED_STUB_NOTIFIED" ] || fail "streak posted no notification"

[ "$(head -n 1 "$CSV_FILE" | cut -d, -f1)" = "date" ] || fail "header missing"
[ "$(grep -c '^date,' "$CSV_FILE")" -eq 1 ] || fail "header written more than once"

# A negative speed passes the arithmetic, so only the validation can reject it.
rows_before=$(wc -l <"$CSV_FILE")
if bash "$SPEED_LOG_SCRIPT" "$CSV_FILE" -5 50 2>/dev/null; then
  fail "a negative contracted speed was accepted"
fi
[ "$(wc -l <"$CSV_FILE")" -eq "$rows_before" ] || fail "a rejected run still wrote a row"

chmod 444 "$CSV_FILE"
if SPEED_STUB_DOWNLOAD=450000000 bash "$SPEED_LOG_SCRIPT" "$CSV_FILE" 500 50 2>/dev/null; then
  fail "a run with a read-only CSV exited as if it logged"
fi
chmod 644 "$CSV_FILE"

if [ "$failures" -gt 0 ]; then
  echo "$failures speed log check(s) failed."
  exit 1
fi
echo "Speed log checks passed."
