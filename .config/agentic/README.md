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
│   ├── documentation.md
│   ├── privacy.md
│   ├── security.md
│   ├── standards.md
│   └── versioning.md
├── hooks/                         # Run per prompt or tool call
│   ├── webfetch-guard.sh          # Claude Code PreToolUse hook, blocks WebFetch when not needed
│   ├── bash-output-cap.sh         # Claude Code PreToolUse hook, caps unbounded Bash stdout
│   └── opencode-guards.js         # OpenCode plugin equivalent, includes the same Bash output cap
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
| `documentation.md` | Tenets for documentation, tests and feature details |
| `privacy.md` | PII handling rules |
| `security.md` | Shell command and endpoint security practices |
| `standards.md` | Core implementation rules, safety, error handling |
| `versioning.md` | `Git` conventions and commit rules |

## Hooks

| File | Wired into | Purpose |
| ---- | ---------- | ------- |
| `webfetch-guard.sh` | Claude Code, Copilot CLI | `PreToolUse` hook, matcher: `WebFetch`. Denies fetches to `github.com`, `sentry.io`, and self-hosted `Phabricator`/`Grafana` hostnames with an actionable reason pointing at the right skill/CLI/MCP. `github.com`/`sentry.io` are also in `claude/settings.json`'s static `permissions.deny` as a fallback; self-hosted `Phabricator`/`Grafana` hostnames can't be expressed as a static domain rule, so those rely on this hook alone. Not wired into Codex, it has no built-in URL-fetch tool to gate, its `web_search` tool returns query snippets rather than a fetched URL. Copilot CLI reads it via a PascalCase `PreToolUse` event name, which opts into its documented Claude-format matcher/payload compatibility mode, no script changes needed |
| `auto-session-title.sh` | Claude Code only | `UserPromptSubmit` hook, generates a session title via a headless `claude -p` call and writes Claude Code's own `custom-title` transcript format. Fundamentally Claude-specific, not portable |
| `bash-output-cap.sh` | Claude Code | `PreToolUse` hook, matcher: `Bash`. Rewrites unbounded commands to redirect their combined stdout+stderr to a temp file and `head -c 20000` it before execution, this is the only stage that can affect Bash output at all, `PostToolUse` can't rewrite a tool's result. Uses a brace group and a temp file rather than piping straight through `head`, a pipe would run the command in a subshell (breaking `cd`/`export` persistence across calls) and risk `SIGPIPE`-killing it mid-run once `head` has its bytes. Never sets `permissionDecision`, so the rewritten command still goes through the normal `allow`/`deny`/`ask` flow. Exempts multi-line/commented commands (unsafe to wrap by string concatenation), dangerous commands already covered by `settings.json`'s `deny`/`ask` lists (rewriting could defeat an end-anchored pattern like `git push *--force* main`), commands already piped/redirected/backgrounded, and ones where the full output is the point (`cat`, `git diff/log/show/blame`, `diff`) |
| `opencode-guards.js` | OpenCode | Blocks `WebFetch` on all 4 hosts, `github.com`, `phabricator.`, `sentry.io`, `grafana.`, regex covers self-hosted domains directly. Also runs the same Bash output cap as `bash-output-cap.sh`, but via `tool.execute.after`, which can rewrite the actual result content post-execution, since OpenCode's own generic output truncation skips any tool (like `bash`) that already sets its own `truncated` metadata |

Codex treats `~/.codex/hooks.json` as a non-managed, user-level hook source: it won't run until reviewed and trusted once per machine via `/hooks` in the Codex CLI (this repo can install the file, it can't pre-trust it for you). Copilot CLI doesn't have this trust-gate for user-level hooks.

In `Claude Code`, stale or oversized sessions are left to its own compaction, it compacts an idle session shortly before the 1 hour prompt cache expires (`idleCompaction`, threshold `CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS` in `claude/settings.json`), set `"idleCompaction": false` there to turn it off.

