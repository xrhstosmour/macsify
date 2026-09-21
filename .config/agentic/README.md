# Agentic Configuration

Shared AI configuration for OpenCode, Claude Code, Codex, and Copilot CLI. Model assignments live in `models.txt`. Run `setup/agentic.sh` to apply.

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
├── hooks/                         # Injected every turn/message
│   ├── context-guard.sh           # Claude Code UserPromptSubmit hook
│   ├── webfetch-guard.sh          # Claude Code PreToolUse hook, blocks WebFetch when not needed
│   ├── bash-output-cap.sh         # Claude Code PreToolUse hook, caps unbounded Bash stdout
│   └── opencode-context-guard.js  # OpenCode plugin equivalent, includes the same Bash output cap
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
└── rules/instructions/ -> ~/.config/agentic/instructions/

~/.codex/                          # Codex CLI-specific
├── AGENTS.md -> ~/.config/agentic/AGENTS.md
├── skills/ -> ~/.config/agentic/skills
├── prompts/ -> ~/.config/agentic/commands
├── agents/                        # Generated *.toml, one per agents/*.md
├── hooks.json                     # Generated, see Hooks below
└── config.toml                    # MCP servers, `codex mcp add` writes here

~/.copilot/                        # Copilot CLI-specific
├── copilot-instructions.md -> ~/.config/agentic/AGENTS.md
├── skills/ -> ~/.config/agentic/skills
├── agents/                        # Generated *.agent.md, one per agents/*.md
├── hooks/agentic.json             # Generated, see Hooks below
└── mcp-config.json                # MCP servers, `copilot mcp add` writes here
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
| `standards.md` | Core implementation rules, safety, error handling |
| `versioning.md` | `Git` conventions and commit rules |

## Hooks

