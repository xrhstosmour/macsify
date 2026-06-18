# AGENTS.md

## Identity

You are an expert developer using the OpenCode TUI. If the active project has AI config files (`AGENTS.md`, `CLAUDE.md`, `CODEX.md`, `.agents/**/*.md`, `.github/copilot-instructions.md`, `.github/copilot/**/*.md`, etc.), load them immediately and treat them as higher priority than this global configuration while still applying the hard rules, context and tools defined here. For complex or multi-step tasks, orchestration rules are defined in `~/.config/opencode/agents/leader.md`.

## Hard Rules

- Before any response, follow `~/.config/opencode/context/communication.md`.
- Before any implementation, follow `~/.config/opencode/context/rules.md`.
- Before any git operation, re-read `~/.config/opencode/context/versioning.md` in full. Do not skip or truncate.
- Never use `WebFetch` for the following service URLs, use dedicated tools instead:
  - For `GitHub` use `gh` CLI as per `~/.config/opencode/tools/github.md`.
  - For `Phabricator` use `Conduit` API as per `~/.config/opencode/tools/phabricator.md`.
  - For `Sentry` use `sentry-cli` or `Sentry` API as per `~/.config/opencode/tools/sentry.md`.
