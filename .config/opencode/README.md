# OpenCode Configuration

Minimal specialist setup for pragmatic software development.

## Architecture

```text
~/.config/opencode/           # BASE CONFIG
├── opencode.json             # Main configuration
├── AGENTS.md                 # Startup instructions
├── context/                  # Base context (loaded always)
│   ├── communication.md
│   ├── github.md
│   ├── knowledge.md
│   ├── models.md
│   ├── preferences.md
│   ├── rules.md
│   └── versioning.md
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
| `/resolve` | - | Resolve `PR` review comments |

## Context Files

| File | Purpose |
| ---- | ------- |
| `communication.md` | Communication style guidelines |
| `github.md` | `GitHub CLI` commands and `PR` guidelines |
| `knowledge.md` | Tools and knowledge base info |
| `models.md` | Model routing, selection by task, escalation path |
| `preferences.md` | Writing and formatting preferences |
| `rules.md` | Core implementation rules, safety, error handling, debugging |
| `versioning.md` | `Git` conventions and commit rules |

## Skills

Skills are loaded by agents and triggered via commands.

| Skill | Command | Purpose |
| ----- | ------ | ------- |
| `resolve_pr_comments` | `/resolve` | Review `PR` comments, assess validity, plan fixes, make fixup commits, push, reply with `SHA` links |

## Agents

| Agent | Model | Purpose |
| ----- | ----- | ------- |
| `leader` | `github-copilot/gpt-5` | Orchestration, delegates only when needed |
| `clarifier` | `github-copilot/gpt-5-mini` | Requirements clarification |
| `architect` | `github-copilot/gpt-5.4` | Architecture decisions |
| `designer` | `github-copilot/gpt-5-mini` | `UI`/`UX` design (frontend only) |
| `implementor` | `github-copilot/gpt-5.3-codex` | Bounded implementation |
| `tester` | `github-copilot/gpt-5.2-codex` | Tests and quality checks |
| `reviewer` | `github-copilot/gpt-5.4` | Code review |
