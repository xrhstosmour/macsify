#!/bin/bash

# Steps of `setup/agentic.sh` that change installed files from a list, kept here
# so `tests/agentic.sh` can run them against a temporary directory. Needs
# `helpers/logs.sh` sourced first.

# Removes the skills listed, personal only or retired, from the installed copy, together
# with the command of the same name that invokes each skill. A CRLF line ending
# or stray spaces around a name are ignored. A line with a path separator or a
# leading dot is skipped, it could name something outside `skills/`.
# Usage:
#   remove_listed_skills <agentic directory> <skills file>
remove_listed_skills() {
  local agentic_directory="$1" skills_file="$2" skill
  while IFS= read -r skill || [ -n "$skill" ]; do
    skill="${skill%$'\r'}"
    skill="${skill#"${skill%%[![:space:]]*}"}"
    skill="${skill%"${skill##*[![:space:]]}"}"
    [[ -z "$skill" || "$skill" =~ ^# || "$skill" == */* || "$skill" == .* ]] && continue
    if [ -d "$agentic_directory/skills/$skill" ]; then
      log_info "Removing skill '${skill}'..."
      rm -rf "${agentic_directory:?}/skills/${skill:?}"
    fi
    rm -f "${agentic_directory:?}/commands/${skill:?}.md"
  done <"$skills_file"
}

# Removes an installed script the source no longer has, a renamed or removed one
# would stay runnable without the checks of its successor.
# Usage:
#   remove_stale_scripts <source directory> <installed directory>
remove_stale_scripts() {
  local source_directory="$1" installed_directory="$2" installed_script
  for installed_script in "$installed_directory/"*.sh; do
    [ -e "$installed_script" ] || continue
    if [ ! -e "$source_directory/$(basename "$installed_script")" ]; then
      rm -f "$installed_script"
    fi
  done
}

# The green watcher was the resolve watcher, its cache holds the keys marked done
# and the claims that count the cycles of the day, moved so neither starts over.
# A cache of the new name already there wins, it is never overwritten.
# Usage:
#   move_green_watcher_cache <cache directory>
move_green_watcher_cache() {
  local cache_directory="$1"
  if [ -d "$cache_directory/resolve-github-prs-comments-watcher" ] && [ ! -e "$cache_directory/green-github-prs-watcher" ]; then
    mv "$cache_directory/resolve-github-prs-comments-watcher" "$cache_directory/green-github-prs-watcher"
  fi
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

# Prints the keys of an installed `Claude Code` settings file that belong to the
# machine, as a `JSON` object, `{}` when there are none or the file is missing
# or not `JSON`. `autoMode` holds this machine's trusted repositories,
# `skipDangerousModePermissionPrompt` is a per-machine acknowledgement and
# `model` is the person's last `/model` choice, which a rerun must not reset,
# so they are carried across the copy of the committed file. The committed
# `model` only seeds a new machine, changing it never reaches an installed one.
# Usage:
#   preserved_claude_settings <installed settings file>
preserved_claude_settings() {
  local file="$1" preserved=""
  if [ -f "$file" ] && command -v jq >/dev/null 2>&1; then
    preserved=$(jq -c '{autoMode, skipDangerousModePermissionPrompt, model} | with_entries(select(.value != null))' "$file" 2>/dev/null || true)
  fi
  [ -n "$preserved" ] || preserved="{}"
  printf '%s\n' "$preserved"
}

# Adds the preserved keys back to the settings file just copied over the
# installed one. A preserved key replaces the repository's value of the same
# key, the other repository keys stay.
# Usage:
#   restore_claude_settings <installed settings file> <preserved JSON>
restore_claude_settings() {
  local file="$1" preserved="$2" merged
  [ -n "$preserved" ] && [ "$preserved" != "{}" ] || return 0
  merged=$(mktemp)
  if jq --argjson keep "$preserved" '. + $keep' "$file" >"$merged"; then
    mv "$merged" "$file"
  else
    rm -f "$merged"
    log_warning "Could not restore ${preserved} in ${file}, add it back by hand."
  fi
}
