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

    agent_json_block=""
    for agent_file in "$AGENT_SOURCE_DIRECTORY"/*.md; do
        agent=$(basename "$agent_file" .md)
        case "$agent" in
            leader|architect|implementor|clarifier|tester|designer|reviewer) ;;
            *) continue ;;
        esac

        model=$(grep "^opencode:${agent}:model:" "$MODELS_FILE_PATH" | cut -d: -f4-)
        variant=$(grep "^opencode:${agent}:variant:" "$MODELS_FILE_PATH" | cut -d: -f4-)
        [ -z "$model" ] && continue

        mode="subagent"
        [ "$agent" = "leader" ] && mode="primary"

        if [ "$variant" != "-" ]; then
            agent_json_block+="    \"${agent}\": {
      \"mode\": \"${mode}\",
      \"model\": \"${model}\",
      \"variant\": \"${variant}\"
    },
"
        else
            agent_json_block+="    \"${agent}\": {
      \"mode\": \"${mode}\",
      \"model\": \"${model}\"
    },
"
        fi
    done

    explore_model=$(grep '^opencode:explore:model:' "$MODELS_FILE_PATH" | cut -d: -f4-)
    compaction_model=$(grep '^opencode:compaction:model:' "$MODELS_FILE_PATH" | cut -d: -f4-)

    agent_json_block+="    \"explore\": {
      \"mode\": \"subagent\",
      \"model\": \"${explore_model:-opencode/big-pickle}\"
    },
    \"compaction\": {
      \"mode\": \"primary\",
      \"model\": \"${compaction_model:-opencode/big-pickle}\"
    }"

    agent_section_file=$(mktemp)
    printf '  \"agent\": {\n%s\n  },\n' "${agent_json_block}" > "$agent_section_file"
    sed -i '' "/\"default_agent\": \"leader\",/r ${agent_section_file}" "$OPENCODE_CONFIGURATION_PATH"
    rm -f "$agent_section_file"

    # OpenCode's `{env:VAR}` config substitution reads its own process environment at launch, it has no equivalent to deriving from `~/.arcrc` itself. Bake the already-derived URL into this deployed (non-tracked) copy directly instead. If nothing was derived, leave the placeholder, OpenCode resolves it to an empty string and that one server just won't connect, not a hard failure.
    if [ -n "$PHABRICATOR_MCP_URL" ]; then
        sed -i '' "s|{env:PHABRICATOR_MCP_URL}|${PHABRICATOR_MCP_URL}|" "$OPENCODE_CONFIGURATION_PATH"
    fi

    log_info "Creating OpenCode symlinks..."

    create_symlink "$AGENTIC_DIRECTORY/agents"       "$HOME/.config/opencode/agents"
    create_symlink "$AGENTIC_DIRECTORY/instructions" "$HOME/.config/opencode/instructions"
    create_symlink "$AGENTIC_DIRECTORY/commands"     "$HOME/.config/opencode/commands"
    create_symlink "$AGENTIC_DIRECTORY/skills"       "$HOME/.config/opencode/skills"
    create_symlink "$AGENTIC_DIRECTORY/AGENTS.md"    "$HOME/.config/opencode/AGENTS.md"

    # OpenCode auto-loads plugins from its plugin directory. This plugin re-injects the routing reminder
    # each turn and blocks `WebFetch` on service hosts. `Claude Code` does the same via the `UserPromptSubmit`
    # hook and permissions.deny in `settings.json`.
    mkdir -p "$HOME/.config/opencode/plugin"
    create_symlink "$AGENTIC_DIRECTORY/hooks/opencode-context-guard.js" "$HOME/.config/opencode/plugin/agentic-reminder.js"

    # `opencode-status-hud`'s own local-install default is `~/.config/opencode/plugins`, which
    # OpenCode does not auto-load. Force it into the same directory as `agentic-reminder.js` above.
    # `mise`-installed `node`/`npm` come from `configure.sh`, which runs after this script, so
    # this still no-ops on a first-time install, re-run `install.sh` afterward, idempotent, to
    # pick it up.
    if command -v npm &>/dev/null; then
        if ! command -v opencode-status-hud &>/dev/null; then
            log_info "Installing opencode-status-hud plugin..."
            npm install -g opencode-status-hud || log_warning "opencode-status-hud install failed, install manually later."
        fi
        opencode-status-hud install --mode local --plugin-dir "$HOME/.config/opencode/plugin" || log_warning "opencode-status-hud plugin registration failed, run manually later."
    else
        log_warning "Skipping 'opencode-status-hud' plugin installation as 'npm' not found!"
    fi

    # `Herdr`'s own installer drops a plugin file into OpenCode's plugin directory, unlike
    # the `settings.json`/`hooks.json` cases above nothing here overwrites it on a re-run,
    # so this mainly matters for a first-time install picking up the integration at all.
    if command -v herdr &>/dev/null; then
        log_info "Installing Herdr integration for OpenCode..."
        herdr integration install opencode || log_warning "Herdr integration install failed for opencode, run manually later."
    fi
fi

if brewfile_declares claude-code; then
    log_info "Injecting Claude Code agent models..."

    # Fully regenerated from agents/*.md below, any hand-added personal subagent
    # not tracked in this repo is destroyed here on every run.
    rm -rf "$HOME/.claude/agents"
    mkdir -p "$HOME/.claude/agents"

    for agent_file in "$AGENT_SOURCE_DIRECTORY"/*.md; do
        agent=$(basename "$agent_file" .md)
        model=$(grep "^claude:${agent}:model:" "$MODELS_FILE_PATH" | cut -d: -f4-)
        effort=$(grep "^claude:${agent}:effort:" "$MODELS_FILE_PATH" | cut -d: -f4- 2>/dev/null || true)

        [ -z "$model" ] && { log_warning "SKIP ${agent}: no model in models.txt"; continue; }

        cp "$agent_file" "$HOME/.claude/agents/${agent}.md"
        sed -i '' "1s/^---$/---\\
model: ${model}/" "$HOME/.claude/agents/${agent}.md"

        if [ -n "$effort" ] && [ "$effort" != "-" ]; then
            sed -i '' "/^model:/a\\
effort: ${effort}" "$HOME/.claude/agents/${agent}.md"
        fi
    done

    log_info "Copying Claude Code settings..."
    cp "$AGENTIC_SCRIPT_DIRECTORY/../claude/settings.json" "$HOME/.claude/"
    cp "$AGENTIC_SCRIPT_DIRECTORY/../claude/keybindings.json" "$HOME/.claude/"

    # `claude/settings.json` bakes an absolute `claude-hud` runtime path into `statusLine.command`.
    # That path is machine and user specific, so re-detect it here instead of trusting whatever
    # was last committed, otherwise a path from one machine silently breaks the HUD on another.
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
        log_warning "No 'bun' or 'node' found, leaving 'claude-hud' statusLine command as committed."
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

    # `Herdr`'s own installer merges a `SessionStart` hook into `settings.json` so its
    # sidebar can show this agent's live status, run last so it lands after the `cp`
    # above overwrote the file with the tracked baseline, not before.
    if command -v herdr &>/dev/null; then
        log_info "Installing Herdr integration for Claude Code..."
        herdr integration install claude || log_warning "Herdr integration install failed for claude, run manually later."
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

    log_info "Writing Codex hooks..."

    # No `PreToolUse` web-fetch guard here: Codex has no built-in URL-fetch tool to
    # gate, its `web_search` tool returns query snippets, not a fetched URL, so
    # there's nothing for `webfetch-guard.sh` to match against.
    cat >"$CODEX_DIRECTORY/hooks.json" <<'EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash ~/.config/agentic/hooks/context-guard.sh" } ] }
    ]
  }
}
EOF

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

    # `Herdr`'s own installer merges a `SessionStart` hook into `hooks.json`, run last
    # so it lands after the `cat >"$CODEX_DIRECTORY/hooks.json"` above overwrote the
    # file with the tracked baseline, not before.
    if command -v herdr &>/dev/null; then
        log_info "Installing Herdr integration for Codex..."
        herdr integration install codex || log_warning "Herdr integration install failed for codex, run manually later."
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
    ],
    "UserPromptSubmit": [
      { "type": "command", "bash": "bash ~/.config/agentic/hooks/context-guard.sh" }
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
    if command -v herdr &>/dev/null; then
        log_info "Installing Herdr integration for Copilot CLI..."
        herdr integration install copilot || log_warning "Herdr integration install failed for copilot, run manually later."
    fi
fi

if command -v herdr &>/dev/null; then
    # `herdr` itself has no auto-naming, new tabs just show a bare number, so
    # `.config/herdr/config.toml` pairs with this plugin (152 stars, MIT,
    # reviewed for network calls before adding here) instead of reinventing it.
    # `herdr plugin install` is idempotent, safe to run on every setup pass.
    log_info "Installing herdr-automatic-rename plugin..."
    herdr plugin install qu8n/herdr-automatic-rename --yes || log_warning "herdr-automatic-rename install failed, run manually later."
fi
