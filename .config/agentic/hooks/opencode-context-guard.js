// OpenCode adapter for the agentic hooks. Mirrors what Claude Code does via
// settings.json:
//   - Re-injects the routing reminder into the system prompt every turn, so it
//     stays salient instead of fading (Claude uses the UserPromptSubmit hook).
//   - Blocks WebFetch on service URLs that have a dedicated CLI, since OpenCode
//     cannot deny WebFetch by host in config (Claude uses permissions.deny).
//   - Warns once a session's token usage or idle time gets large, mirroring
//     Claude Code's context-guard.sh (same thresholds, exact token counts here
//     instead of a byte-size estimate, since the session API reports them).
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
];

// Same balanced thresholds as context-guard.sh (Claude Code side).
const SIZE_WARN_TOKENS = 180000;
const IDLE_WARN_SECONDS = 2700;

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
            `# Context Health Warning\n\nThis session has used ~${totalTokens} tokens, last active ${idleMinutes} minutes ago.\nLong idle gaps on large contexts force an expensive full cache rebuild on the next turn.\nTell the user their context is large or stale and recommend running /compact or starting a new session before continuing with heavy tool use.`,
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
