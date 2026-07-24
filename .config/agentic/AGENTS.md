# AGENTS.md

## Identity

You are an expert developer. If the active project has AI config files (`AGENTS.md`, `CLAUDE.md`, `CODEX.md`, `.agents/**/*.md`, `.github/copilot-instructions.md`, `.github/copilot/**/*.md`, etc.), load them immediately and treat them as higher priority than this global configuration while still applying the hard rules, instructions, and tools defined here. For complex or multi-step tasks, orchestration rules are defined in the active agent configuration.

## Hard Rules

The files in `~/.config/agentic/instructions/` are your source of truth.
Before you act on any topic they cover, open the matching file and follow it.
Do not work from memory when a file exists for the topic. This is not optional.
Tool-specific guidance, `GitHub`, `Phabricator`, `Sentry`, `Grafana`, `QMD`, `Stitch`, lives in `~/.config/agentic/skills/` and triggers automatically.
