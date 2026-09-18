#!/bin/bash

# Fails if any skill's `SKILL.md` frontmatter is missing a non-empty `name` or
# `description` field. Frontmatter-boundary detection mirrors `setup/agentic.sh`'s
# `extract_agent_body`.

set -e

exit_status=0

for skill_file in .config/agentic/skills/*/SKILL.md; do
    frontmatter=$(awk '
        /^---[[:space:]]*$/ { dashes++; if (dashes == 2) exit; next }
        dashes == 1 { print }
    ' "$skill_file")

    if ! grep -q '^name: *[^[:space:]]' <<< "$frontmatter"; then
        echo "::error file=${skill_file}::Missing or empty 'name' in frontmatter"
        exit_status=1
    fi
    if ! grep -q '^description: *[^[:space:]]' <<< "$frontmatter"; then
        echo "::error file=${skill_file}::Missing or empty 'description' in frontmatter"
        exit_status=1
    fi
done

exit "$exit_status"
