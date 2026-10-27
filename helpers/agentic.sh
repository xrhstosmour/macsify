#!/bin/bash

# Steps of `setup/agentic.sh` that change installed files from a list, kept here
# so `tests/agentic.sh` can run them against a temporary directory. Needs
# `helpers/logs.sh` sourced first.

# Removes the skills listed as personal only from the installed copy, together
# with the command of the same name that invokes each skill. A CRLF line ending
# or stray spaces around a name are ignored. A line with a path separator or a
# leading dot is skipped, it could name something outside `skills/`.
# Usage:
#   remove_personal_skills <agentic directory> <personal skills file>
remove_personal_skills() {
  local agentic_directory="$1" skills_file="$2" skill
  while IFS= read -r skill || [ -n "$skill" ]; do
    skill="${skill%$'\r'}"
    skill="${skill#"${skill%%[![:space:]]*}"}"
    skill="${skill%"${skill##*[![:space:]]}"}"
    [[ -z "$skill" || "$skill" =~ ^# || "$skill" == */* || "$skill" == .* ]] && continue
    if [ -d "$agentic_directory/skills/$skill" ]; then
      log_info "Removing personal only skill '${skill}'..."
      rm -rf "${agentic_directory:?}/skills/${skill:?}"
    fi
    rm -f "${agentic_directory:?}/commands/${skill:?}.md"
  done <"$skills_file"
}

# Sets the `agent` block of an `opencode.json` from `models.txt`, one entry per
# OpenCode agent with a model, plus `explore` and `compaction`. A merge with
# `jq`, so the template's formatting does not matter. Fails when the result has
# no leader model.
# Usage:
#   inject_opencode_agent_models <opencode.json> <models.txt> <agents directory>
inject_opencode_agent_models() {
  local configuration="$1" models_file="$2" agents_directory="$3"
  local agents='{}' agent_file agent model variant mode explore_model compaction_model temporary

  for agent_file in "$agents_directory"/*.md; do
    agent=$(basename "$agent_file" .md)
    case "$agent" in
      leader | architect | implementor | clarifier | tester | designer | reviewer) ;;
      *) continue ;;
    esac

    model=$(grep "^opencode:${agent}:model:" "$models_file" | cut -d: -f4-)
    variant=$(grep "^opencode:${agent}:variant:" "$models_file" | cut -d: -f4-)
    [ -z "$model" ] && continue

    mode="subagent"
    [ "$agent" = "leader" ] && mode="primary"

    agents=$(jq -c --arg agent "$agent" --arg mode "$mode" --arg model "$model" --arg variant "$variant" \
      '.[$agent] = {mode: $mode, model: $model} + (if $variant == "" or $variant == "-" then {} else {variant: $variant} end)' <<<"$agents")
  done

  explore_model=$(grep '^opencode:explore:model:' "$models_file" | cut -d: -f4-)
  compaction_model=$(grep '^opencode:compaction:model:' "$models_file" | cut -d: -f4-)
  agents=$(jq -c --arg explore "${explore_model:-opencode/big-pickle}" --arg compaction "${compaction_model:-opencode/big-pickle}" \
    '. + {explore: {mode: "subagent", model: $explore}, compaction: {mode: "primary", model: $compaction}}' <<<"$agents")

  temporary=$(mktemp)
  if ! jq --argjson agents "$agents" '.agent = $agents' "$configuration" >"$temporary"; then
    rm -f "$temporary"
    log_error "Could not inject agent models into ${configuration}"
    return 1
  fi
  mv "$temporary" "$configuration"

  if ! jq -e '.agent.leader.model' "$configuration" >/dev/null; then
    log_error "Injected agent models are missing or invalid in ${configuration}"
    return 1
  fi
}
