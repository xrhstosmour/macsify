// OpenCode adapter for the agentic hooks. Mirrors what Claude Code does via
// settings.json:
//   - Re-injects the routing reminder into the system prompt every turn, so it
//     stays salient instead of fading (Claude uses the UserPromptSubmit hook).
//   - Blocks WebFetch on service URLs that have a dedicated CLI, since OpenCode
//     cannot deny WebFetch by host in config (Claude uses permissions.deny).
//
// The reminder text lives in reminders.md, the single source. The injection
// hook is experimental in the OpenCode API, so it is wrapped in try/catch: if
// it ever changes, injection stops silently and nothing crashes.

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

export const AgenticReminderPlugin = async () => {
  return {
    "experimental.chat.system.transform": async (_input, output) => {
      try {
        output.system.push(readFileSync(reminderPath, "utf8"));
      } catch {
        // Best-effort. Never break a session if the reminder file is missing.
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