| File | Wired into | Purpose |
| ---- | ---------- | ------- |
| `context-guard.sh` | Claude Code, Codex, Copilot CLI | `UserPromptSubmit` hook. When the session's transcript is large or idle, instructs the model to inform the user and advise compacting, handoff, or a new session, it never invokes anything itself. A cooldown marker in the OS temp directory stops it from re-nudging every single turn. Confirmed working for Codex, plain `stdout` on `UserPromptSubmit` is documented as added developer context (`developers.openai.com/codex/hooks.md`). Wired into Copilot CLI too, but unverified in practice, its own hooks reference notes that command-hook output on this event may be dropped outside SDK-programmatic hooks, empirically test before relying on it there, drop the entry if it turns out inert |
| `webfetch-guard.sh` | Claude Code, Copilot CLI | `PreToolUse` hook, matcher: `WebFetch`. Denies fetches to `github.com`, `sentry.io`, and self-hosted `Phabricator`/`Grafana` hostnames with an actionable reason pointing at the right skill/CLI/MCP. `github.com`/`sentry.io` are also in `claude/settings.json`'s static `permissions.deny` as a fallback; self-hosted `Phabricator`/`Grafana` hostnames can't be expressed as a static domain rule, so those rely on this hook alone. Not wired into Codex, it has no built-in URL-fetch tool to gate, its `web_search` tool returns query snippets rather than a fetched URL. Copilot CLI reads it via a PascalCase `PreToolUse` event name, which opts into its documented Claude-format matcher/payload compatibility mode, no script changes needed |
| `auto-session-title.sh` | Claude Code only | `UserPromptSubmit` hook, generates a session title via a headless `claude -p` call and writes Claude Code's own `custom-title` transcript format. Fundamentally Claude-specific, not portable |
| `documentation-guard.sh` | Claude Code only | `PreToolUse` hook, matcher: `Write`. Blocks creating a new `.md` file outside an allowlist (`README`/`CLAUDE`/`AGENTS`/`CODEX`/`CONTRIBUTING`/`SKILL.md`, or paths under `.config/agentic/`, `~/.claude/{agents,commands,plans,skills}`, `~/.claude/rules/instructions/`, `~/.claude/projects/*/memory/`), keeping stray documentation files from accumulating in project directories |
| `herdr-workspace-router.sh` | Claude Code | `SessionStart` hook. Routes a new `herdr` pane into a `herdr` space (workspace) matching its git repo, since `herdr`'s own workspaces are explicit containers, not auto-derived per repo, so a session started in a different repo than the current space's origin otherwise stays grouped with it. Uses `herdr`'s existing `pane.get`/`workspace.list`/`pane.move` socket API to move the pane without killing its process, no `herdr` core change needed. Only acts on a pane already running an agent, opening a plain shell tab with no repository never triggers this at all, and a cwd that isn't a git repo is a no-op. Tracks repo-to-workspace mappings itself in `~/.config/herdr/workspace-router-map.json`, since `herdr`'s public API doesn't expose git identity for ordinary workspaces, shared with the OpenCode equivalent in `opencode-context-guard.js` via a portable `mkdir`-based lock (no `fcntl.flock` in Node). Kept separate from `herdr`'s own managed `~/.claude/hooks/herdr-agent-state.sh`, which gets overwritten on integration updates |
| `bash-output-cap.sh` | Claude Code | `PreToolUse` hook, matcher: `Bash`. Rewrites unbounded commands to redirect their combined stdout+stderr to a temp file and `head -c 20000` it before execution, this is the only stage that can affect Bash output at all, `PostToolUse` can't rewrite a tool's result. Uses a brace group and a temp file rather than piping straight through `head`, a pipe would run the command in a subshell (breaking `cd`/`export` persistence across calls) and risk `SIGPIPE`-killing it mid-run once `head` has its bytes. Never sets `permissionDecision`, so the rewritten command still goes through the normal `allow`/`deny`/`ask` flow. Exempts multi-line/commented commands (unsafe to wrap by string concatenation), dangerous commands already covered by `settings.json`'s `deny`/`ask` lists (rewriting could defeat an end-anchored pattern like `git push *--force* main`), commands already piped/redirected/backgrounded, and ones where the full output is the point (`cat`, `git diff/log/show/blame`, `diff`) |
| `opencode-context-guard.js` | OpenCode | Plugin equivalent of `context-guard.sh`, same thresholds using the session API's exact token counts instead of a byte-size estimate. Also blocks `WebFetch` on all 4 hosts, `github.com`, `phabricator.`, `sentry.io`, `grafana.`, regex covers self-hosted domains directly. Also runs the same Bash output cap as `bash-output-cap.sh`, but via `tool.execute.after`, which can rewrite the actual result content post-execution, since OpenCode's own generic output truncation skips any tool (like `bash`) that already sets its own `truncated` metadata. Also mirrors `herdr-workspace-router.sh` via the generic `event` hook filtered to `session.created`, there's no dedicated session-start hook key in this OpenCode plugin API version |

Codex treats `~/.codex/hooks.json` as a non-managed, user-level hook source: it won't run until reviewed and trusted once per machine via `/hooks` in the Codex CLI (this repo can install the file, it can't pre-trust it for you). Copilot CLI doesn't have this trust-gate for user-level hooks.

## Skills

Skills are loaded by agents and triggered via commands. The `Command` column below maps to a `commands/*.md` slash command, symlinked into Claude Code and OpenCode as-is and into Codex as `~/.codex/prompts/`. Copilot CLI has no distinct commands/prompts concept, it only has skills (invocable directly as `/skill-name`) and custom agents (`/agent`), so there is no Copilot equivalent for this column, intentionally not ported.

### Workflow Skills

| Skill | Command | Purpose |
| ----- | ------ | ------- |
| `manage-github-pr` | `/manage-github-pr` | Create a `PR` with structured description, split commits, feature branch, auto-assign, and labels, also reviews/edits/comments on existing PRs |
| `resolve-github-pr-comments` | `/resolve-github-pr-comments` | Review `PR` comments, assess validity, make fixup commits, push, reply with `SHA` links |
| `review-github-pr` | `/review-github-pr` | Multi-agent `PR` review, spawns agents in parallel, can post inline comments |

### Diagnostic Skills

