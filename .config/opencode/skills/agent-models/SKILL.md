---
name: agent-models
description: >
   Research available models for any provider, rank them per agent role, and update
   all model references across agent configs and opencode.json. Works with OpenCode,
   Claude Code, Codex, and any agentic environment.
---

# Agent Models

## When to use

User asks to update, refresh, or change models across all agent configs, or switch providers.

## Provider selection

Ask user to pick a provider:

1. opencode-go
2. github-copilot
3. claude-code
4. custom, user pastes their own model table

## Research models

For known providers, attempt to fetch model info from these sources:

| Provider | URL(s) to try |
|----------|---------------|
| opencode-go | `https://opencode.ai/go` |
| github-copilot | `https://docs.github.com/en/copilot/reference/ai-models/supported-models` |
| claude-code | `https://docs.anthropic.com/en/docs/about-claude/models` |

For each model found, extract Model name, Provider, Rate limits, and Quality tier if available.

If web fetch fails or data is incomplete, ask the user to paste the model table directly (name, provider, rate limits columns).

For `custom`, ask user to paste a table with columns: Model, Provider, requests per 5h, requests per week, requests per month.

## Determine variants

After selecting models, determine the highest available variant per model. Do not guess, fetch the source of truth. The `variant:` field in agent YAML is OpenCode-specific; other tools (Claude Code, Codex) use their own internal systems.

### Running Through OpenCode

Fetch `https://models.dev/api.json`, filter by provider (`opencode-go`, `github-copilot`, `anthropic`, `openai`, etc.), and check each model's `reasoning_options` array:

- Empty (`[]`) → no variants, then remove `variant:` line from agent YAML
- Non-empty → use the highest/latest value from the array of strings. For example, `["max", "xhigh", "high"]` → use `max`. If the array is `["low", "medium", "high"]`, use `high`. If the array is `["none", "minimal", "low", "medium", "high"]`, use `high`.

### Running Through Claude Code

Claude Code uses the `effort` parameter as the equivalent of variants. Fetch available models and their effort levels from `https://docs.anthropic.com/en/docs/build-with-claude/effort`.

Available levels: `low`, `medium`, `high` which is the default, `xhigh`, `max`. Not all models support all levels.

### Running Through Codex

Codex uses the `reasoning.effort` parameter as the equivalent of variants. Fetch available models and their reasoning effort levels from `https://platform.openai.com/docs/guides/reasoning`.

Available levels: `none`, `minimal`, `low`, `medium`, `high`, `xhigh`. Model-dependent which are supported.

### Other Environments And Custom Providers

Ask the user which variants/effort levels each model supports.

## Rank per role

Analyze each model on these criteria:

| Agent role | Priority |
|------------|----------|
| leader, architect | Reasoning strength, context window |
| implementor | Code generation quality |
| reviewer | Critical reasoning, analysis |
| designer | Creative/UX reasoning |
| tester, clarifier | Speed, rate limits (cheaper is fine) |
| default, explore, compaction (in opencode.json) | Speed, rate limits |

Rank models from best to worst for each role. Show the proposed mapping to the user with a brief rationale for each assignment.

Important: Never assign the same model to adjacent pipeline roles (implementor + reviewer), use different vendors so the review catches blind spots.

## Apply

Once the user approves, update the config files. The same agent `.md` files with YAML frontmatter can be shared across environments, the `variant:` field maps to each tool's equivalent concept.

### Mapping

| YAML field | OpenCode | Claude Code | Codex |
|------------|----------|-------------|-------|
| `model:` | `model:` in agent YAML | `model:` in agent YAML | `model:` in agent YAML |
| `variant:` | `variant:` (native) | `effort` parameter | `reasoning.effort` parameter |

### Apply to OpenCode

Read the actual filesystem:

1. Read `.config/opencode/opencode.json` and update three model fields: `model` (default), `agent.explore.model`, `agent.compaction.model`.

2. List every `.md` file in `.config/opencode/agents/`. For each agent file, update the `model:` and `variant:` lines in its YAML frontmatter (determined above). If a model has no variants, remove the `variant:` line entirely.

### Apply to Claude Code

The same agent `.md` files work, `variant:` maps to `effort`. Ensure the files are placed where Claude Code reads them, and update the `variant:` values using the mapping above.

### Apply to Codex

The same agent `.md` files work, `variant:` maps to `reasoning.effort`. Ensure the files are placed where Codex reads them, and update the `variant:` values using the mapping above.

## Verify

After all edits, grep for `model:` across all agent files and `"model"` across opencode.json. For each agent, verify:
- The model ID matches the approved mapping
- The variant (if present) is the correct highest variant for that model
- No variant line exists for models that don't support variants

Update the README.md agents table and architecture diagram to reflect the new models.

## Rules

1. Do not use bash or system-specific commands, use the agent's built-in file editing tools. This ensures portability across OpenCode, Claude Code, and Codex.
2. Always show the proposed mapping and get approval before editing.
3. If any file cannot be found or read, report it and stop.
4. Keep the mapping concise, one model per role with no fallback lists.
