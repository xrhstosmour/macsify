# OpenCode Configuration

Minimal specialist setup for pragmatic software development.

## Architecture

```text
~/.config/opencode/           # BASE CONFIG
├── opencode.json             # Main configuration
├── AGENTS.md                 # Startup instructions
├── context/                  # Base context (loaded always)
│   ├── communication.md
│   ├── knowledge.md
│   ├── rules.md
│   ├── versioning.md
│   └── tools/
│       ├── github.md
│       ├── phabricator.md
│       └── sentry.md
├── commands/                 # Workflow commands
├── agents/                   # Agent definitions
└── skills/                   # Reusable skills
```

## Workflow

| Phase | Command | Agent | Purpose |
| ----- | ------ | ----- | ------- |
| Scope | `/scope` | `leader` | Assess scope, present approach, iterate until approved |
| Code | `/code` | `implementor` | Implement approved scope, show changes, iterate until approved |
| Test | `/test` | `tester` | Run tests and quality checks |
| Review | `/review` | `reviewer` | Code review for quality, security, best practices |

## Commands

### PR Management

| Command | Purpose |
| ------- | ------- |
| `/create-pr` | Create a `PR` with structured description, split commits, feature branch, auto-assign, and labels |
| `/review-pr` | Multi-agent `PR` review, spawns agents in parallel, can post inline comments |
| `/resolve-pr-comments` | Resolve `PR` review comments, make fixup commits, push, reply with `SHA` links |

### Diagnosis & Analysis

| Command | Purpose |
| ------- | ------- |
| `/diagnose` | Structured 6-phase debugging loop for hard bugs and performance regressions |
| `/technical-analysis` | Structured technical analysis with method-level changes, notes, estimation, and architecture improvement |

### Utility

| Command | Purpose |
| ------- | ------- |
| `/caveman` | Toggle ultra-compressed caveman communication mode |
| `/handoff` | Compact conversation into a handoff doc for another agent session |

## Context Files

| File | Purpose |
| ---- | ------- |
| `communication.md` | Communication style guidelines |
| `knowledge.md` | Tools and knowledge base info |
| `rules.md` | Core implementation rules, safety, error handling, debugging |
| `versioning.md` | `Git` conventions and commit rules |
| `tools/github.md` | `GitHub CLI` commands and `PR` guidelines |
| `tools/phabricator.md` | Phabricator `Conduit` API integration |
| `tools/sentry.md` | Sentry error tracking and issue analysis |

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
| `agent_models` | `/agent-models` | Research, rank, and apply model updates across all agents and opencode.json for any provider |

## Agents

| Agent | Model | Variant | Purpose |
| ----- | ----- | ------- | ------- |
| `leader` | `opencode-go/deepseek-v4-pro` | `max` | Orchestration, delegates only when needed |
| `clarifier` | `opencode-go/deepseek-v4-flash` | `max` | Requirements clarification |
| `architect` | `opencode-go/deepseek-v4-pro` | `max` | Architecture decisions |
| `designer` | `opencode-go/mimo-v2.5` | `high` | `UI`/`UX` design (frontend only) |
| `implementor` | `opencode-go/deepseek-v4-pro` | `max` | Bounded implementation with TDD vertical slices |
| `tester` | `opencode-go/deepseek-v4-flash` | `max` | Tests and quality checks |
| `reviewer` | `opencode-go/mimo-v2.5-pro` | `high` | Code review, security, performance analysis |