## MCP Servers

`setup/agentic.sh` registers each server from these env vars (a server left unset is skipped with a warning, not a hard failure). Never hardcode an organization's actual URL in this repo, set it as an env var instead, for example a fish universal variable:

```bash
# Sentry MCP URL setup.
# No URL needed, hardcoded in setup/agentic.sh.

# Phabricator MCP URL setup.
set -Ux PHABRICATOR_MCP_URL "<url>"

# Grafana MCP URL setup.
set -Ux GRAFANA_MCP_URL "<url>"

# Metabase MCP URL setup.
set -Ux METABASE_MCP_URL "<url>"
```

After registration, each server still needs its own authentication inside the agentic tool itself, `setup/agentic.sh` only wires up the connection.

Slack is not registered here. `Claude Code` cannot do local OAuth for it, it comes from the `claude.ai` Slack connector (`mcp__claude_ai_Slack__*` tools, discovered through `ToolSearch`), and `claude/settings.json` allowlists only its read tools. `privacy.md` applies to anything read from or written to Slack, no PII.

## Startup context

Everything listed at session start costs tokens on every turn, so `claude/settings.json` trims what is unused. `deniedMcpServers` takes an array of `{ "serverName": "<name>" }` objects, the object-with-array and `disabledMcpServers` forms were tested and do nothing, it hides the unused claude.ai connectors and keeps Slack. `skillOverrides` sets a local skill to `user-invocable-only` (hidden from the model, still in the `/` menu) or `name-only`, it does not reach plugin skills, bundled skills, or the claude.ai synced `anthropic-skills:*`, turn those off in the claude.ai skills settings. Verify with `claude --settings <file> -p "say ok" --output-format stream-json --verbose` and read the `init` event, or with `/context` in a fresh session. Today `agent-models`, `capture-knowledge`, `caveman`, `craft-design-prompt`, `eli5`, `humanize`, `implement-design-from-export`, `marketing`, `promo-video`, `seo` and `technical-analysis` are `user-invocable-only`, and `mobile-app-design` and `web-app-design` are `name-only`.

## Advisor

`/advisor <model>` (or the `advisorModel` setting) lets the main model consult a stronger one at decision points. Each call is billed at the advisor's rates on the full transcript, uncached. It is not a replacement for the `reviewer` agent, Claude decides when to call it. Off by default, try it on the `implementor` before making it a default.

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
| `launch-audit` | `/launch-audit` | Pre-launch readiness audit, five parallel fresh-context read-only lanes, security and known CVEs, performance, dead weight and upgrades that fix bugs or replace own code, test gaps, new developer confusion, merged and verified into a ranked one-week fix plan, changes no code |
| `security-audit` | `/security-audit` | Deep read-only security audit adapted from `cloudflare/security-audit-skill`, parallel hunt lanes plus on-demand references for web and auth, AI and agents, supply chain and CI, cloud, and data isolation, every candidate disproved by a fresh verifier into confirmed, needs-validation, or rejected, changes no code |
| `seo` | `/seo` | Technical SEO, E-E-A-T/content quality, schema markup, sitemap, image SEO, and AI-search (GEO/AEO) analysis for any URL |

### Creative Skills

| Skill | Command | Purpose |
| ----- | ------ | ------- |
| `promo-video` | `/promo-video` | Plan and produce a short launch video for the current project: inspect, storyboard, tone, share copy, then render locally from HTML scenes with headless Chrome and `ffmpeg` through the bundled `scripts/promo.py` (one command, Python 3 standard library only), no packages to install, works natively on macOS, Linux, and Windows. Runs on the model pinned in its `SKILL.md` for the turn it is invoked |

### Marketing Skills

| Skill | Command | Purpose |
| ----- | ------ | ------- |
| `marketing` | `/marketing` | Own condensed take on `coreyhaines31/marketingskills` for indie apps, a router plus on-demand references for product context, launch, ASO, landing copy, pricing and paywalls, onboarding. Defers search work to `seo` |

