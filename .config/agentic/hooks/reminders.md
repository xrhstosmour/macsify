# Reminders

Match what you are about to do to this table:

| When the work touches | Read this file first |
| --------------------- | -------------------- |
| Any response you write | `~/.config/agentic/instructions/communication.md` |
| Writing, editing, planning, debugging | `~/.config/agentic/instructions/standards.md` |
| Any git action | `~/.config/agentic/instructions/versioning.md` |
| `GitHub`, `gh`, pull requests, issues | `~/.config/agentic/tools/github.md` |
| `Phabricator`, `T<id>` links | `~/.config/agentic/tools/phabricator.md` |
| `Sentry`, error tracking | `~/.config/agentic/tools/sentry.md` |
| Searching markdown notes | `~/.config/agentic/tools/qmd.md` |

Rules, before and while you act:

- Read the matching file as your first tool call. Responding before reading it is WRONG.
- If an operation has a matching skill, run it, do not hand-roll the equivalent `gh`/`curl`/CLI commands.
- When a skill or routed file defines a checklist, apply every item before finishing, never a subset.
