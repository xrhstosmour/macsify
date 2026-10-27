#!/bin/bash

set -e

AGENTIC_SCRIPT_DIRECTORY=$(cd "$(dirname "$0")" && pwd)
AGENTIC_DIRECTORY="$HOME/.config/agentic"
MODELS_FILE_PATH="$AGENTIC_DIRECTORY/models.txt"
AGENT_SOURCE_DIRECTORY="$AGENTIC_DIRECTORY/agents"

source "$AGENTIC_SCRIPT_DIRECTORY/../helpers/logs.sh"
source "$AGENTIC_SCRIPT_DIRECTORY/../helpers/brewfile.sh"
source "$AGENTIC_SCRIPT_DIRECTORY/../helpers/symlink.sh"
source "$AGENTIC_SCRIPT_DIRECTORY/../helpers/phabricator.sh"
source "$AGENTIC_SCRIPT_DIRECTORY/../helpers/profile.sh"
source "$AGENTIC_SCRIPT_DIRECTORY/../helpers/agentic.sh"

# The profile decides which tools `brewfile_declares` sees and which skills stay installed.
profile_resolve

# Extract the dedented body of an agent markdown file's `description:` frontmatter
# field (a folded YAML block scalar), used to populate the description in
# generated Codex/Copilot agent files. Frontmatter keys start at column 0, so a
# `^[A-Za-z_-]+:` line with no leading whitespace ends the block, an indented
# line like "  Examples:" inside the description does not.
# Usage:
#   extract_agent_description "$agent_file"
extract_agent_description() {
  awk '
    /^---[[:space:]]*$/ {
      dashes++
      if (dashes == 2) exit
      next
    }
    dashes == 1 {
      if ($0 ~ /^description:/) { in_description = 1; next }
      if (in_description && $0 ~ /^[A-Za-z_-]+:/) { in_description = 0 }
      if (in_description) { sub(/^  /, ""); print }
    }
  ' "$1"
}

# Extract everything after an agent markdown file's frontmatter block, used as
# the agent's system prompt/instructions in generated Codex/Copilot agent files.
# Usage:
#   extract_agent_body "$agent_file"
extract_agent_body() {
  awk '
    /^---[[:space:]]*$/ { dashes++; next }
    dashes >= 2 { print }
  ' "$1"
}

# Runs a command with a timeout using bash builtins only, macOS ships no `timeout` binary and
# this repo doesn't otherwise depend on `coreutils`. Sends SIGTERM after $1 seconds, escalates
# to SIGKILL 5s later if the command ignored it, for example a CLI stuck reading `/dev/tty` in
# raw mode. Returns 124 on timeout, matching GNU `timeout`'s convention, otherwise the command's
# own exit status.
# Usage:
#   run_with_timeout <seconds> <command> [arguments...]
run_with_timeout() {
  local duration="$1"
  shift

  local timed_out_marker
  timed_out_marker=$(mktemp)
  rm -f "$timed_out_marker"

  "$@" &
  local command_pid=$!

  (
    sleep "$duration"
    if kill -0 "$command_pid" 2>/dev/null; then
      : >"$timed_out_marker"
      kill -TERM "$command_pid" 2>/dev/null
      sleep 5
      kill -KILL "$command_pid" 2>/dev/null
    fi
  ) &
  local watcher_pid=$!

  wait "$command_pid" 2>/dev/null
  local command_status=$?

  kill "$watcher_pid" 2>/dev/null
  wait "$watcher_pid" 2>/dev/null

  if [ -f "$timed_out_marker" ]; then
    rm -f "$timed_out_marker"
    return 124
  fi
  return "$command_status"
}

# Registers an MCP server via `<cli> mcp get`/`mcp add`, hardened against a misresolved or
# unauthenticated CLI throwing up an interactive prompt instead of failing: `</dev/null` forces
# immediate EOF on a stdin-read prompt, `run_with_timeout` catches one that reads `/dev/tty`
# directly instead. A timed-out check (exit 124) is logged and skipped rather than falling
# through to `mcp add` and hanging again. `mcp add` failures are logged and skipped rather than
# aborting the rest of the install. Returns 0 only when registration was attempted, so callers
# can conditionally print a follow-up note.
# Usage:
#   register_mcp_server <cli> <name> <label> <mcp add arguments...>
register_mcp_server() {
  local cli="$1" name="$2" label="$3"
  shift 3

  run_with_timeout 30 "$cli" mcp get "$name" </dev/null &>/dev/null
  local mcp_get_status=$?

  if [ "$mcp_get_status" -eq 0 ]; then
    log_warning "${label} MCP server already registered, skipping."
    return 1
  elif [ "$mcp_get_status" -eq 124 ]; then
    log_warning "${label} MCP check timed out, skipping registration attempt."
    return 1
  fi

  log_info "Registering ${label} MCP server..."
  run_with_timeout 30 "$cli" mcp add "$@" </dev/null || log_warning "${label} MCP registration failed, register manually later."
  return 0
}

