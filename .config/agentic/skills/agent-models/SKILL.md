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

Available levels: `low`, `medium`, `high` (default), `xhigh`, `max`. Not all models support all levels. Haiku models do not support effort at all, omit the `effort:` field for those.

Effort comes first per agent role, then model selection:

| Role | Effort recommendation |
|------|----------------------|
| leader | `high` for orchestration, `xhigh` only if the task involves long-horizon multi-step reasoning |
| implementor | `high` for code generation quality |
| reviewer | `high` for critical analysis |
| architect, designer | `high` for design/analysis |
| clarifier | `medium` for fast exploration |
| tester | `medium` or omit (model default) for speed |

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
| reviewer | Critical reasoning, analysis | Must be a different vendor or tier than implementor so the review catches blind spots. In single-provider setups, use a higher tier model. |
| designer | Creative/UX reasoning | Prefer models with broader general knowledge. Context window is secondary. |
| tester, clarifier | Speed, reliability | Prefer models with higher rate limits or lower cost for uninterrupted work. Still use a capable model, not the absolute cheapest. |
| default, explore, compaction | Speed, rate limits | Same as tester/clarifier. Prefer models with higher rate limits, but still capable enough for the task. |

### Cost consciousness

Do not overuse expensive models. In a single-provider setup (e.g. Anthropic-only), assign the most expensive model (e.g. Opus) to at most one role, typically reviewer. Everything else uses the mid-tier model (e.g. Sonnet). Only use the cheapest model (e.g. Haiku) for roles where speed matters more than quality (tester, compaction).

When building the proposal, show a table with:
- Each role
- The proposed model
- The capability evidence from `models.dev` or the Go rate table
- A one-line reason (e.g. "largest context window", "highest rate limit", "different vendor from implementor")

Important: Do not assign the same model to adjacent pipeline roles (implementor + reviewer). Use different vendors so the review catches blind spots.

## Apply

Once the user approves, update `.config/agentic/models.txt`. This is the single source of truth for all model assignments. `setup/agentic.sh` reads it and injects models into both tools.

### models.txt format

```
# Format: <tool>:<agent>:<field>:<value>
# Use '-' as value when a field does not apply.

# OpenCode
opencode:leader:model:opencode-go/deepseek-v4-pro
opencode:leader:variant:max
opencode:explore:model:opencode/big-pickle
opencode:explore:variant:-

# Claude Code
claude:leader:model:sonnet
claude:leader:effort:medium
claude:tester:model:haiku
```

### Fields per tool

| Tool | Fields | Lines per agent |
|------|--------|----------------|
| OpenCode | `model`, `variant` (use `-` if none) | `opencode:<agent>:model:...` + `opencode:<agent>:variant:...` |
| Claude Code | `model` (use aliases: `sonnet`, `opus`, `haiku`, not full IDs), `effort` (omit line entirely if not supported, e.g. Haiku) | `claude:<agent>:model:...` + optional `claude:<agent>:effort:...` |

### Apply steps

1. Read `.config/agentic/models.txt`.
2. Update the `opencode:` and `claude:` lines with the approved model assignments.
3. Write the updated file.
4. Run `setup/agentic.sh` to inject models into both tools. NOTHING else to edit.

### Verify

After all edits:

- Read `.config/agentic/models.txt` and verify every agent has matching `opencode:<agent>:model:` and `claude:<agent>:model:` lines.
- Verify the OpenCode `explore` and `compaction` entries are present.
- Run `bash setup/agentic.sh` and confirm it completes without errors.
- Update documentation files (README.md, architecture diagrams) to reflect the new models.

## Rules

1. Do not use bash or system-specific commands, use the agent's built-in file editing tools. This ensures portability across OpenCode, Claude Code, and Codex.
2. Always show the proposed mapping and get approval before editing.
3. If any file cannot be found or read, report it and stop.
4. Keep the mapping concise, one model per role with no fallback lists.
