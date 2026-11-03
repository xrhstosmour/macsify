#!/bin/bash

# Checks `helpers/syncthing.sh`: the API key and GUI URL are read out of
# `config.xml` (the scheme follows `tls`, the host is always loopback), and the
# hardening sends the exact options and GUI payloads with the key in a header and
# the body on standard input. `curl` is stubbed, nothing reaches a real `Syncthing`.

set -e

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_DIRECTORY="$TESTS_SCRIPT_DIRECTORY/.."

# shellcheck source=../helpers/syncthing.sh
source "$REPOSITORY_DIRECTORY/helpers/syncthing.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

cat >"$TEST_DIRECTORY/config.xml" <<'CONFIGURATION'
<configuration version="37">
    <device id="X" name="phone">
        <address>dynamic</address>
    </device>
    <gui enabled="true" tls="false" debugging="false">
        <address>0.0.0.0:8999</address>
        <apikey>test-key</apikey>
    </gui>
</configuration>
CONFIGURATION

[ "$(syncthing_api_key "$TEST_DIRECTORY/config.xml")" = "test-key" ] || fail "API key was not read"
[ "$(syncthing_gui_url "$TEST_DIRECTORY/config.xml")" = "http://127.0.0.1:8999" ] || fail "a GUI on every interface was not reduced to loopback with its port"

sed 's/tls="false"/tls="true"/' "$TEST_DIRECTORY/config.xml" >"$TEST_DIRECTORY/tls.xml"
[ "$(syncthing_gui_url "$TEST_DIRECTORY/tls.xml")" = "https://127.0.0.1:8999" ] || fail "tls=true did not give an https URL"

# Stub `curl`, recording the URL, the header file content and the body.
mkdir -p "$TEST_DIRECTORY/bin"
cat >"$TEST_DIRECTORY/bin/curl" <<'STUB'
#!/bin/bash
header_file=""
for argument in "$@"; do
  [[ "$argument" == @/dev/fd/* ]] && header_file="${argument#@}"
done
{
  echo "ARGUMENTS: $*"
  [ -n "$header_file" ] && echo "HEADER: $(cat "$header_file")"
  echo "BODY: $(cat)"
} >>"$CURL_LOG"
STUB
chmod +x "$TEST_DIRECTORY/bin/curl"

export CURL_LOG="$TEST_DIRECTORY/curl.log"
: >"$CURL_LOG"
PATH="$TEST_DIRECTORY/bin:$PATH" harden_syncthing "https://127.0.0.1:8999" "test-key" >/dev/null 2>&1

grep -q 'rest/config/options' "$CURL_LOG" || fail "options were not patched"
grep -q 'rest/config/gui' "$CURL_LOG" || fail "GUI settings were not patched"
grep -q '"globalAnnounceEnabled":false' "$CURL_LOG" || fail "global discovery was not turned off"
grep -q '"relaysEnabled":false' "$CURL_LOG" || fail "relays were not turned off"
grep -q '"natEnabled":false' "$CURL_LOG" || fail "NAT traversal was not turned off"
grep -q '"urAccepted":-1' "$CURL_LOG" || fail "usage reporting was not declined"
grep -q '"address":"127.0.0.1:8999"' "$CURL_LOG" || fail "GUI was not bound to loopback on its own port"
grep -q '"useTLS":true' "$CURL_LOG" || fail "GUI was not switched to https"
grep -q 'HEADER: X-API-Key: test-key' "$CURL_LOG" || fail "key was not sent in a header"
grep -- 'ARGUMENTS' "$CURL_LOG" | grep -q 'test-key' && fail "key leaked into the curl arguments"

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: Syncthing helpers"
