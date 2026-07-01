#!/bin/bash

set -e

AGENTIC_SCRIPT_DIRECTORY=$(cd "$(dirname "$0")" && pwd)
AGENTIC_DIRECTORY="$HOME/.config/agentic"
MODELS_FILE_PATH="$AGENTIC_DIRECTORY/models.txt"
AGENT_SOURCE_DIRECTORY="$AGENTIC_DIRECTORY/agents"

source "$AGENTIC_SCRIPT_DIRECTORY/../helpers/logs.sh"

if [ ! -f "$MODELS_FILE_PATH" ]; then
    log_error "models.txt not found at ${MODELS_FILE_PATH}"
    exit 1
fi

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

    agent_json_block+="    \"${agent}\": {
      \"mode\": \"${mode}\",
      \"model\": \"${model}\",
      \"variant\": \"${variant}\"
    },
"
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

log_info "Injecting Claude Code agent models..."

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

log_info "Creating symlinks..."

ln -sfn "$AGENTIC_DIRECTORY/agents"       "$HOME/.config/opencode/agents"
ln -sfn "$AGENTIC_DIRECTORY/instructions" "$HOME/.config/opencode/instructions"
ln -sfn "$AGENTIC_DIRECTORY/tools"        "$HOME/.config/opencode/tools"
ln -sfn "$AGENTIC_DIRECTORY/commands"     "$HOME/.config/opencode/commands"
ln -sfn "$AGENTIC_DIRECTORY/skills"       "$HOME/.config/opencode/skills"
ln -sf  "$AGENTIC_DIRECTORY/AGENTS.md"    "$HOME/.config/opencode/AGENTS.md"

mkdir -p "$HOME/.claude/rules"
ln -sf  "$AGENTIC_DIRECTORY/AGENTS.md"    "$HOME/.claude/CLAUDE.md"
ln -sfn "$AGENTIC_DIRECTORY/commands"     "$HOME/.claude/commands"
ln -sfn "$AGENTIC_DIRECTORY/skills"       "$HOME/.claude/skills"
ln -sfn "$AGENTIC_DIRECTORY/instructions" "$HOME/.claude/rules/instructions"
ln -sfn "$AGENTIC_DIRECTORY/tools"        "$HOME/.claude/rules/tools"