### Design Skills

| Skill | Command | Purpose |
| ----- | ------ | ------- |
| `web-app-design` | Loaded by the `designer` agent, no dedicated command | Craft-first UI design guidance: visual hierarchy, design tokens, states, component checklist |
| `mobile-app-design` | Loaded by the `designer` agent, no dedicated command | Platform-native UI craft for Flutter, SwiftUI/UIKit, and Jetpack Compose apps: HIG/Material conventions, native controls, navigation, icons, safe areas |

### Utility Skills

| Skill | Command | Purpose |
| ----- | ------ | ------- |
| `caveman` | `/caveman` | Ultra-compressed communication mode, cuts token usage by dropping filler while keeping technical accuracy |
| `handoff` | `/handoff` | Compact conversation into a handoff document for fresh agent sessions |
| `agent-models` | `/agent-models` | Research, rank, and apply model updates across all agents and configs for any provider |
| `humanize` | `/humanize` | Rewrite AI-sounding text as natural human writing, English and Greek |
| `capture-knowledge` | `/capture-knowledge` | Add knowledge from the conversation or mined sources to an external knowledge repo, the shareable profile opens a `PR` |
| `eli5` | Skill only, `/eli5` | Explain a concept, error, or code simply, dead-simple by default or matched to a stated audience |
| `html-plan` | `/html-plan <task>`, from the `html-plan@claude-community` plugin | Write a plan as one interactive HTML page, answer decisions and comment in place, then paste the response back. `Claude Code` only, enabled and the `claude-community` marketplace added through `claude/settings.json`, needs `node`. The model writes the page by hand, so it costs tokens per plan |

### Task Management Skills

| Skill | Command | Purpose |
| ----- | ------- | ------- |
| `manage-phabricator-task` | `/manage-phabricator-task` | Create and edit Phabricator tasks via the official `Phabricator MCP` server, including tag and workboard-column conventions for boards that use them |

### Tool Skills, auto-triggered by topic

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
| `test-quality` | Test junk patterns and test authoring rules |
| `craft-design-prompt` | Polish an AI design tool prompt before the user goes to the tool |
| `implement-design-from-export` | Build/match UI from an AI design tool export, HTML/CSS or screenshot |

## Agents

Agent system prompts live in `agents/`. Model assignments are in `models.txt` as the single source of truth. `setup/agentic.sh` injects them into each tool:

- **OpenCode**: built into `opencode.json` via the `agent` section.
- **Claude Code**: injected into each agent YAML frontmatter under `~/.claude/agents/`.
- **Codex**: generated as one `.toml` file per agent under `~/.codex/agents/`, `name`/`model`/`description`/`developer_instructions` fields plus an optional `model_reasoning_effort` when `models.txt` sets one, `developer_instructions` is the agent's Markdown body.
- **Copilot CLI**: generated as one `.agent.md` file per agent under `~/.copilot/agents/`, same YAML-frontmatter-plus-Markdown-body shape as the Claude Code source files. `disallowedTools`/`permission` (Claude/OpenCode-only, denylist-based) don't translate to Copilot's allowlist-based `tools:` field, so they're dropped, Copilot agents get access to all tools rather than the same restrictions Claude's `architect`/`reviewer`/etc. get.

Built-in agents: `explore` and `compaction` use lowest-cost capable models. Claude Code has no model setting for its built-in `Explore`, so `claude/agents/explore.md` overrides it with a read-only agent of the same name that takes the `claude:explore:` model. Compaction there has no model setting either and follows the session model. `CLAUDE_CODE_SUBAGENT_MODEL` in `claude/settings.json` is the default for `general-purpose` and any subagent without its own model, never for agents that set one, from Claude Code 2.1.251, before that it overrode every agent's model. `Plan` and forks follow the session model.

Refer to `models.txt` for current assignments.
