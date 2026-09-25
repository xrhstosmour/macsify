---
name: agent-models
description: >
   Research available models for any provider, rank them per agent role, and update
   all model references across agent configs and opencode.json. Works with OpenCode,
   Claude Code, Codex, Copilot CLI, and any agentic environment.
---

# Agent Models

## When to use

- `/agent-models`
- User says "update models", "new models", "switch models", or "change provider".
- Models are outdated or a provider has released new options.
- User wants to evaluate a different provider for one or more agent roles.

## Provider selection

Ask user to pick a provider:

1. opencode, free Zen models
2. opencode-go, paid subscription
3. github-copilot
4. claude-code
5. custom, user pastes their own model table

## Research models

For known providers, attempt to fetch model info from these sources:

| Provider | URLs to try |
|----------|---------------|
| opencode | `https://opencode.ai/zen/v1/models` for available models, `https://opencode.ai/docs/zen/` for pricing and docs |
| opencode-go | `https://opencode.ai/go` for rate limits, `https://opencode.ai/docs/go/` for pricing and docs |
| github-copilot | `https://docs.github.com/en/copilot/reference/ai-models/supported-models` |
| claude-code | `https://docs.anthropic.com/en/docs/about-claude/models` |

For each model found, extract Model name, Provider, Rate limits, and Quality tier if available.

If web fetch fails or data is incomplete, ask the user to paste the model table directly, with name, provider, and rate limits columns.

For `custom`, ask user to paste a table with columns: Model, Provider, requests per 5h, requests per week, requests per month.

## Research capabilities

After fetching models, collect objective capability data before ranking. Do not guess or use assumptions. The data source depends on which terminal tool you are configuring:

### For OpenCode

Fetch `https://models.dev/api.json` and filter by provider. Extract these fields per model:

- `context_window`, context size in tokens
- `max_output`, max output tokens
- `reasoning_options`, variants or effort levels supported
- `pricing`, input cost per MTok, output cost per MTok
- `npi`, npm/package info, indicates API compatibility type
- `recommended` or `priority` tier if present

For opencode, fetch `https://opencode.ai/zen/v1/models` for the list of free models, IDs ending in `-free`. All free models have zero cost. For opencode-go specifically, also fetch `https://opencode.ai/go` for rate limit data, requests per 5h.

### For Anthropic/Claude Code

Fetch model capabilities from Anthropic's official docs:
- Models overview: `https://docs.anthropic.com/en/docs/about-claude/models`
- Effort levels: `https://docs.anthropic.com/en/docs/build-with-claude/effort`
- Extract: context window, max output, effort levels supported, pricing

### For Codex

Do not use the generic OpenAI platform docs, `platform.openai.com/...`, Codex CLI's recommended/available models and reasoning-effort levels are documented separately from the raw API catalog and differ from it, for example the `-codex`-suffixed models from the raw API are not what Codex CLI's own docs currently recommend. Fetch straight from Codex's own docs instead:
- `https://developers.openai.com/codex/subagents.md`, section "Choosing models and reasoning". Append `.md` to any `developers.openai.com/codex/*` page URL to fetch the raw markdown source directly, bypassing JS rendering and avoiding summarization loss from a fetch tool that pipes the page through another model, `WebFetch`-style tools do this by default, prefer `curl`/`Read` on the `.md` URL when precision matters.
- Cross-check available model IDs exist against `https://models.dev/api.json`, provider key `openai`.
- Extract: the recommended model per workload as stated in the "Model choice" section, this rotates as OpenAI ships new generations, don't hardcode specific names from this skill file, always re-fetch, and the `model_reasoning_effort` levels from the "Reasoning effort" section.

### For Copilot CLI

