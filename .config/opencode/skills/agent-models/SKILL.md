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

## Research capabilities

After fetching models, collect objective capability data before ranking. Do not guess or use assumptions. The data source depends on which terminal tool you are configuring:

### For OpenCode

Fetch `https://models.dev/api.json` and filter by provider. Extract these fields per model:

- `context_window` (context size in tokens)
- `max_output` (max output tokens)
- `reasoning_options` (variants or effort levels supported)
- `pricing` (input cost per MTok, output cost per MTok)
- `npi` (npm/package info, indicates API compatibility type)
- `recommended` or `priority` tier if present

For opencode-go specifically, also fetch `https://opencode.ai/go` for rate limit data (requests per 5h).

### For Anthropic/Claude Code

Fetch model capabilities from Anthropic's official docs:
- Models overview: `https://docs.anthropic.com/en/docs/about-claude/models`
- Effort levels: `https://docs.anthropic.com/en/docs/build-with-claude/effort`
- Extract: context window, max output, effort levels supported, pricing

### For OpenAI/Codex

Fetch model capabilities from OpenAI's official docs:
- Reasoning models: `https://platform.openai.com/docs/guides/reasoning`
- Models list: `https://platform.openai.com/docs/models`
- Extract: reasoning effort levels, context window, pricing

### For other providers or when docs are unreachable

Use the rate limit table from `https://opencode.ai/go` as a cheapness proxy: higher request limits imply lower cost per call, which suits high-frequency roles like tester and clarifier.

### Presenting the proposal

When presenting the ranking proposal, cite the data used for each assignment. Show a table with per-model capability evidence next to each role assignment.

## Determine variants

After selecting models, determine the highest available variant per model. Do not guess, fetch the source of truth. The `variant:` field in agent YAML is OpenCode-specific. Other tools (Claude Code, Codex) use their own internal systems.

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

Use the capability data collected above to rank models. Do not guess or rely on general knowledge when ranking. Use the capability data collected above.

| Agent role | Priority | Data to use for ranking |
| leader, architect | Reasoning strength, context window | Sort by `context_window` descending, then by `reasoning_options` complexity. Larger context + more effort levels = better for planning. |
| implementor | Code generation quality | Prefer models tagged as code-optimized in models.dev metadata. Fallback: prefer OpenAI-compatible (codex-style) over Anthropic-compatible for code gen. |
| reviewer | Critical reasoning, analysis | Same as leader/architect. Must be a different vendor than implementor. |
| designer | Creative/UX reasoning | Prefer models with broader general knowledge. Context window is secondary. |
| tester, clarifier | Speed, reliability | Prefer models with higher rate limits for uninterrupted work. Still use a capable model, not the absolute cheapest. |
| default, explore, compaction | Speed, rate limits | Same as tester/clarifier. Prefer models with higher rate limits, but still capable enough for the task. |

When building the proposal, show a table with:
- Each role
- The proposed model
- The capability evidence from `models.dev` or the Go rate table
- A one-line reason (e.g. "largest context window", "highest rate limit", "different vendor from implementor")

Important: Do not assign the same model to adjacent pipeline roles (implementor + reviewer). Use different vendors so the review catches blind spots.

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
- Update the README.md or other documentation files mentioning agents, agents table, and architecture diagram to reflect the new models.

## Rules

1. Do not use bash or system-specific commands, use the agent's built-in file editing tools. This ensures portability across OpenCode, Claude Code, and Codex.
2. Always show the proposed mapping and get approval before editing.
3. If any file cannot be found or read, report it and stop.
4. Keep the mapping concise, one model per role with no fallback lists.
