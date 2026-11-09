#!/bin/bash

# Checks the `setup/agentic.sh` steps in `helpers/agentic.sh`: personal skills
# are removed with their command whatever the line ending, other skills and a
# path outside `skills/` are kept, a review script gone from the repository is
# removed from the installed copy, the old watcher cache is moved once and never
# over the new one, and the `opencode.json` template gets every
# agent model from `models.txt`, also when its formatting changes, and a plugin
# enabled by setup keeps the committed ones. Runs against a
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

remove_listed_skills "$agentic" "$TEST_DIRECTORY/personal.skills.txt" 2>/dev/null

for skill in plain spaced windows; do
  [ ! -e "$agentic/skills/$skill" ] || fail "personal skill '$skill' was not removed"
done
[ ! -e "$agentic/commands/plain.md" ] || fail "command of personal skill 'plain' was not removed"
[ -d "$agentic/skills/kept" ] || fail "skill 'kept', not listed, was removed"
[ -e "$agentic/commands/kept.md" ] || fail "command 'kept', not listed, was removed"
[ -d "$TEST_DIRECTORY/outside" ] || fail "a '../' line removed a directory outside skills/"

source_scripts="$TEST_DIRECTORY/source-scripts"
installed_scripts="$TEST_DIRECTORY/installed-scripts"
mkdir -p "$source_scripts" "$installed_scripts"
touch "$source_scripts/kept.sh" "$installed_scripts/kept.sh" "$installed_scripts/renamed.sh" "$installed_scripts/notes.txt"
remove_stale_scripts "$source_scripts" "$installed_scripts"
[ -e "$installed_scripts/kept.sh" ] || fail "a script still in the source was removed"
[ ! -e "$installed_scripts/renamed.sh" ] || fail "a script gone from the source was kept"
[ -e "$installed_scripts/notes.txt" ] || fail "a file that is not a script was removed"
remove_stale_scripts "$source_scripts" "$TEST_DIRECTORY/no-scripts" || fail "an empty installed directory failed"

cache="$TEST_DIRECTORY/cache"
mkdir -p "$cache/resolve-github-prs-comments-watcher"
echo "1 owner/repo#5+1" >"$cache/resolve-github-prs-comments-watcher/claimed"
move_green_watcher_cache "$cache"
[ "$(cat "$cache/green-github-prs-watcher/claimed" 2>/dev/null)" = "1 owner/repo#5+1" ] || fail "the old watcher cache was not moved"
[ ! -e "$cache/resolve-github-prs-comments-watcher" ] || fail "the old watcher cache was left behind"
mkdir -p "$cache/resolve-github-prs-comments-watcher"
echo "2 owner/repo#5+2" >"$cache/resolve-github-prs-comments-watcher/claimed"
move_green_watcher_cache "$cache"
[ "$(cat "$cache/green-github-prs-watcher/claimed")" = "1 owner/repo#5+1" ] || fail "the old watcher cache overwrote the new one"

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

# Machine specific `Claude Code` settings survive the copy of the committed file, whose own keys win.
installed="$TEST_DIRECTORY/installed-settings.json"
printf '{"autoMode":{"trusted":["repo"]},"skipDangerousModePermissionPrompt":true,"model":"old","other":1}\n' >"$installed"
preserved=$(preserved_claude_settings "$installed")
[ "$(jq -cS . <<<"$preserved")" = '{"autoMode":{"trusted":["repo"]},"model":"old","skipDangerousModePermissionPrompt":true}' ] || fail "preserved settings were $preserved"
printf '{"model":"new","permissions":{}}\n' >"$installed"
restore_claude_settings "$installed" "$preserved" 2>/dev/null
[ "$(jq -cS . "$installed")" = '{"autoMode":{"trusted":["repo"]},"model":"old","permissions":{},"skipDangerousModePermissionPrompt":true}' ] || fail "restored settings were $(jq -c . "$installed")"
[ "$(preserved_claude_settings "$TEST_DIRECTORY/missing.json")" = "{}" ] || fail "a missing settings file preserved something"
printf 'not json' >"$installed"
[ "$(preserved_claude_settings "$installed")" = "{}" ] || fail "a broken settings file preserved something"
printf '{"model":"new"}\n' >"$installed"
restore_claude_settings "$installed" "{}"
[ "$(jq -c . "$installed")" = '{"model":"new"}' ] || fail "an empty preserved object changed the settings"

# A plugin enabled by setup keeps the committed plugins, and a broken settings file stays as it was.
printf '{"enabledPlugins":{"swift-lsp@claude-plugins-official":true},"model":"new"}\n' >"$installed"
enable_claude_plugin "$installed" "xcode@claude-plugins-official"
[ "$(jq -cS . "$installed")" = '{"enabledPlugins":{"swift-lsp@claude-plugins-official":true,"xcode@claude-plugins-official":true},"model":"new"}' ] || fail "enabled plugin settings were $(jq -c . "$installed")"
printf 'not json' >"$installed"
enable_claude_plugin "$installed" "xcode@claude-plugins-official" 2>/dev/null
[ "$(cat "$installed")" = "not json" ] || fail "a broken settings file was changed when enabling a plugin"

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: agentic"
