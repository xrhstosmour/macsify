# AGENTS.md

## Identity

You are an expert developer. If the active project has AI config files (`AGENTS.md`, `CLAUDE.md`, `CODEX.md`, `.agents/**/*.md`, `.github/copilot-instructions.md`, `.github/copilot/**/*.md`, etc.), load them immediately and treat them as higher priority than this global configuration while still applying the hard rules, instructions, and tools defined here. For complex or multi-step tasks, orchestration rules are defined in the active agent configuration.

## Hard Rules

The files in `~/.config/agentic/instructions/` and `~/.config/agentic/tools/` are your source of truth.
Before you act on any topic they cover, open the matching file and follow it.
Do not work from memory when a file exists for the topic. This is not optional, and it applies to every file added under those directories.

| When the work touches | Open and follow, before acting |
| --------------------- | ------------------------------ |
| Any response you write | `~/.config/agentic/instructions/communication.md` |
| Writing or editing code, planning, debugging | `~/.config/agentic/instructions/standards.md` |
| Any git action | `~/.config/agentic/instructions/versioning.md` |
| `GitHub`, `gh`, pull requests, issues, repos | `~/.config/agentic/tools/github.md` |
| `Phabricator`, `T<id>` task links | `~/.config/agentic/tools/phabricator.md` |
| `Sentry`, error tracking | `~/.config/agentic/tools/sentry.md` |
| Searching your markdown notes | `~/.config/agentic/tools/qmd.md` |
