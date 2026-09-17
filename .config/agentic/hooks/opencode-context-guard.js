// OpenCode adapter for the agentic hooks. Mirrors what Claude Code does via
// settings.json:
//   - Blocks WebFetch on service URLs that have a dedicated CLI, since OpenCode
//     cannot deny WebFetch by host in config (Claude uses permissions.deny).
//   - Warns once a session has been idle for a while, mirroring Claude Code's
//     idle-only context-guard.sh (same threshold, using the session API's
//     `time.updated` instead of a transcript file's mtime). A byte/token size
//     check was dropped from both scripts: it was an unreliable estimate of
//     actual context usage, and the host's own context indicator already
//     covers that accurately.
//   - Blocks stray .md file creation, mirroring Claude Code's
//     documentation-guard.sh (same extension check, exempt basenames, and
//     exempt-path allowlist, adapted for OpenCode's own agentic-config
//     symlink targets instead of Claude Code's ~/.claude/* paths).
//
// Static instructions (communication/standards/versioning) load via opencode.json's
// `instructions` array instead, no hook needed for those.
//
// experimental.chat.system.transform is not on opencode.ai/docs. Source of truth:
//   signature:  https://github.com/anomalyco/opencode/blob/dev/packages/plugin/src/index.ts
//   invocation: https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/session/llm/request.ts
//   session shape (tokens, time.updated in epoch ms): https://github.com/anomalyco/opencode/blob/dev/packages/core/src/session.ts

import { existsSync } from "node:fs";

// Service URLs that must go through a dedicated CLI, never WebFetch. Patterns
// match against the hostname only (see below), anchored to a label boundary,
// so a path/query segment that happens to contain one of these words (e.g.
// blog.example.com/learn-grafana) isn't mistaken for the real host.
const blockedHosts = [
  { pattern: /(^|\.)github\.com$/i, use: "the `gh` CLI, see the `read-github-pr`/`read-github-issue`/`read-github-files` skills" },
  { pattern: /(^|\.)phabricator\./i, use: "the Phabricator MCP tools per the `read-phabricator-task` skill" },
  { pattern: /(^|\.)sentry\.io$/i, use: "the Sentry MCP tools per the `read-sentry-issue` skill" },
  { pattern: /(^|\.)grafana\./i, use: "`logcli` per the `search-grafana-logs` skill" },
];

// Fails open on any doubt, same as documentation-guard.sh: a false-positive
// block on real skill/agent authoring is worse than an occasional stray file.
const docGuardExemptBasenames = new Set(["README.md", "CLAUDE.md", "AGENTS.md", "CODEX.md", "CONTRIBUTING.md", "SKILL.md"]);
// OpenCode's own agents/commands/skills/instructions live under the
// .config/agentic/ source of truth (symlinked into
// ~/.config/opencode/{agents,commands,skills,instructions}), not under
// ~/.claude/*, so the exempt paths differ from documentation-guard.sh.
const docGuardExemptPathPattern = /(^|\/)\.config\/agentic\/|\/\.config\/opencode\/(agents|commands|skills|instructions)\//;

// No documented cache-TTL basis for this environment's actual providers
// (opencode/deepseek-v4-flash-free, nemotron, etc. via the opencode-go gateway,
// not Anthropic), so this mirrors context-guard.sh's Claude-subscription figure
// as a general staleness heuristic rather than a provider-verified number.
const IDLE_WARN_SECONDS = 3600;

// In-memory, per running OpenCode process. Unlike context-guard.sh's
// UserPromptSubmit hook (fires once per user message, so idle naturally
// self-resets), this transform can run on every LLM request within a turn,
// including intermediate tool-calling rounds. Keeps track of the
// `time.updated` value last seen when a warning fired, so it only re-fires
// once that value has actually moved forward, not on every request in a burst.
const lastWarned = new Map();

export const AgenticReminderPlugin = async ({ client }) => {
  return {
    "experimental.chat.system.transform": async (input, output) => {
      const sessionID = input.sessionID;
      if (!sessionID) return;

      try {
        const { data: session } = await client.session.get({ path: { id: sessionID } });
        if (!session) return;

        const updatedAt = session.time?.updated ?? Date.now();
        const idleSeconds = (Date.now() - updatedAt) / 1000;

        if (idleSeconds > IDLE_WARN_SECONDS) {
          const last = lastWarned.get(sessionID);

          if (!last || last.updatedAt !== updatedAt) {
            lastWarned.set(sessionID, { updatedAt });
            const idleMinutes = Math.round(idleSeconds / 60);
            output.system.push(
              `# Context Health Warning\n\nThis session has been idle for ~${idleMinutes} minutes. Long idle gaps force an expensive full cache rebuild on the next turn.\nFinish responding to the user's current request first. Then inform them the session has been idle a while, and advise compacting, handoff, or a new session.\nDo not interrupt the current answer to do this, and do not invoke anything yourself, only inform and advise.`,
            );
          }
        }
      } catch {
        // Best-effort. Never break a session if session info can't be fetched.
      }
    },
    "tool.execute.before": async (input, output) => {
      const tool = (input.tool ?? "").toLowerCase();

      if (tool === "webfetch") {
        const url = String(output.args?.url ?? "");
        let host = url;
        try {
          host = new URL(url).hostname;
        } catch {
          // Not a parseable absolute URL, fall back to matching the raw string.
        }
        const blocked = blockedHosts.find((entry) => entry.pattern.test(host));
        if (blocked) {
          throw new Error(`Blocked: use ${blocked.use}, not WebFetch.`);
        }
        return;
      }

      if (tool === "write") {
        const filePath = String(output.args?.filePath ?? "");
        if (!/\.md$/i.test(filePath)) return;
        if (existsSync(filePath)) return;
        const base = filePath.split("/").pop();
        if (docGuardExemptBasenames.has(base)) return;
        if (docGuardExemptPathPattern.test(filePath)) return;
        throw new Error(
          "Unnecessary documentation file creation blocked. Use README.md/CLAUDE.md/AGENTS.md for docs instead, per CLAUDE.md's file-creation rule.",
        );
      }
    },
  };
};
