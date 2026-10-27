#!/bin/bash

# Checks the `setup/agentic.sh` steps in `helpers/agentic.sh`: personal skills
# are removed with their command whatever the line ending, other skills and a
# path outside `skills/` are kept, and the `opencode.json` template gets every
# agent model from `models.txt`, also when its formatting changes. Runs against a
# temporary directory, never the installed configuration.

set -e

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_DIRECTORY="$TESTS_SCRIPT_DIRECTORY/.."

# shellcheck source=../helpers/logs.sh
source "$REPOSITORY_DIRECTORY/helpers/logs.sh"
# shellcheck source=../helpers/agentic.sh
source "$REPOSITORY_DIRECTORY/helpers/agentic.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

agentic="$TEST_DIRECTORY/agentic"
mkdir -p "$agentic/skills/plain" "$agentic/skills/spaced" "$agentic/skills/windows" "$agentic/skills/kept" "$agentic/commands" "$TEST_DIRECTORY/outside"
touch "$agentic/commands/plain.md" "$agentic/commands/kept.md"
printf '# Comment line\nplain\n  spaced  \nwindows\r\n../outside\n' >"$TEST_DIRECTORY/personal.skills.txt"

remove_personal_skills "$agentic" "$TEST_DIRECTORY/personal.skills.txt" 2>/dev/null

for skill in plain spaced windows; do
  [ ! -e "$agentic/skills/$skill" ] || fail "personal skill '$skill' was not removed"
done
[ ! -e "$agentic/commands/plain.md" ] || fail "command of personal skill 'plain' was not removed"
[ -d "$agentic/skills/kept" ] || fail "skill 'kept', not listed, was removed"
[ -e "$agentic/commands/kept.md" ] || fail "command 'kept', not listed, was removed"
[ -d "$TEST_DIRECTORY/outside" ] || fail "a '../' line removed a directory outside skills/"

agents="$TEST_DIRECTORY/agents"
mkdir -p "$agents"
touch "$agents/leader.md" "$agents/reviewer.md" "$agents/unlisted.md"
cat >"$TEST_DIRECTORY/models.txt" <<'MODELS'
opencode:leader:model:provider/leader-model
opencode:leader:variant:high
opencode:reviewer:model:provider/reviewer-model
opencode:reviewer:variant:-
opencode:unlisted:model:provider/unlisted-model
opencode:explore:model:provider/explore-model
MODELS

# The real template, then the same content on one line, the injection must not
# depend on how the template is formatted.
for template in pretty compact; do
  configuration="$TEST_DIRECTORY/opencode-$template.json"
  if [ "$template" = pretty ]; then
    cp "$REPOSITORY_DIRECTORY/.config/opencode/opencode.json" "$configuration"
  else
    jq -c . "$REPOSITORY_DIRECTORY/.config/opencode/opencode.json" >"$configuration"
  fi

  # A separate `bash -e`, like `setup/agentic.sh`, an `if` here would turn `set -e` off inside the function.
  if ! bash -ec 'source "$1/helpers/logs.sh"; source "$1/helpers/agentic.sh"; inject_opencode_agent_models "$2" "$3" "$4"' _ "$REPOSITORY_DIRECTORY" "$configuration" "$TEST_DIRECTORY/models.txt" "$agents" 2>/dev/null; then
    fail "injection into the $template template failed"
    continue
  fi

  expected='{"leader":{"mode":"primary","model":"provider/leader-model","variant":"high"},"reviewer":{"mode":"subagent","model":"provider/reviewer-model"},"explore":{"mode":"subagent","model":"provider/explore-model"},"compaction":{"mode":"primary","model":"opencode/big-pickle"}}'
  actual=$(jq -cS '.agent' "$configuration")
  [ "$actual" = "$(jq -cS . <<<"$expected")" ] || fail "$template template got agent block $actual"
  [ "$(jq -r '.default_agent' "$configuration")" = leader ] || fail "$template template lost its other keys"
done

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: agentic"