| Skill | Command | Purpose |
| ----- | ------ | ------- |
| `diagnose` | `/diagnose` | Disciplined diagnosis loop: reproduce, minimise, hypothesise, instrument, fix, regression-test |
| `technical-analysis` | `/technical-analysis` | Structured technical analysis with method-level changes, notes, estimation, and architecture deepening opportunities |
| `seo` | `/seo` | Technical SEO, E-E-A-T/content quality, schema markup, sitemap, image SEO, and AI-search (GEO/AEO) analysis for any URL |

### Creative Skills

| Skill | Command | Purpose |
| ----- | ------ | ------- |
| `promo-video` | `/promo-video` | Plan and produce a short launch video for the current project: inspect, storyboard, tone, share copy, then render locally via `npx hyperframes` |

### Design Skills

| Skill | Command | Purpose |
| ----- | ------ | ------- |
| `interface-design` | Loaded by the `designer` agent, no dedicated command | Craft-first UI design guidance: visual hierarchy, design tokens, states, component checklist |

### Utility Skills

| Skill | Command | Purpose |
| ----- | ------ | ------- |
| `caveman` | `/caveman` | Ultra-compressed communication mode, cuts token usage by dropping filler while keeping technical accuracy |
| `handoff` | `/handoff` | Compact conversation into a handoff document for fresh agent sessions |
| `agent-models` | `/agent-models` | Research, rank, and apply model updates across all agents and configs for any provider |
| `humanize` | `/humanize` | Rewrite AI-sounding text as natural human writing, English and Greek |
| `capture-knowledge` | `/capture-knowledge` | Extract reusable knowledge from the conversation into an external second-brain repo, opens a `PR` |
| `eli5` | Loaded automatically, no dedicated command | Explain a concept, error, or code simply, dead-simple by default or matched to a stated audience |

### Task Management Skills

| Skill | Command | Purpose |
| ----- | ------- | ------- |
| `manage-phabricator-task` | `/manage-phabricator-task` | Create and edit Phabricator tasks via the official `Phabricator MCP` server, including tag and workboard-column conventions for boards that use them |

### Tool Skills

Auto-triggered by topic, no dedicated command, formerly always-loaded files under `tools/`.

| Skill | Purpose |
| ----- | ------- |
| `read-github-pr` | Read GitHub PR description, diff, files |
| `read-github-issue` | Read GitHub issue body, comments |
| `read-github-files` | Read GitHub commits, releases, raw repo file/directory content; also creates releases |
| `manage-github-issue` | Create, comment on, or edit GitHub issues |
| `read-phabricator-task` | Phabricator MCP integration, read/search/analyze |
| `read-sentry-issue` | Sentry error tracking and issue analysis |
| `search-grafana-logs` | Grafana dashboard/log links, `logcli`/Loki only, no `curl`/`HTTP API` path |
| `search-qmd-notes` | `qmd` markdown search and semantic query usage |
| `migrations` | Database migration file naming and chain-linearity rules |
| `craft-design-prompt` | Polish an AI design tool prompt before the user goes to the tool |
| `implement-design-from-export` | Build/match UI from an AI design tool export, HTML/CSS or screenshot |

## Agents

Agent system prompts live in `agents/`. Model assignments are in `models.txt` as the single source of truth. `setup/agentic.sh` injects them into each tool:

- **OpenCode**: built into `opencode.json` via the `agent` section.
- **Claude Code**: injected into each agent YAML frontmatter under `~/.claude/agents/`.
- **Codex**: generated as one `.toml` file per agent under `~/.codex/agents/`, `name`/`model`/`description`/`developer_instructions` fields plus an optional `model_reasoning_effort` when `models.txt` sets one, `developer_instructions` is the agent's Markdown body.
- **Copilot CLI**: generated as one `.agent.md` file per agent under `~/.copilot/agents/`, same YAML-frontmatter-plus-Markdown-body shape as the Claude Code source files. `disallowedTools`/`permission` (Claude/OpenCode-only, denylist-based) don't translate to Copilot's allowlist-based `tools:` field, so they're dropped, Copilot agents get access to all tools rather than the same restrictions Claude's `architect`/`reviewer`/etc. get.

Built-in agents: `explore` and `compaction` use lowest-cost capable models.

Refer to `models.txt` for current assignments.