Fetch `https://models.dev/api.json`, provider key `github-copilot`. Copilot CLI selects models by ID string, for example `claude-sonnet-4.5`, `gpt-5.6`, spanning multiple vendors through the same subscription. Prefer a model ID tagged `(latest)` in its `models.dev` display name when one exists for the vendor/tier you want, that tag tracks the newest patch the same way Claude Code's own bare `sonnet`/`opus`/`haiku` aliases do, a hard version-pinned entry, a specific dot-release with no `(latest)` tag, is a deliberate opt-in to a fixed release and goes stale as newer ones ship.

### For other providers or when docs are unreachable

Use the rate limit table from `https://opencode.ai/go` as a cheapness proxy: higher request limits imply lower cost per call, which suits high-frequency roles like tester and clarifier.

### Presenting the proposal

When presenting the ranking proposal, cite the data used for each assignment. Show a table with per-model capability evidence next to each role assignment.

## Determine variants

After selecting models, determine the highest available variant per model. Do not guess, fetch the source of truth. The `variant:` field in agent YAML is OpenCode-specific. Other tools, Claude Code and Codex, use their own internal systems.

### Running Through OpenCode

Fetch `https://models.dev/api.json`, filter by provider, `opencode`, `opencode-go`, `github-copilot`, `anthropic`, `openai`, etc., and check each model's `reasoning_options` array:

- Empty, `[]`, → no variants, then remove `variant:` line from agent YAML
- Non-empty → use the highest/latest value from the array of strings. For example, `["max", "xhigh", "high"]` → use `max`. If the array is `["low", "medium", "high"]`, use `high`. If the array is `["none", "minimal", "low", "medium", "high"]`, use `high`.

### Running Through Claude Code

Claude Code uses the `effort` parameter as the equivalent of variants. Fetch available models and their effort levels from `https://docs.anthropic.com/en/docs/build-with-claude/effort`.

Available levels: `low`, `medium`, `high` as the default, `xhigh`, `max`. Not all models support all levels. Haiku models do not support effort at all, omit the `effort:` field for those.

Effort comes first per agent role, then model selection:

| Role | Effort recommendation |
|------|----------------------|
| leader | `high` for orchestration, `xhigh` only if the task involves long-horizon multi-step reasoning |
| implementor | `high` for code generation quality |
| reviewer | `high` for critical analysis |
| architect, designer | `high` for design/analysis |
| clarifier | `medium` for fast exploration |
| tester | `medium`, or omit for the model default, for speed |

### Running Through Codex

Codex uses the `model_reasoning_effort` field in the generated agent `.toml` file as the equivalent of variants. Fetch current levels and per-role guidance from `https://developers.openai.com/codex/subagents.md`, fetch the raw `.md` URL directly, see the note under "For Codex" above, section "Reasoning effort, `model_reasoning_effort`".

Available levels: `low`, `medium`, `high`, `xhigh`, `max`, `ultra`. Model- and surface-dependent which are supported. Codex's own docs explicitly call out `high` for reviewer/security-focused roles, the same bump Claude Code's `reviewer` already gets.

### Running Through Copilot CLI

Copilot CLI's custom agent files, `.agent.md` files, have no separate reasoning-effort or variant field, only `model`. Leave effort out of the `copilot:` rows in `models.txt` entirely, the same way Claude Code's Haiku-based `tester` already omits `effort:`.

### Other Environments And Custom Providers

Ask the user which variants/effort levels each model supports.

## Rank per role

Rank models from the capability data collected above. Do not guess or rely on general knowledge when ranking.

| Agent role | Priority | Data to use for ranking |
| leader, architect | Reasoning strength, context window | Sort by `context_window` descending, then by `reasoning_options` complexity. Larger context + more effort levels = better for planning. |
| implementor | Code generation quality | Prefer models tagged as code-optimized in models.dev metadata. If nothing carries that tag, rank by the provider's own published coding guidance fetched in "Research capabilities", never by a general impression of which vendor writes better code. |
| reviewer | Critical reasoning, analysis | Must be a different vendor or tier than implementor so the review catches blind spots. In single-provider setups, use a higher tier model. |
| designer | Creative/UX reasoning | Prefer models with broader general knowledge. Context window is secondary. |
| tester, clarifier | Speed, reliability | Prefer models with higher rate limits or lower cost for uninterrupted work. Still use a capable model, not the absolute cheapest. |
| default, explore, compaction | Speed, rate limits | Same as tester/clarifier. Prefer models with higher rate limits, but still capable enough for the task. |

