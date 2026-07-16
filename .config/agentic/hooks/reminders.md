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
| `Grafana`/`Loki` links, "search Loki", "check Grafana", log queries | `~/.config/agentic/tools/grafana.md` |
| Searching markdown notes | `~/.config/agentic/tools/qmd.md` |

Rules, before and while you act:

- Read the matching file as your first tool call. Responding before reading it is WRONG.
- If an operation has a matching skill, run it, do not hand-roll the equivalent `gh`/`curl`/CLI commands.
- When a request could match more than one skill, for example a project skill in `~/.config/agentic/skills/` and a same-topic plugin/marketplace skill, prefer the project skill. It encodes this repo's specific workflow and trigger phrasing.
- When a skill or routed file defines a checklist, apply every item before finishing, never a subset.