# Runs a `herdr integration`/`herdr plugin` install, logging before and warning (never
# aborting the rest of the install) on failure. Factors out the repeated log-run-warn
# shape six Herdr install sites below would otherwise each hand-roll. Guards on `herdr`
# actually being on PATH, `brewfile_declares herdr` only proves the Brewfile lists it,
# not that `brew bundle` succeeded. Wrapped in `run_with_timeout`/`</dev/null` like
# `register_mcp_server` above, a `herdr integration install <agent>` call has no `--yes`
# equivalent and would otherwise hang the whole script under `set -e` on a stuck prompt.
# Usage:
#   install_herdr_component <label> <herdr subcommand and arguments...>
install_herdr_component() {
  local label="$1"
  shift

  if ! command -v herdr &>/dev/null; then
    log_warning "${label} skipped, herdr not found on PATH."
    return 1
  fi

  log_info "Installing ${label}..."
  run_with_timeout 30 "$@" </dev/null || log_warning "${label} install failed, run manually later."
}

# Refresh the installed copy every tool links to, so a rerun after a merge picks up new skills.
# `cp -R` only adds and overwrites, files that exist only in the installed copy stay.
log_info "Copying agentic configuration to ${AGENTIC_DIRECTORY}..."
mkdir -p "$AGENTIC_DIRECTORY"
cp -R "$AGENTIC_SCRIPT_DIRECTORY/../.config/agentic/." "$AGENTIC_DIRECTORY/"

# Skills listed as personal only are removed from the installed copy on any other
# profile, also when a machine switches profile after an earlier install.
PERSONAL_SKILLS_FILE_PATH="$AGENTIC_SCRIPT_DIRECTORY/../packages/personal.skills.txt"
if [ "$MACSIFY_PROFILE" != "personal" ] && [ -f "$PERSONAL_SKILLS_FILE_PATH" ]; then
    remove_personal_skills "$AGENTIC_DIRECTORY" "$PERSONAL_SKILLS_FILE_PATH"
fi
log_divider

# Only set up the tools declared in the Brewfile. `install.sh` runs `brew bundle` before
# this script, so the Brewfile is the intent signal, not a runtime `command -v` check.
if [ ! -f "$MODELS_FILE_PATH" ]; then
    log_error "models.txt not found at ${MODELS_FILE_PATH}"
    exit 1
fi

PHABRICATOR_MCP_URL="${PHABRICATOR_MCP_URL:-$(derive_phabricator_mcp_url)}"

