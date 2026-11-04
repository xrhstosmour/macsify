#!/bin/bash

# Checks `.config/agentic/hooks/herdr-application-resume.sh`: outside an app
# terminal it records nothing, a session is saved and read back only by the
# terminal's own shell, a session ID that is not plain is refused, only the
# listed flags are kept, and forget or a `SessionEnd` that is the person leaving
# removes the record. `hc` is a stub that keeps the label in a file and answers
# with a fixed shell pid and the foreground command in `HC_STUB_ARGV`.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK="$TESTS_SCRIPT_DIRECTORY/../.config/agentic/hooks/herdr-application-resume.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

mkdir -p "$TEST_DIRECTORY/bin" "$TEST_DIRECTORY/work"
cat >"$TEST_DIRECTORY/bin/hc" <<'STUB'
#!/bin/bash
label="$HC_STUB_DIRECTORY/label"
case "$1" in
  label)
    value="${3#resume.record=}"
    if [ -n "$value" ]; then printf '%s' "$value" >"$label"; else rm -f "$label"; fi
    ;;
  get)
    record=""
    [ -f "$label" ] && record=$(cat "$label")
    jq -nc --arg record "$record" --argjson argv "${HC_STUB_ARGV:-[\"claude\"]}" \
      '{pid: 4242, foreground: {argv: $argv}, labels: ({where: "x"} + (if $record == "" then {} else {"resume.record": $record} end))}'
    ;;
esac
STUB
chmod +x "$TEST_DIRECTORY/bin/hc"
export PATH="$TEST_DIRECTORY/bin:$PATH"
export HC_STUB_DIRECTORY="$TEST_DIRECTORY"
failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

recorded() {
  [ -f "$TEST_DIRECTORY/label" ] && echo yes || echo no
}

unset HC_TERMINAL_ID
printf '{"session_id":"abc","cwd":"%s"}' "$TEST_DIRECTORY/work" | bash "$HOOK" save claude
[ "$(recorded)" = "no" ] || fail "recorded outside an app terminal"

export HC_TERMINAL_ID="t1f"
printf '{"session_id":"abc-123","cwd":"%s"}' "$TEST_DIRECTORY/work" | bash "$HOOK" save claude
[ "$(recorded)" = "yes" ] || fail "claude session was not recorded"
[ "$(bash "$HOOK" show 4242)" = "$(printf 'claude\tabc-123\t%s' "$TEST_DIRECTORY/work")" ] || fail "the terminal's own shell did not get the session"
[ -z "$(bash "$HOOK" show 9999)" ] || fail "a shell that is not the terminal's own got the session"

bash "$HOOK" save opencode ses_abc123 "$TEST_DIRECTORY/work"
[ "$(bash "$HOOK" show 4242)" = "$(printf 'opencode\tses_abc123\t%s' "$TEST_DIRECTORY/work")" ] || fail "opencode session did not replace the claude one"

# Allowlisted flags come back, secrets, the first prompt and resume flags do not.
HC_STUB_ARGV='["claude","--permission-mode","plan","--model","opus","--dangerously-skip-permissions","--api-key","secret","--resume","old","write code"]' \
  bash "$HOOK" save opencode ses_flags "$TEST_DIRECTORY/work"
[ "$(bash "$HOOK" show 4242)" = "$(printf 'opencode\tses_flags\t%s\t--permission-mode\tplan\t--model\topus\t--dangerously-skip-permissions' "$TEST_DIRECTORY/work")" ] || fail "flags were not kept as listed"
HC_STUB_ARGV='["claude","--model","--resume"]' bash "$HOOK" save opencode ses_value "$TEST_DIRECTORY/work"
[ "$(bash "$HOOK" show 4242)" = "$(printf 'opencode\tses_value\t%s' "$TEST_DIRECTORY/work")" ] || fail "a flag followed by another flag kept a value"

bash "$HOOK" forget
[ "$(recorded)" = "no" ] || fail "forget left the record"
[ -z "$(bash "$HOOK" show 4242)" ] || fail "a forgotten session was shown"

# Only the person leaving ends the record, a clear or a reboot keeps it.
printf '{"session_id":"abc","cwd":"%s"}' "$TEST_DIRECTORY/work" | bash "$HOOK" save claude
for reason in clear other resume; do
  printf '{"reason":"%s"}' "$reason" | bash "$HOOK" end
  [ "$(recorded)" = "yes" ] || fail "a session end with reason '$reason' forgot the record"
done
printf 'not json' | bash "$HOOK" end
[ "$(recorded)" = "yes" ] || fail "a broken payload forgot the record"
for reason in prompt_input_exit logout; do
  printf '{"session_id":"abc","cwd":"%s"}' "$TEST_DIRECTORY/work" | bash "$HOOK" save claude
  printf '{"reason":"%s"}' "$reason" | bash "$HOOK" end
  [ "$(recorded)" = "no" ] || fail "a session end with reason '$reason' kept the record"
done

# Each of these must record nothing.
refused() {
  [ "$(recorded)" = "no" ] || fail "$1 was recorded"
  bash "$HOOK" forget
}

printf '{"session_id":"a b;rm","cwd":"%s"}' "$TEST_DIRECTORY/work" | bash "$HOOK" save claude
refused "an ID with a space and a semicolon"
(cd "$TEST_DIRECTORY" && bash "$HOOK" save opencode '$(touch pwned)' "$TEST_DIRECTORY/work")
refused "a command substitution as ID"
[ ! -e "$TEST_DIRECTORY/pwned" ] || fail "a command substitution in the ID ran"
bash "$HOOK" save opencode '--dangerously-skip-permissions' "$TEST_DIRECTORY/work"
refused "an ID that is a flag"
mkdir -p "$TEST_DIRECTORY/work	--model"
bash "$HOOK" save opencode ses_tab "$TEST_DIRECTORY/work	--model"
refused "a folder with a tab"
printf '{"session_id":"abc","cwd":"/does/not/exist"}' | bash "$HOOK" save claude
refused "a missing folder"
printf 'not json' | bash "$HOOK" save claude
refused "a broken payload"

# A record written by something else is checked again when read.
for record in \
  '{"agent":"claude","session":"-x","folder":"/tmp"}' \
  '{"agent":"claude","session":"ok","folder":"/tmp\t--model"}' \
  '{"agent":"bash","session":"ok","folder":"/tmp"}' \
  'not json'; do
  printf '%s' "$record" >"$TEST_DIRECTORY/label"
  [ -z "$(bash "$HOOK" show 4242)" ] || fail "a bad record was shown: $record"
done

[ "$failures" = "0" ] && echo "herdr-application-resume: all checks passed"
exit "$failures"
