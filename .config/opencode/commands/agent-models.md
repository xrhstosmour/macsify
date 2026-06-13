---
description: Research available models for a provider, rank per agent role, and update all configs
---

# Agent Models

Research, rank, and apply model updates across all agent configs and opencode.json.

## Entry Criteria

- User wants to update or switch models across agents.
- User says "update models", "new models", "switch models", or "change provider".

## Process

Follow the agent-models skill:

1. Ask user to pick a provider (opencode-go, github-copilot, claude-code, custom).
2. Fetch model data from provider docs or ask user to paste a table.
3. Rank models per agent role by quality and rate limits.
4. Show proposed mapping and get approval.
5. Edit all 8 config files to apply.
6. Verify with a grep check.
