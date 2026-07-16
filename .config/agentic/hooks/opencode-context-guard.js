// OpenCode adapter for the agentic hooks. Mirrors what Claude Code does via
// settings.json:
//   - Re-injects the routing reminder into the system prompt every turn, so it
//     stays salient instead of fading (Claude uses the UserPromptSubmit hook).
//   - Blocks WebFetch on service URLs that have a dedicated CLI, since OpenCode
//     cannot deny WebFetch by host in config (Claude uses permissions.deny).
//   - Warns once a session's token usage or idle time gets large, mirroring
//     Claude Code's context-guard.sh (same thresholds, exact token counts here
//     instead of a byte-size estimate, since the session API reports them).
//     Thresholds are intentionally aggressive (50K tokens, 30 min idle) to
//     force compaction before context bloat becomes irreversible.
//
// The reminder text lives in reminders.md, the single source. The injection
// hook is experimental in the OpenCode API, so it is wrapped in try/catch: if
// it ever changes, injection stops silently and nothing crashes.
//
// experimental.chat.system.transform is not on opencode.ai/docs. Source of truth:
//   signature:  https://github.com/anomalyco/opencode/blob/dev/packages/plugin/src/index.ts
//   invocation: https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/session/llm/request.ts
//   session shape (tokens, time.updated in epoch ms): https://github.com/anomalyco/opencode/blob/dev/packages/core/src/session.ts

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const reminderPath = join(homedir(), ".config", "agentic", "hooks", "reminders.md");

// Service URLs that must go through a dedicated CLI, never WebFetch.
const blockedHosts = [
  { pattern: /github\.com/i, use: "the `gh` CLI per ~/.config/agentic/tools/github.md" },
  { pattern: /phabricator\./i, use: "the Conduit API per ~/.config/agentic/tools/phabricator.md" },
  { pattern: /sentry\.io/i, use: "`sentry-cli` per ~/.config/agentic/tools/sentry.md" },
  { pattern: /grafana\./i, use: "`logcli` per ~/.config/agentic/tools/grafana.md" },
];

// Warn early. 50K tokens is roughly 2-3 API calls with a full context window.
// At 180K the context is already bloated and compaction cannot recover lost cache.
const SIZE_WARN_TOKENS = 50000;
const IDLE_WARN_SECONDS = 1800;

export const AgenticReminderPlugin = async ({ client }) => {
  return {
    "experimental.chat.system.transform": async (input, output) => {
      try {
        output.system.push(readFileSync(reminderPath, "utf8"));
      } catch {
        // Best-effort. Never break a session if the reminder file is missing.
      }

      const sessionID = input.sessionID;
      if (!sessionID) return;

      try {
        const { data: session } = await client.session.get({ path: { id: sessionID } });
        if (!session) return;

        const tokens = session.tokens ?? {};
        const totalTokens = (tokens.input ?? 0) + (tokens.output ?? 0) + (tokens.cache?.read ?? 0) + (tokens.cache?.write ?? 0);
        const idleSeconds = (Date.now() - (session.time?.updated ?? Date.now())) / 1000;

        if (totalTokens > SIZE_WARN_TOKENS || idleSeconds > IDLE_WARN_SECONDS) {
          const idleMinutes = Math.round(idleSeconds / 60);
          output.system.push(
            `# Context Health Warning\n\nThis session has used ~${totalTokens} tokens, last active ${idleMinutes} minutes ago.\nYOU MUST compact now or start a fresh session. Long sessions burn tokens because every API call re-sends the full conversation history.\nDo not defer compaction. Do not start new delegations until context is compacted.`,
          );
        }
      } catch {
        // Best-effort. Never break a session if session info can't be fetched.
      }
    },
    "tool.execute.before": async (input, output) => {
      if ((input.tool ?? "").toLowerCase() !== "webfetch") return;
      const url = String(output.args?.url ?? "");
      const blocked = blockedHosts.find((host) => host.pattern.test(url));
      if (blocked) {
        throw new Error(`Blocked: use ${blocked.use}, not WebFetch.`);
      }
    },
  };
};
