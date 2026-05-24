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
| Plan | `/plan` | `leader` | Assess scope, present approach, iterate until approved |
| Code | `/code` | `implementor` | Implement approved scope, show changes, iterate until approved |
| Test | `/test` | `tester` | Run tests and quality checks |
| Review | `/review` | `reviewer` | Code review for quality, security, best practices |

## Commands

| Command | Agent | Purpose |
| ------ | ----- | ------- |
| `/plan` | `leader` | Plan and scope task |
| `/code` | `implementor` | Implement changes |
| `/test` | `tester` | Run tests and checks |
| `/review` | `reviewer` | Review code quality |
| `/caveman` | - | Toggle ultra-compressed caveman communication mode |
| `/diagnose` | - | Structured 6-phase debugging loop for hard bugs and performance regressions |
| `/handoff` | - | Compact conversation into a handoff doc for another agent session |
| `/resolve-pr-comments` | - | Resolve `PR` review comments |
| `/review-pr` | - | Multi-agent `PR` review, can post inline comments |
| `/technical-analysis` | - | Structured technical analysis with method-level changes, notes, estimation, and architecture improvement |

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

| Skill | Command | Purpose |
| ----- | ------ | ------- |
| `resolve_pr_comments` | `/resolve-pr-comments` | Review `PR` comments, assess validity, make fixup commits, push, reply with `SHA` links |
| `review_pr` | `/review-pr` | Multi-agent `PR` review, spawns agents in parallel, can post inline comments |
| `technical_analysis` | `/technical-analysis` | Structured technical analysis with method-level changes, notes, estimation, and architecture deepening opportunities |
| `caveman` | `/caveman` | Ultra-compressed communication mode, cuts token usage by dropping filler while keeping technical accuracy |
| `diagnose` | `/diagnose` | Disciplined diagnosis loop: reproduce, minimise, hypothesise, instrument, fix, regression-test |
| `handoff` | `/handoff` | Compact conversation into a handoff document for fresh agent sessions |

## Agents

| Agent | Model | Purpose |
| ----- | ----- | ------- |
| `leader` | `github-copilot/gpt-5.4` | Orchestration, delegates only when needed |
| `clarifier` | `github-copilot/grok-code-fast-1` | Requirements clarification with branch-by-branch grilling |
| `architect` | `github-copilot/gpt-5.4-mini` | Architecture decisions |
| `designer` | `github-copilot/gpt-5.4-mini` | `UI`/`UX` design (frontend only) |
| `implementor` | `github-copilot/gpt-5.3-codex` | Bounded implementation |
| `tester` | `github-copilot/gpt-5.4-mini` | Tests and quality checks |
| `reviewer` | `github-copilot/gpt-5.4-mini` | Code review, security, performance analysis |
