#!/bin/bash

# Checks `.config/scripts/antivirus/scan.sh`: an infected file moves into quarantine with a
# note and without execute bits, a clean file and a file outside the scanned paths
# stay, `--recent` skips old files, and nothing is ever deleted. `clamscan` is
# stubbed to flag any file containing the word EICAR, no engine or signatures needed.

set -e

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCAN_SCRIPT="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/antivirus/scan.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

mkdir -p "$TEST_DIRECTORY/bin" "$TEST_DIRECTORY/watched" "$TEST_DIRECTORY/elsewhere"
cat >"$TEST_DIRECTORY/bin/clamscan" <<'STUB'
#!/bin/bash
file="${@: -1}"
if grep -q EICAR "$file"; then
  echo "$file: Eicar-Test-Signature FOUND"
  exit 1
fi
exit 0
STUB
chmod +x "$TEST_DIRECTORY/bin/clamscan"

export ANTIVIRUS_QUARANTINE_DIRECTORY="$TEST_DIRECTORY/quarantine"
export ANTIVIRUS_LOG_FILE="$TEST_DIRECTORY/scan.log"
export PATH="$TEST_DIRECTORY/bin:$PATH"

echo "EICAR" >"$TEST_DIRECTORY/watched/bad.txt"
chmod +x "$TEST_DIRECTORY/watched/bad.txt"
echo "hello" >"$TEST_DIRECTORY/watched/good.txt"
echo "EICAR" >"$TEST_DIRECTORY/elsewhere/unscanned.txt"

bash "$SCAN_SCRIPT" "$TEST_DIRECTORY/watched"

[ ! -e "$TEST_DIRECTORY/watched/bad.txt" ] || fail "infected file was left in place"
[ -e "$TEST_DIRECTORY/watched/good.txt" ] || fail "clean file was moved"
[ -e "$TEST_DIRECTORY/elsewhere/unscanned.txt" ] || fail "file outside the scanned paths was touched"

quarantined=$(find "$ANTIVIRUS_QUARANTINE_DIRECTORY" -name '*bad.txt' -not -name '*.note')
[ -n "$quarantined" ] || fail "infected file is not in quarantine"
[ ! -x "$quarantined" ] || fail "quarantined file kept its execute bit"
grep -q 'Reason: Eicar-Test-Signature' "$quarantined.note" || fail "note does not say why"
grep -q "Origin: $TEST_DIRECTORY/watched/bad.txt" "$quarantined.note" || fail "note does not say where it came from"
[ "$(stat -c '%a' "$ANTIVIRUS_QUARANTINE_DIRECTORY" 2>/dev/null || stat -f '%Lp' "$ANTIVIRUS_QUARANTINE_DIRECTORY")" = "700" ] || fail "quarantine is not private"

# A rerun finds nothing new and deletes nothing.
bash "$SCAN_SCRIPT" "$TEST_DIRECTORY/watched"
[ -e "$quarantined" ] || fail "rerun removed the quarantined file"

# Dependency and repository folders are not scanned.
mkdir -p "$TEST_DIRECTORY/watched/node_modules/package"
echo "EICAR" >"$TEST_DIRECTORY/watched/node_modules/package/fixture.txt"
bash "$SCAN_SCRIPT" "$TEST_DIRECTORY/watched"
[ -e "$TEST_DIRECTORY/watched/node_modules/package/fixture.txt" ] || fail "a file inside node_modules was scanned"

# `--recent` leaves a file older than the window alone.
echo "EICAR" >"$TEST_DIRECTORY/watched/old.txt"
touch -t 200001010000 "$TEST_DIRECTORY/watched/old.txt"
bash "$SCAN_SCRIPT" --recent "$TEST_DIRECTORY/watched"
[ -e "$TEST_DIRECTORY/watched/old.txt" ] || fail "--recent scanned an old file"

# Startup diff: the first run only saves a baseline, a new item is reported once.
export ANTIVIRUS_DATA_DIRECTORY="$TEST_DIRECTORY/data"
export ANTIVIRUS_STARTUP_DIRECTORIES="$TEST_DIRECTORY/launch"
STARTUP_SCRIPT="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/antivirus/startup-difference.sh"
mkdir -p "$TEST_DIRECTORY/launch"
touch "$TEST_DIRECTORY/launch/known.plist"
: >"$ANTIVIRUS_LOG_FILE"

bash "$STARTUP_SCRIPT"
grep -q CHECK "$ANTIVIRUS_LOG_FILE" && fail "the first run reported items instead of saving a baseline"

touch "$TEST_DIRECTORY/launch/new.plist"
bash "$STARTUP_SCRIPT"
bash "$STARTUP_SCRIPT"
[ "$(grep -c 'CHECK new startup item: .*new.plist' "$ANTIVIRUS_LOG_FILE")" = "1" ] || fail "new startup item was not reported exactly once"

# Report: says what it found and does not repeat it on the next run.
export ANTIVIRUS_REPORT_DIRECTORY="$TEST_DIRECTORY/reports"
REPORT_SCRIPT="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/antivirus/report.sh"
echo "$(date '+%Y-%m-%d %H:%M:%S') QUARANTINED '/x/bad' as '/q/bad', Eicar" >>"$ANTIVIRUS_LOG_FILE"
first=$(bash "$REPORT_SCRIPT")
grep -q '^HIGH:' "$first" || fail "report has no HIGH line for a quarantined file"
grep -q '^CHECK: new startup item' "$first" || fail "report has no CHECK line for the new startup item"
second=$(sleep 1; bash "$REPORT_SCRIPT")
grep -q '^OK:' "$second" || fail "a second report repeated old findings"

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: Antivirus scan, startup diff and report"
