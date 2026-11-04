#!/bin/bash

# Checks `.config/fish/conf.d/herdr-agent-resume.fish`: the terminal's own shell
# resumes the recorded agent in the recorded folder with its flags and keeps the
# record until the agent returns, a shell that is not the terminal's own and a
# record naming a flag as session resume nothing, and an agent typed by hand and
# ended forgets its record while other commands do not. `hc`, `claude` and
# `opencode` are stubs, the first keeps the label in a file, the others print the
# arguments they got and whether the record was still there. Needs `fish`.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY="$TESTS_SCRIPT_DIRECTORY/.."

if ! command -v fish >/dev/null 2>&1; then
  echo "SKIP: fish not found"
  exit 0
fi

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

mkdir -p "$TEST_DIRECTORY/bin" "$TEST_DIRECTORY/work" "$TEST_DIRECTORY/home/.config/agentic/hooks"
cp "$REPOSITORY/.config/agentic/hooks/herdr-application-resume.sh" "$TEST_DIRECTORY/home/.config/agentic/hooks/"

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
    jq -nc --arg record "$record" --argjson pid "${HC_STUB_PID:-0}" \
      '{pid: $pid, foreground: {argv: ["claude"]}, labels: (if $record == "" then {} else {"resume.record": $record} end)}'
    ;;
esac
STUB
for agent in claude opencode; do
  cat >"$TEST_DIRECTORY/bin/$agent" <<STUB
#!/bin/bash
echo "$agent \$* in \$PWD, record \$([ -f "\$HC_STUB_DIRECTORY/label" ] && echo kept || echo gone)" >>"\$HC_STUB_DIRECTORY/calls"
STUB
done
chmod +x "$TEST_DIRECTORY"/bin/*

export HC_STUB_DIRECTORY="$TEST_DIRECTORY"
failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# Starts an interactive `fish` with the config file sourced, the shell's own pid
# is the one `hc` reports unless `own` is "no", then runs the fish command given.
shell() {
  own="$1"
  HOME="$TEST_DIRECTORY/home" PATH="$TEST_DIRECTORY/bin:$PATH" HC_TERMINAL_ID=t1f \
    fish -N -i -C "set -gx HC_STUB_PID (test $own = yes; and echo \$fish_pid; or echo 1); source $REPOSITORY/.config/fish/conf.d/herdr-agent-resume.fish" -c "$2" >/dev/null 2>&1
}

save() {
  printf '%s' "$1" >"$TEST_DIRECTORY/label"
  : >"$TEST_DIRECTORY/calls"
}

record='{"agent":"claude","session":"abc-123","folder":"'"$TEST_DIRECTORY"'/work","flags":["--permission-mode","plan"]}'

save "$record"
shell yes 'emit fish_prompt'
[ "$(cat "$TEST_DIRECTORY/calls")" = "claude --resume abc-123 --permission-mode plan in $TEST_DIRECTORY/work, record kept" ] || fail "the own shell did not resume with folder and flags, or dropped the record early: $(cat "$TEST_DIRECTORY/calls")"
[ ! -f "$TEST_DIRECTORY/label" ] || fail "the record stayed after the agent returned"

save '{"agent":"opencode","session":"ses_1","folder":"'"$TEST_DIRECTORY"'/work","flags":[]}'
shell yes 'emit fish_prompt'
grep -q '^opencode --session ses_1 in ' "$TEST_DIRECTORY/calls" || fail "opencode was not resumed with --session"

save "$record"
shell no 'emit fish_prompt'
[ ! -s "$TEST_DIRECTORY/calls" ] && [ -f "$TEST_DIRECTORY/label" ] || fail "a shell that is not the terminal's own resumed or dropped the record"

save '{"agent":"claude","session":"--dangerously-skip-permissions","folder":"'"$TEST_DIRECTORY"'/work"}'
shell yes 'emit fish_prompt'
[ ! -s "$TEST_DIRECTORY/calls" ] || fail "a flag as session ID was run"

save "$record"
shell yes 'emit fish_postexec "ls -l"'
[ -f "$TEST_DIRECTORY/label" ] || fail "an unrelated command forgot the record"
shell yes 'emit fish_postexec "claude --model opus"'
[ ! -f "$TEST_DIRECTORY/label" ] || fail "a typed agent that returned kept the record"

[ "$failures" = "0" ] && echo "herdr-agent-resume-fish: all checks passed"
exit "$failures"
