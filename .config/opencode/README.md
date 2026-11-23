# OpenCode

OpenCode configuration and plugins. `opencode.json` is a template, see `opencode.json` is a template in the repository's `AGENTS.md`.

## Plugins and MCP servers

`setup/agentic.sh` also installs, with `npm install -g`:

- The third-party `opencode-status-hud` HUD plugin, into `~/.config/opencode/plugin/`.
- The `browse` MCP server, `@opencode/browse`, pinned, with its hourly self-update set to `notify`. It lets OpenCode drive the real `Chrome`. Each of its tools asks first through `"browse_*": "ask"` in `permission`, since a page it reads could try to steer it.

The `browse` extension is added and paired by hand once: `browse install` opens the Chrome Web Store and pairs it. Choose no agents there, `opencode.json` already has the entry.
