#!/bin/bash

# Checks the `setup/agentic.sh` steps in `helpers/agentic.sh`: personal skills
# are removed with their command whatever the line ending, other skills and a
# path outside `skills/` are kept, a review script gone from the repository is
# removed from the installed copy, the old watcher cache is moved once and never
# over the new one, and the `opencode.json` template gets every
# agent model from `models.txt`, also when its formatting changes, a plugin
# enabled by setup keeps the committed ones, only a committed plugin not
# installed yet is installed, and the committed MCP read tools are allowed only
# under a server whose `url` has their public host or a host of the trusted
# hosts file. Runs against a
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

# The machine settings add denied servers and skill overrides without duplicates, the committed override wins, other machine keys are ignored, a missing or broken file changes nothing.
machine="$TEST_DIRECTORY/machine-settings.json"
printf '{"deniedMcpServers":[{"serverName":"a"}],"skillOverrides":{"one":"user-invocable-only"},"model":"new"}\n' >"$installed"
printf '{"deniedMcpServers":[{"serverName":"a"},{"serverName":"b"},{"serverName":"b"}],"skillOverrides":{"one":"off","two":"user-invocable-only"},"permissions":{"allow":["Bash(*)"]}}\n' >"$machine"
merge_machine_claude_settings "$installed" "$machine"
[ "$(jq -cS . "$installed")" = '{"deniedMcpServers":[{"serverName":"a"},{"serverName":"b"}],"model":"new","skillOverrides":{"one":"user-invocable-only","two":"user-invocable-only"}}' ] || fail "merged machine settings were $(jq -c . "$installed")"
printf '{"model":"new"}\n' >"$installed"
merge_machine_claude_settings "$installed" "$TEST_DIRECTORY/missing.json"
[ "$(jq -c . "$installed")" = '{"model":"new"}' ] || fail "a missing machine settings file changed the settings"
printf 'not json' >"$machine"
merge_machine_claude_settings "$installed" "$machine" 2>/dev/null
[ "$(jq -c . "$installed")" = '{"model":"new"}' ] || fail "a broken machine settings file changed the settings"

