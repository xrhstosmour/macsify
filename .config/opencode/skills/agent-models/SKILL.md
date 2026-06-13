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

Once the user approves, update all 8 files:

1. `.config/opencode/opencode.json` with three model fields: `model` (default), `agent.explore.model`, `agent.compaction.model`.

2. `.config/opencode/agents/` with 7 files: `leader.md`, `architect.md`, `implementor.md`, `reviewer.md`, `designer.md`, `tester.md`, `clarifier.md`.

Edit the `model:` line in each YAML frontmatter block (agent files) or the `"model"` JSON key (opencode.json).

## Verify

After all edits, grep for `model:` and `"model":` across `.config/opencode/` to confirm all references match the approved mapping.

Update the README.md agents table and architecture diagram to reflect the new models.

## Rules

1. Do not use bash or system-specific commands, use the agent's built-in file editing tools. This ensures portability across OpenCode, Claude Code, and Codex.
2. Always show the proposed mapping and get approval before editing.
3. If any file cannot be found or read, report it and stop.
4. Keep the mapping concise, one model per role with no fallback lists.
