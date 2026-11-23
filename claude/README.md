# Claude Code

Global `Claude Code` configuration, copied to `~/.claude/` by `setup/agentic.sh`, file by file, so this README stays here.

| Path | Purpose |
| ---- | ------- |
| `settings.json` | Global settings, merged with the machine's own keys, see below |
| `keybindings.json` | Key bindings |
| `plugins/claude-hud/config.json` | `claude-hud` status line configuration |
| `agents/explore.md` | Override of the built-in `Explore` subagent, model injected from `.config/agentic/models.txt` |
| `mcp-read-tools.json` | Read-only MCP tools allowed without a prompt |

## Read-only MCP tools

After the copy, `setup/agentic.sh` allows the tools of `mcp-read-tools.json` under the MCP servers in that machine's `~/.claude.json`. Each tool is allowed only on a server whose `url` has a trusted host, a public host committed under `hosts`, or a private one listed by hand in `~/.claude/mcp-trusted-hosts`. That file never goes in the repository, since server names and private hosts differ per laptop and stay out of it.

## Plugins

`setup/agentic.sh` installs each plugin `settings.json` turns on that is not installed yet, since an `enabledPlugins` entry never downloads one.
On the personal profile only, it installs Apple's `xcode` plugin with `claude plugin install --yes` and enables it again after each copy, since it links from the installed Xcode. Allowing external agents in Xcode's Intelligence settings stays a manual step.

## `Explore` override

`agents/explore.md` copies the built-in `Explore` `disallowedTools` and `omitClaudeMd`, which needs Claude Code 2.1.271 or later, re-check both against the built-in on each Claude Code upgrade.
Since it skips the global instructions, its Rules carry the shell safety and privacy rules from `.config/agentic/instructions/security.md` and `privacy.md`, and the `rg` search rule from `standards.md` Context Management, change them together.
