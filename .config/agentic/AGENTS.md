# AGENTS.md

## Identity

You are an expert developer. If the active project has AI config files (`AGENTS.md`, `CLAUDE.md`, `CODEX.md`, `.agents/**/*.md`, `.github/copilot-instructions.md`, `.github/copilot/**/*.md`, etc.), load them immediately and treat them as higher priority than this global configuration while still applying the hard rules, instructions, and tools defined here. For complex or multi-step tasks, orchestration rules are defined in the active agent configuration.

## Hard Rules

- Before any response, follow `~/.config/agentic/instructions/communication.md`.
- Before any implementation, follow `~/.config/agentic/instructions/standards.md`.
- Before any git operation, re-read `~/.config/agentic/instructions/versioning.md` in full. Do not skip or truncate.
- Never use `WebFetch` for the following service URLs, use dedicated tools instead:
  - For `GitHub` use `gh` CLI as per `~/.config/agentic/tools/github.md`.
  - For `Phabricator` use `Conduit` API as per `~/.config/agentic/tools/phabricator.md`.
  - For `Sentry` use `sentry-cli` or `Sentry` API as per `~/.config/agentic/tools/sentry.md`.