if brewfile_declares "anomalyco/tap/opencode"; then
    log_info "Injecting OpenCode agent models..."

    OPENCODE_CONFIGURATION_PATH="$HOME/.config/opencode/opencode.json"
    OPENCODE_CONFIGURATION_TEMPLATE="$AGENTIC_SCRIPT_DIRECTORY/../.config/opencode/opencode.json"
    cp "$OPENCODE_CONFIGURATION_TEMPLATE" "$OPENCODE_CONFIGURATION_PATH"
    inject_opencode_agent_models "$OPENCODE_CONFIGURATION_PATH" "$MODELS_FILE_PATH" "$AGENT_SOURCE_DIRECTORY"

    # OpenCode's `{env:VAR}` config substitution reads its own process environment at launch, it has no equivalent to deriving from `~/.arcrc` itself. Bake the already-derived URL into this deployed (non-tracked) copy directly instead. If nothing was derived, leave the placeholder, OpenCode resolves it to an empty string and that one server just won't connect, not a hard failure.
    # A `&` or `|` in a URL is special in a `sed` replacement, escape both so a query string survives.
    if [ -n "$PHABRICATOR_MCP_URL" ]; then
        sed -i '' "s|{env:PHABRICATOR_MCP_URL}|$(printf '%s' "$PHABRICATOR_MCP_URL" | sed 's/[&|\\]/\\&/g')|" "$OPENCODE_CONFIGURATION_PATH"
    fi
    if [ -n "$GRAFANA_MCP_URL" ]; then
        sed -i '' "s|{env:GRAFANA_MCP_URL}|$(printf '%s' "$GRAFANA_MCP_URL" | sed 's/[&|\\]/\\&/g')|" "$OPENCODE_CONFIGURATION_PATH"
    fi
    if [ -n "$METABASE_MCP_URL" ]; then
        sed -i '' "s|{env:METABASE_MCP_URL}|$(printf '%s' "$METABASE_MCP_URL" | sed 's/[&|\\]/\\&/g')|" "$OPENCODE_CONFIGURATION_PATH"
    fi

    log_info "Creating OpenCode symlinks..."

    create_symlink "$AGENTIC_DIRECTORY/agents"       "$HOME/.config/opencode/agents"
    create_symlink "$AGENTIC_DIRECTORY/instructions" "$HOME/.config/opencode/instructions"
    create_symlink "$AGENTIC_DIRECTORY/commands"     "$HOME/.config/opencode/commands"
    create_symlink "$AGENTIC_DIRECTORY/skills"       "$HOME/.config/opencode/skills"
    create_symlink "$AGENTIC_DIRECTORY/AGENTS.md"    "$HOME/.config/opencode/AGENTS.md"

    # OpenCode auto-loads plugins from its plugin directory. This plugin blocks `WebFetch` on service
    # hosts and caps Bash output. `Claude Code` does the same via hooks and permissions.deny in
    # `settings.json`.
    mkdir -p "$HOME/.config/opencode/plugin"
    # Previous name of the plugin, a leftover link would keep loading the old file next to the new one.
    rm -f "$HOME/.config/opencode/plugin/agentic-reminder.js"
    create_symlink "$AGENTIC_DIRECTORY/hooks/opencode-guards.js" "$HOME/.config/opencode/plugin/agentic-guards.js"

    # `opencode-status-hud`'s own local-install default is `~/.config/opencode/plugins`, which
    # OpenCode does not auto-load. Force it into the same directory as `agentic-guards.js` above.
    # `mise`-installed `node`/`npm` come from `configure.sh`, which runs after this script, so
    # this no-ops on the first run, `configure.sh` reruns this script once `node` is installed.
    if command -v npm &>/dev/null; then
        if ! command -v opencode-status-hud &>/dev/null; then
            log_info "Installing opencode-status-hud plugin..."
            npm install -g opencode-status-hud@0.1.3 || log_warning "opencode-status-hud install failed, install manually later."
        fi
        opencode-status-hud install --mode local --plugin-dir "$HOME/.config/opencode/plugin" || log_warning "opencode-status-hud plugin registration failed, run manually later."
    else
        log_warning "Skipping 'opencode-status-hud' plugin installation as 'npm' not found!"
    fi

    # `Herdr`'s own installer drops a plugin file into OpenCode's plugin directory, unlike
    # the `settings.json`/`agentic.json` cases nothing here overwrites it on a re-run,
    # so this mainly matters for a first-time install picking up the integration at all.
    if brewfile_declares herdr; then
        install_herdr_component "Herdr integration for OpenCode" herdr integration install opencode
    fi
fi

