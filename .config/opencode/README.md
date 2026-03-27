# OpenCode Configuration

Minimal specialist setup for pragmatic software development.

## Workflow

1. `/plan` - review plan with user, iterate until approved
2. `/code` - show changes, iterate until approved
3. `/test` - run tests and quality checks (standalone too)
4. `/review` - code review (standalone too)

## Commands

1. `/resolve` - resolve `PR` review comments using `resolve_pr_comments` skill

## Skills

Skills are loaded by agents and can be triggered via commands (e.g., `/resolve`).

| Skill | Command | Purpose |
| --- | --- | --- |
| `resolve_pr_comments` | `/resolve` | Review `PR` comments, assess validity, plan fixes with user, make fixup commits, push, reply with `SHA` links and re-request reviews. |

## Agents

| Agent | Purpose |
| --- | --- |
| `leader` | Orchestration, delegates only when needed |
| `clarifier` | Requirements clarification |
| `architect` | Architecture decisions |
| `designer` | `UI`/`UX` design (frontend only) |
| `implementor` | Bounded implementation |
| `tester` | Tests and quality checks |
| `reviewer` | Code review |

## Context

- `communication.md` - Communication style
- `knowledge.md` - Knowledge context
- `preferences.md` - Writing and formatting preferences
- `rules.md` - Implementation rules
- `versioning.md` - Versioning and `Git` commands and guidelines
- `github.md` - `GitHub` commands and guidelines
