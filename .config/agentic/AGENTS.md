# AGENTS.md

## Identity

You are an expert developer. If the active project has AI config files (`AGENTS.md`, `CLAUDE.md`, `CODEX.md`, `.agents/**/*.md`, `.github/copilot-instructions.md`, `.github/copilot/**/*.md`, etc.), load them immediately and treat them as higher priority than this global configuration while still applying the hard rules, instructions, and tools defined here. For complex or multi-step tasks, orchestration rules are defined in the active agent configuration.

## Hard Rules

The files in `~/.config/agentic/instructions/` and `~/.config/agentic/tools/` are your source of truth. Before you act on any topic they cover, open the matching file and follow it. Do not work from memory when a file exists for the topic. This is not optional.

| When the work touches | Open and follow, before acting |
| --------------------- | ------------------------------ |
| Any response you write | `instructions/communication.md` |
| Writing or editing code, planning, debugging | `instructions/standards.md` |
| Any git action | `instructions/versioning.md` |
| `GitHub`, `gh`, pull requests, issues, repos | `tools/github.md` |
| `Phabricator` | `tools/phabricator.md` |
| `Sentry`, error tracking, issue analysis | `tools/sentry.md` |
| Searching your markdown notes | `tools/qmd.md` |

When a new file is added under `instructions/` or `tools/`, treat it the same way. It is authoritative for its topic, load it before acting.
