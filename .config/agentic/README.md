# Agentic Configuration

Shared AI configuration for OpenCode and Claude Code. Model assignments live in `models.txt`. Run `setup/agentic.sh` to apply.

## Architecture

```text
~/.config/agentic/                 # Shared symlinked into both tools
├── AGENTS.md                      # Startup instructions, CLAUDE.md symlinks to this
├── agents/                        # Agent definitions, no model fields, injected at install
│   ├── leader.md
│   ├── architect.md
│   ├── implementor.md
│   ├── clarifier.md
│   ├── tester.md
│   ├── designer.md
│   └── reviewer.md
├── instructions/                  # Core instructions (loaded always)
│   ├── communication.md
│   ├── standards.md
│   └── versioning.md
├── tools/                         # Tool-specific usage guides
│   ├── github.md
│   ├── phabricator.md
│   ├── sentry.md
│   ├── grafana.md
│   └── qmd.md
├── hooks/                         # Injected every turn/message
│   ├── reminders.md               # Routing table, single source for both tools
│   ├── context-guard.sh           # Claude Code UserPromptSubmit hook
│   ├── webfetch-guard.sh          # Claude Code PreToolUse hook, blocks WebFetch when not needed
│   └── opencode-context-guard.js  # OpenCode plugin equivalent
├── commands/                      # Workflow commands
├── skills/                        # Reusable skills
└── models.txt                     # Single source of truth for model assignments

.config/agentic/                   # Project-local overrides and additions
├── commands/
│   └── <project-specific-command>.md
└── skills/
    └── <project-specific-skill>/
        └── SKILL.md

~/.config/opencode/                # OpenCode-specific
├── opencode.json                  # Config + agent models (injected by setup/agentic.sh)
└── tui.json                       # TUI keybinds

~/.claude/                         # Claude Code-specific
├── CLAUDE.md -> ~/.config/agentic/AGENTS.md
├── settings.json                  # Claude Code settings
├── agents/                        # Agent files with injected model/effort
├── rules/instructions/ -> ~/.config/agentic/instructions/
└── rules/tools/ -> ~/.config/agentic/tools/
```

## Workflow

| Phase | Command | Agent | Purpose |
| ----- | ------ | ----- | ------- |
| Scope | `/scope` | `leader` | Assess scope, present approach, iterate until approved |
| Code | `/code` | `implementor` | Implement approved scope, show changes, iterate until approved |
| Test | `/test` | `tester` | Run tests and quality checks |
| Review | `/review` | `reviewer` | Code review for quality, security, best practices |

## Instructions

| File | Purpose |
| ---- | ------- |
| `communication.md` | Communication style guidelines |
| `standards.md` | Core implementation rules, safety, error handling, debugging |
| `versioning.md` | `Git` conventions and commit rules |

## Tools

| File | Purpose |
| ---- | ------- |
| `github.md` | `GitHub CLI` commands and `PR` guidelines |
| `phabricator.md` | Phabricator `Conduit` API integration |
| `sentry.md` | Sentry error tracking and issue analysis |
| `grafana.md` | Grafana dashboard/log links, `logcli`/Loki only, no `curl`/`HTTP API` path |
| `qmd.md` | `qmd` markdown search and semantic query usage |

## Hooks

| File | Purpose |
| ---- | ------- |
| `reminders.md` | Routing table mapping topics to instruction/tool files, injected every turn |
| `context-guard.sh` | Claude Code `UserPromptSubmit` hook. Prints `reminders.md`, then warns if the session's transcript is large or idle (risk of an expensive prompt-cache rebuild) |
| `webfetch-guard.sh` | Claude Code `PreToolUse` hook (matcher: `WebFetch`). Denies fetches to self-hosted `Phabricator`/`Grafana` hostnames, a static `permissions.deny` domain rule can't match an arbitrary org hostname |
| `opencode-context-guard.js` | OpenCode plugin equivalent, same thresholds using the session API's exact token counts instead of a byte-size estimate. Also blocks `WebFetch` on all 4 hosts (regex covers self-hosted domains directly) |

## Skills

Skills are loaded by agents and triggered via commands.

### Workflow Skills

| Skill | Command | Purpose |
| ----- | ------ | ------- |
| `create_pr` | `/create-pr` | Create a `PR` with structured description, split commits, feature branch, auto-assign, and labels |
| `resolve_pr_comments` | `/resolve-pr-comments` | Review `PR` comments, assess validity, make fixup commits, push, reply with `SHA` links |
| `review_pr` | `/review-pr` | Multi-agent `PR` review, spawns agents in parallel, can post inline comments |

### Diagnostic Skills

| Skill | Command | Purpose |
| ----- | ------ | ------- |
| `diagnose` | `/diagnose` | Disciplined diagnosis loop: reproduce, minimise, hypothesise, instrument, fix, regression-test |
| `technical_analysis` | `/technical-analysis` | Structured technical analysis with method-level changes, notes, estimation, and architecture deepening opportunities |

### Design Skills

| Skill | Command | Purpose |
| ----- | ------ | ------- |
| `interface_design` | Loaded by the `designer` agent, no dedicated command | Craft-first UI design guidance: visual hierarchy, design tokens, states, component checklist |

### Utility Skills

| Skill | Command | Purpose |
| ----- | ------ | ------- |
| `caveman` | `/caveman` | Ultra-compressed communication mode, cuts token usage by dropping filler while keeping technical accuracy |
| `handoff` | `/handoff` | Compact conversation into a handoff document for fresh agent sessions |
| `agent_models` | `/agent-models` | Research, rank, and apply model updates across all agents and configs for any provider |

### Task Management Skills

| Skill | Command | Purpose |
| ----- | ------- | ------- |
| `create_phabricator_task` | `/create-phabricator-task` | Create and edit Phabricator tasks via the `Conduit` API |

## Agents

Agent system prompts live in `agents/`. Model assignments are in `models.txt` as the single source of truth. `setup/agentic.sh` injects them into each tool:

- **OpenCode**: built into `opencode.json` via the `agent` section.
- **Claude Code**: injected into each agent YAML frontmatter under `~/.claude/agents/`.

Built-in agents: `explore` and `compaction` use lowest-cost capable models.

Refer to `models.txt` for current assignments.