if brewfile_declares claude-code; then
    log_info "Injecting Claude Code agent models..."

    # Fully regenerated from `agents/*.md` and `claude/agents/*.md` below, any
    # hand-added personal subagent not tracked in this repo is destroyed here on every run.
    rm -rf "$HOME/.claude/agents"
    mkdir -p "$HOME/.claude/agents"

    # `claude/agents/` holds Claude Code only overrides of built-in subagents, such as `Explore`.
    for agent_file in "$AGENT_SOURCE_DIRECTORY"/*.md "$AGENTIC_SCRIPT_DIRECTORY"/../claude/agents/*.md; do
        agent=$(basename "$agent_file" .md)
        model=$(grep "^claude:${agent}:model:" "$MODELS_FILE_PATH" | cut -d: -f4-)
        effort=$(grep "^claude:${agent}:effort:" "$MODELS_FILE_PATH" | cut -d: -f4- 2>/dev/null || true)

        [ -z "$model" ] && { log_warning "SKIP ${agent}: no model in models.txt"; continue; }

        # The directory was emptied above, so an existing file means two sources share a name.
        if [ -e "$HOME/.claude/agents/${agent}.md" ]; then
            log_warning "${agent}.md exists in both agent sources, the one from ${agent_file} wins."
        fi

        cp "$agent_file" "$HOME/.claude/agents/${agent}.md"
        sed -i '' "1s/^---$/---\\
model: ${model}/" "$HOME/.claude/agents/${agent}.md"

        if [ -n "$effort" ] && [ "$effort" != "-" ]; then
            sed -i '' "/^model:/a\\
effort: ${effort}" "$HOME/.claude/agents/${agent}.md"
        fi
    done

    # `autoMode` holds this machine's trusted repos and org details, Claude Code writes it, and
    # `skipDangerousModePermissionPrompt` is a per-machine acknowledgement. Neither belongs in
    # the committed file, so carry them across the overwrite below.
    preserved_settings=""
    if [ -f "$HOME/.claude/settings.json" ] && command -v jq >/dev/null 2>&1; then
        preserved_settings=$(jq -c '{autoMode, skipDangerousModePermissionPrompt} | with_entries(select(.value != null))' "$HOME/.claude/settings.json" 2>/dev/null || true)
    fi

    log_info "Copying Claude Code settings..."
    cp "$AGENTIC_SCRIPT_DIRECTORY/../claude/settings.json" "$HOME/.claude/"

    if [ -n "$preserved_settings" ] && [ "$preserved_settings" != "{}" ]; then
        merged_settings=$(mktemp)
        if jq --argjson keep "$preserved_settings" '. + $keep' "$HOME/.claude/settings.json" > "$merged_settings"; then
            mv "$merged_settings" "$HOME/.claude/settings.json"
        else
            rm -f "$merged_settings"
            log_warning "Could not restore autoMode in ~/.claude/settings.json, add it back by hand."
        fi
    fi
    cp "$AGENTIC_SCRIPT_DIRECTORY/../claude/keybindings.json" "$HOME/.claude/"

    # `claude/settings.json` commits a bare `bun` in `statusLine.command` and this resolves it to
    # an absolute path, which is what the HUD needs since Claude Code does not run the statusline
    # through a `mise`-shimmed shell. The committed value stays a bare command name so the file
    # carries no machine or user specific path, and so an unsubstituted checkout still works
    # wherever `bun` is on `PATH` instead of pointing at some other machine's home directory.
    # Same `mise`-installed `node`/`bun` gap as `opencode-status-hud` above, not available yet
    # on a first-time install, re-run `install.sh` after `configure.sh` completes to pick it up.
    log_info "Re-detecting claude-hud runtime path..."
    hud_runtime_path=$(command -v bun || command -v node || true)
    if [ -n "$hud_runtime_path" ]; then
        node -e '
const fs = require("fs");
const path = process.argv[1];
const runtimePath = process.argv[2];
const settings = JSON.parse(fs.readFileSync(path, "utf8"));
if (settings.statusLine && typeof settings.statusLine.command === "string") {
    settings.statusLine.command = settings.statusLine.command.replace(
        /exec "[^"]+"/,
        "exec \"" + runtimePath + "\""
    );
    fs.writeFileSync(path, JSON.stringify(settings, null, 2) + "\n");
}
' "$HOME/.claude/settings.json" "$hud_runtime_path"
    else
        log_warning "No 'bun' or 'node' found, leaving 'claude-hud' statusLine command as committed, it falls back to whatever 'bun' resolves to on PATH."
    fi

    mkdir -p "$HOME/.claude/plugins/claude-hud"
    cp "$AGENTIC_SCRIPT_DIRECTORY/../claude/plugins/claude-hud/config.json" "$HOME/.claude/plugins/claude-hud/"

    log_info "Creating Claude Code symlinks..."

    mkdir -p "$HOME/.claude/rules"

    # Prune dangling symlinks left behind by a source directory this repo no longer
    # provides (like the old `tools/` folder). Only removes *broken* symlinks, so a
    # currently-valid one a user or tool placed under this directory is untouched, a
    # failure to unlink one shouldn't block the rest of setup below.
    find "$HOME/.claude/rules" -maxdepth 1 -type l ! -exec test -e {} \; -delete \
        || log_warning "Could not prune stale symlinks under ~/.claude/rules, check manually."
    create_symlink "$AGENTIC_DIRECTORY/AGENTS.md"    "$HOME/.claude/CLAUDE.md"
    create_symlink "$AGENTIC_DIRECTORY/commands"     "$HOME/.claude/commands"
    create_symlink "$AGENTIC_DIRECTORY/skills"       "$HOME/.claude/skills"
    create_symlink "$AGENTIC_DIRECTORY/instructions" "$HOME/.claude/rules/instructions"

    # Phabricator MCP, OAuth handled lazily on first use, see the read-phabricator-task skill.
    # See `register_mcp_server` above for the hardening applied to every `mcp` invocation below.
    if ! command -v claude &>/dev/null; then
        log_warning "Skipping Phabricator MCP registration, 'claude' CLI not found."
    elif [ -z "$PHABRICATOR_MCP_URL" ]; then
        log_warning "Skipping Phabricator MCP registration, no URL derived from '~/.arcrc' or 'PHABRICATOR_MCP_URL' environment variable."
    else
        register_mcp_server claude phabricator Phabricator --transport http phabricator "$PHABRICATOR_MCP_URL" -s user || true
    fi

    # Sentry's official hosted MCP, OAuth handled lazily on first use, see the read-sentry-issue skill for the read-only scoping steps.
    if ! command -v claude &>/dev/null; then
        log_warning "Skipping Sentry MCP registration, 'claude' CLI not found."
    elif register_mcp_server claude sentry Sentry --transport http sentry "https://mcp.sentry.dev/mcp?skills=inspect" -s user; then
        log_warning "Uncheck everything except 'Inspect Issues & Events' on the consent screen."
    fi

    # Grafana MCP, requires GRAFANA_MCP_URL to be set.
    if ! command -v claude &>/dev/null; then
        log_warning "Skipping Grafana MCP registration, 'claude' CLI not found."
    elif [ -z "$GRAFANA_MCP_URL" ]; then
        log_warning "Skipping Grafana MCP registration, no 'GRAFANA_MCP_URL' environment variable."
    else
        register_mcp_server claude grafana Grafana --transport http grafana "$GRAFANA_MCP_URL" -s user || true
    fi

    # Metabase MCP, requires METABASE_MCP_URL to be set.
    if ! command -v claude &>/dev/null; then
        log_warning "Skipping Metabase MCP registration, 'claude' CLI not found."
    elif [ -z "$METABASE_MCP_URL" ]; then
        log_warning "Skipping Metabase MCP registration, no 'METABASE_MCP_URL' environment variable."
    else
        register_mcp_server claude metabase Metabase --transport http metabase "$METABASE_MCP_URL" -s user || true
    fi

    # `Herdr`'s own installer merges a `SessionStart` hook into `settings.json` so its
    # sidebar can show this agent's live status, run last so it lands after the `cp`
    # above overwrote the file with the tracked baseline, not before.
    if brewfile_declares herdr; then
        install_herdr_component "Herdr integration for Claude Code" herdr integration install claude
    fi
fi

if brewfile_declares codex; then
    log_info "Injecting Codex agent definitions..."

    CODEX_DIRECTORY="$HOME/.codex"
    rm -rf "$CODEX_DIRECTORY/agents"
    mkdir -p "$CODEX_DIRECTORY/agents"

    for agent_file in "$AGENT_SOURCE_DIRECTORY"/*.md; do
        agent=$(basename "$agent_file" .md)
        model=$(grep "^codex:${agent}:model:" "$MODELS_FILE_PATH" | cut -d: -f4- 2>/dev/null || true)
        effort=$(grep "^codex:${agent}:effort:" "$MODELS_FILE_PATH" | cut -d: -f4- 2>/dev/null || true)

        [ -z "$model" ] && { log_warning "SKIP ${agent}: no model in models.txt"; continue; }

        description=$(extract_agent_description "$agent_file")
        instructions=$(extract_agent_body "$agent_file")

        {
            printf 'name = "%s"\n' "$agent"
            printf 'model = "%s"\n' "$model"
            [ -n "$effort" ] && [ "$effort" != "-" ] && printf 'model_reasoning_effort = "%s"\n' "$effort"
            printf "description = '''\n%s\n'''\n" "$description"
            printf "developer_instructions = '''\n%s\n'''\n" "$instructions"
        } >"$CODEX_DIRECTORY/agents/${agent}.toml"
    done

    log_info "Creating Codex symlinks..."

    create_symlink "$AGENTIC_DIRECTORY/AGENTS.md" "$CODEX_DIRECTORY/AGENTS.md"
    create_symlink "$AGENTIC_DIRECTORY/skills"    "$CODEX_DIRECTORY/skills"
    create_symlink "$AGENTIC_DIRECTORY/commands"  "$CODEX_DIRECTORY/prompts"

    # Phabricator/Sentry MCP, mirrors the Claude Code block above, including the
    # `</dev/null`/`timeout`/fail-soft hardening on every `mcp` invocation.
    if ! command -v codex &>/dev/null; then
        log_warning "Skipping Phabricator/Sentry MCP registration, 'codex' CLI not found."
    else
        if [ -z "$PHABRICATOR_MCP_URL" ]; then
            log_warning "Skipping Phabricator MCP registration, no URL derived from '~/.arcrc' or 'PHABRICATOR_MCP_URL' environment variable."
        elif grep -q '^\[mcp_servers\.phabricator\]' "$CODEX_DIRECTORY/config.toml" 2>/dev/null; then
            log_warning "Phabricator MCP server already registered, skipping."
        else
            log_info "Registering Phabricator MCP server..."
            run_with_timeout 30 codex mcp add phabricator --url "$PHABRICATOR_MCP_URL" </dev/null || log_warning "Phabricator MCP registration failed, register manually later."
        fi

        if grep -q '^\[mcp_servers\.sentry\]' "$CODEX_DIRECTORY/config.toml" 2>/dev/null; then
            log_warning "Sentry MCP server already registered, skipping."
        else
            log_info "Registering Sentry MCP server..."
            run_with_timeout 30 codex mcp add sentry --url "https://mcp.sentry.dev/mcp?skills=inspect" </dev/null || log_warning "Sentry MCP registration failed, register manually later."
            log_warning "Uncheck everything except 'Inspect Issues & Events' on the consent screen."
        fi
    fi

    # `Herdr`'s own installer merges a `SessionStart` hook into `hooks.json`.
    if brewfile_declares herdr; then
        install_herdr_component "Herdr integration for Codex" herdr integration install codex
    fi
fi

if brewfile_declares copilot-cli; then
    log_info "Injecting Copilot CLI agent definitions..."

    COPILOT_DIRECTORY="$HOME/.copilot"
    rm -rf "$COPILOT_DIRECTORY/agents"
    mkdir -p "$COPILOT_DIRECTORY/agents" "$COPILOT_DIRECTORY/hooks"

    for agent_file in "$AGENT_SOURCE_DIRECTORY"/*.md; do
        agent=$(basename "$agent_file" .md)
        model=$(grep "^copilot:${agent}:model:" "$MODELS_FILE_PATH" | cut -d: -f4- 2>/dev/null || true)

        [ -z "$model" ] && { log_warning "SKIP ${agent}: no model in models.txt"; continue; }

        description=$(extract_agent_description "$agent_file")
        instructions=$(extract_agent_body "$agent_file")

        # Only `name`/`description`/`model` carry over. `disallowedTools`/`permission`
        # are Claude/OpenCode-only fields, Copilot's `tools:` is an allowlist, not a
        # denylist, so there's no faithful translation, these agents get all tools.
        {
            printf -- '---\n'
            printf 'name: %s\n' "$agent"
            printf 'description: >-\n'
            printf '%s\n' "$description" | sed 's/^/  /'
            printf 'model: %s\n' "$model"
            printf -- '---\n'
            printf '%s\n' "$instructions"
        } >"$COPILOT_DIRECTORY/agents/${agent}.agent.md"
    done

    log_info "Creating Copilot CLI symlinks..."

    create_symlink "$AGENTIC_DIRECTORY/AGENTS.md" "$COPILOT_DIRECTORY/copilot-instructions.md"
    create_symlink "$AGENTIC_DIRECTORY/skills"    "$COPILOT_DIRECTORY/skills"

    log_info "Writing Copilot CLI hooks..."

    # PascalCase event names opt into Copilot's Claude-format matcher semantics, so
    # `webfetch-guard.sh` reads the same `tool_name`/`tool_input.url` shape it
    # already gets from Claude Code and Codex.
    cat >"$COPILOT_DIRECTORY/hooks/agentic.json" <<'EOF'
{
  "version": 1,
  "hooks": {
    "PreToolUse": [
      { "type": "command", "matcher": "WebFetch", "bash": "bash ~/.config/agentic/hooks/webfetch-guard.sh" }
    ]
  }
}
EOF

    # Phabricator/Sentry MCP, mirrors the Claude Code block above, a `copilot` binary resolved
    # from an unrelated install (for example a bundled editor extension) can throw up an
    # interactive prompt instead of failing outright, see `register_mcp_server` above for the
    # hardening applied to every `mcp` invocation below.
    if ! command -v copilot &>/dev/null; then
        log_warning "Skipping Phabricator/Sentry MCP registration, 'copilot' CLI not found."
    else
        if [ -z "$PHABRICATOR_MCP_URL" ]; then
            log_warning "Skipping Phabricator MCP registration, no URL derived from '~/.arcrc' or 'PHABRICATOR_MCP_URL' environment variable."
        else
            register_mcp_server copilot phabricator Phabricator --transport http phabricator "$PHABRICATOR_MCP_URL" || true
        fi

        if register_mcp_server copilot sentry Sentry --transport http sentry "https://mcp.sentry.dev/mcp?skills=inspect"; then
            log_warning "Uncheck everything except 'Inspect Issues & Events' on the consent screen."
        fi
    fi

    # `Herdr`'s own installer merges a `SessionStart` hook into `hooks/agentic.json`, run
    # last so it lands after the `cat >"$COPILOT_DIRECTORY/hooks/agentic.json"` above
    # overwrote the file with the tracked baseline, not before.
    if brewfile_declares herdr; then
        install_herdr_component "Herdr integration for Copilot CLI" herdr integration install copilot
    fi
fi

if brewfile_declares herdr; then
    # `herdr` itself has no auto-naming, new tabs just show a bare number, so
    # `.config/herdr/config.toml` pairs with this plugin (152 stars, MIT,
    # reviewed for network calls before adding here) instead of reinventing it.
    # Pinned to the tag reviewed above, `herdr plugin install` is idempotent so
    # re-running this is safe, but floating on the branch would silently pull
    # whatever the next upstream push contains straight into every shell.
    install_herdr_component "herdr-automatic-rename plugin" herdr plugin install qu8n/herdr-automatic-rename --ref v0.11.1 --yes

    # Diff/file review pane, reviewed before adding: read-only against the
    # worktree, only network call is reading (never posting to) the PR via
    # `gh`/`glab`/`az`, per its own `README.md`. Pinned to the tag reviewed above,
    # same reasoning as the plugin install right before this one.
    install_herdr_component "herdr-reviewr plugin" herdr plugin install persiyanov/herdr-reviewr --ref v0.38.0 --yes

    # Local plugin from this repository, runs the `gfrb` fetch and rebase in every
    # herdr pane checked out on `main` or `master`. `install.sh` copied it into `~/.config` already, a
    # link points herdr at it in place, so later edits need no re-link.
    # Previous name of the plugin, a leftover link would run every sync twice.
    if herdr plugin list 2>/dev/null | grep -q '^- herdr-repo-sync '; then
        log_info "Unlinking the 'herdr-repo-sync' plugin, renamed to 'herdr-repository-sync'..."
        if run_with_timeout 30 herdr plugin unlink herdr-repo-sync </dev/null; then
            rm -rf "$HOME/.config/herdr-repo-sync" "${XDG_CACHE_HOME:-$HOME/.cache}/herdr-repo-sync"
        else
            log_warning "Could not unlink 'herdr-repo-sync', run 'herdr plugin unlink herdr-repo-sync' by hand."
        fi
    fi
    if ! herdr plugin list 2>/dev/null | grep -q '^- herdr-repository-sync '; then
        install_herdr_component "herdr-repository-sync plugin" herdr plugin link "$HOME/.config/herdr-repository-sync" --enabled
    fi

    # Local plugin from this repository, removes a clean worktree under
    # `~/Developer/worktrees` once its herdr workspace is closed, same link
    # reasoning as `herdr-repository-sync` above.
    if ! herdr plugin list 2>/dev/null | grep -q '^- herdr-worktree-cleanup '; then
        install_herdr_component "herdr-worktree-cleanup plugin" herdr plugin link "$HOME/.config/herdr-worktree-cleanup" --enabled
    fi
fi