# The `trusted` read tools are allowed under every MCP server of the machine whose host is in the trusted hosts file, user-scope or added to one project, once each, after the committed rules and without duplicates, a missing or broken `~/.claude.json` changes nothing.
tools="$TEST_DIRECTORY/read-tools.json"
state="$TEST_DIRECTORY/claude.json"
trusted_hosts="$TEST_DIRECTORY/mcp-trusted-hosts"
printf '{"trusted":["read_a","read_b"],"hosts":{}}\n' >"$tools"
printf '# Private portal.\n  Portal.Example \r\n\n' >"$trusted_hosts"
printf '{"permissions":{"allow":["Bash(ls)","mcp__one__read_a"],"deny":["mcp__two__read_b"]},"model":"new"}\n' >"$installed"
printf '{"mcpServers":{"one":{"url":"https://portal.example/a"}},"projects":{"/repository":{"mcpServers":{"one":{"url":"https://portal.example/a"},"two":{"url":"https://portal.example/b"},"stranger":{"url":"https://stranger.example"}}},"/other":{}}}\n' >"$state"
allow_claude_mcp_read_tools "$installed" "$tools" "$state" "$trusted_hosts"
[ "$(jq -c . "$installed")" = '{"permissions":{"allow":["Bash(ls)","mcp__one__read_a","mcp__one__read_b","mcp__two__read_a","mcp__two__read_b"],"deny":["mcp__two__read_b"]},"model":"new"}' ] || fail "allowed MCP read tools were $(jq -c . "$installed")"
# Without the trusted hosts file the `trusted` tools stay prompted on every server.
printf '{"model":"new"}\n' >"$installed"
allow_claude_mcp_read_tools "$installed" "$tools" "$state" "$TEST_DIRECTORY/missing-hosts"
[ "$(jq -c . "$installed")" = '{"model":"new"}' ] || fail "a machine without trusted hosts got $(jq -c . "$installed")"
# The tools of a host go only to the servers with that host, whatever their name, path, port or case, never to another host or a server without a `url`.
printf '{"trusted":["read_a"],"hosts":{"vendor.example":["whoami"]}}\n' >"$tools"
printf '{"model":"new"}\n' >"$installed"
printf '{"mcpServers":{"renamed":{"url":"https://vendor.example/mcp?skills=inspect"},"ported":{"url":"https://VENDOR.example:8443"},"other":{"url":"https://other.example/vendor.example"},"lookalike":{"url":"https://vendor.example.other.example"},"local":{"command":"server"}}}\n' >"$state"
allow_claude_mcp_read_tools "$installed" "$tools" "$state" "$TEST_DIRECTORY/missing-hosts"
[ "$(jq -c '.permissions.allow' "$installed")" = '["mcp__ported__whoami","mcp__renamed__whoami"]' ] || fail "host read tools were $(jq -c . "$installed")"
printf '{"model":"new"}\n' >"$installed"
printf '{"projects":{}}\n' >"$state"
allow_claude_mcp_read_tools "$installed" "$tools" "$state" "$trusted_hosts"
[ "$(jq -c . "$installed")" = '{"model":"new"}' ] || fail "a machine without MCP servers got $(jq -c . "$installed")"
printf '{"model":"new"}\n' >"$installed"
allow_claude_mcp_read_tools "$installed" "$tools" "$TEST_DIRECTORY/missing.json" "$trusted_hosts"
[ "$(jq -c . "$installed")" = '{"model":"new"}' ] || fail "a missing ~/.claude.json changed the settings"
printf 'not json' >"$state"
allow_claude_mcp_read_tools "$installed" "$tools" "$state" "$trusted_hosts" 2>/dev/null
[ "$(jq -c . "$installed")" = '{"model":"new"}' ] || fail "a broken ~/.claude.json changed the settings"

# A plugin enabled by setup keeps the committed plugins, and a broken settings file stays as it was.
printf '{"enabledPlugins":{"swift-lsp@claude-plugins-official":true},"model":"new"}\n' >"$installed"
enable_claude_plugin "$installed" "xcode@claude-plugins-official"
[ "$(jq -cS . "$installed")" = '{"enabledPlugins":{"swift-lsp@claude-plugins-official":true,"xcode@claude-plugins-official":true},"model":"new"}' ] || fail "enabled plugin settings were $(jq -c . "$installed")"
printf 'not json' >"$installed"
enable_claude_plugin "$installed" "xcode@claude-plugins-official" 2>/dev/null
[ "$(cat "$installed")" = "not json" ] || fail "a broken settings file was changed when enabling a plugin"

# Only a turned on plugin that is not installed is reported, a missing or broken installed list installs them all.
printf '{"enabledPlugins":{"swift-lsp@claude-plugins-official":true,"claude-hud@claude-hud":true,"off@claude-hud":false}}\n' >"$installed"
installed_plugins="$TEST_DIRECTORY/installed_plugins.json"
printf '{"plugins":{"claude-hud@claude-hud":[{"scope":"user"}]}}\n' >"$installed_plugins"
[ "$(missing_claude_plugins "$installed" "$installed_plugins")" = "swift-lsp@claude-plugins-official" ] || fail "missing plugins were $(missing_claude_plugins "$installed" "$installed_plugins")"
[ "$(missing_claude_plugins "$installed" "$TEST_DIRECTORY/missing.json" | sort | tr '\n' ' ')" = "claude-hud@claude-hud swift-lsp@claude-plugins-official " ] || fail "a missing installed list did not report every plugin"
printf 'not json' >"$installed_plugins"
[ "$(missing_claude_plugins "$installed" "$installed_plugins" | wc -l | tr -d ' ')" = 2 ] || fail "a broken installed list did not report every plugin"

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: agentic"