### Cost consciousness

Do not overuse expensive models. In a single-provider setup, for example Anthropic-only, assign the most expensive model, such as Opus, to at most one role, typically reviewer. Everything else uses the mid-tier model, such as Sonnet. Only use the cheapest model, such as Haiku, for roles where speed matters more than quality, tester and compaction.

When building the proposal, show a table with:
- Each role
- The proposed model
- The capability evidence from `models.dev` or the Go rate table
- A one-line reason, such as "largest context window", "highest rate limit", or "different vendor from implementor"

## Apply

Once the user approves, update `.config/agentic/models.txt`. This is the single source of truth for all model assignments. `setup/agentic.sh` reads it and injects models into both tools.

### models.txt format

```
# Format: <tool>:<agent>:<field>:<value>
# Use '-' as value when a field does not apply.

# OpenCode
opencode:leader:model:<provider>/<model-id>
opencode:leader:variant:max
opencode:explore:model:<provider>/<cheaper-model-id>
opencode:explore:variant:-

# Claude Code
claude:leader:model:<alias>
claude:leader:effort:medium
claude:tester:model:<cheaper-alias>

# Codex
codex:leader:model:<model-id>
codex:leader:effort:medium
codex:tester:model:<cheaper-model-id>
codex:tester:effort:low

# Copilot CLI
copilot:leader:model:<vendor-model-id>
copilot:tester:model:<cheaper-vendor-model-id>
```

### Fields per tool

| Tool | Fields | Lines per agent |
|------|--------|----------------|
| OpenCode | `model`, `variant`, use `-` if none | `opencode:<agent>:model:...` + `opencode:<agent>:variant:...` |
| Claude Code | `model`, use aliases `sonnet`, `opus`, `haiku`, not full IDs, `effort`, omit the line entirely if not supported, such as Haiku | `claude:<agent>:model:...` + optional `claude:<agent>:effort:...` |
| Codex | `model`, full model ID, e.g. `gpt-5.6`, `effort` via `model_reasoning_effort`, omit the line to use the model's default | `codex:<agent>:model:...` + optional `codex:<agent>:effort:...` |
| Copilot CLI | `model`, full model ID, e.g. `claude-sonnet-4.5`, only, no effort field exists | `copilot:<agent>:model:...` |

### Apply steps

1. Read `.config/agentic/models.txt`.
2. Update the `<tool>:` lines for whichever tools the user is targeting, `opencode`, `claude`, `codex`, or `copilot`, with the approved model assignments.
3. Write the updated file.
4. Run `setup/agentic.sh` to inject models into every configured tool. Nothing else to edit.

### Verify

After all edits:

- Read `.config/agentic/models.txt` and verify every agent has a matching `<tool>:<agent>:model:` line for each tool being updated.
- Verify the OpenCode `explore` and `compaction` entries are present, if touching the OpenCode section.
- Run `bash setup/agentic.sh` and confirm it completes without errors.
- Update documentation files, README.md and architecture diagrams, to reflect the new models.

## Rules

1. Edit `.config/agentic/models.txt` with the agent's built-in file editing tools, not `sed`/`awk`/system-specific commands, to keep the mapping change portable across OpenCode, Claude Code, Codex, and Copilot CLI. Running `setup/agentic.sh` afterward to inject the mapping is still required and isn't covered by this rule.
2. Always show the proposed mapping and get approval before editing.
3. If any file cannot be found or read, report it and stop.
4. Keep the mapping concise, one model per role with no fallback lists.
