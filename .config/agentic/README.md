# Agentic Configuration

Shared AI configuration for OpenCode and Claude Code. Model assignments live in `models.txt`. Run `setup/agentic.sh` to apply.

## Architecture

```text
~/.config/agentic/              # Shared (symlinked into both tools)
├── AGENTS.md                   # Startup instructions (CLAUDE.md symlinks to this)
├── agents/                     # Agent definitions (no model fields, injected at install)
│   ├── leader.md
│   ├── architect.md
│   ├── implementor.md
│   ├── clarifier.md
│   ├── tester.md
│   ├── designer.md
│   └── reviewer.md
├── instructions/               # Core instructions (loaded always)
│   ├── communication.md
│   ├── standards.md
│   └── versioning.md
├── tools/                      # Tool-specific usage guides
│   ├── github.md
│   ├── phabricator.md
│   ├── sentry.md
│   └── qmd.md
├── commands/                   # Workflow commands
├── skills/                     # Reusable skills
└── models.txt                  # Single source of truth for model assignments

.config/agentic/                # Project-local overrides and additions
├── commands/
│   └── create-phabricator-task.md
└── skills/
    └── create-phabricator-task/
        └── SKILL.md

~/.config/opencode/             # OpenCode-specific
├── opencode.json               # Config + agent models (injected by setup/agentic.sh)
└── tui.json                    # TUI keybinds

~/.claude/                      # Claude Code-specific
├── CLAUDE.md -> ~/.config/agentic/AGENTS.md
├── settings.json               # Claude Code settings
├── agents/                     # Agent files with injected model/effort
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
| `qmd.md` | `qmd` markdown search and semantic query usage |

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
