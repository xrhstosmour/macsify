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
//   - Caps oversized `bash` stdout+stderr post-execution, mirroring Claude
//     Code's bash-output-cap.sh (same 20000-byte cap and the same "full
//     output is the point" command exemptions), but through
//     tool.execute.after rather than a PreToolUse command rewrite. That
//     also means it skips a few exemptions that only make sense for a
//     command *rewrite*: bash-output-cap.sh additionally exempts
//     multi-line/commented commands (string-wrapping them would break
//     their syntax) and dangerous commands (rewriting them could defeat an
//     end-anchored deny pattern in settings.json). Neither risk applies
//     here, this hook only truncates the result text after the real
//     command already ran with its real permissions and its real syntax.
//     OpenCode's own generic truncation (opencode.json's tool_output.max_lines/
//     max_bytes, packages/opencode/src/tool/truncate.ts, default 2000 lines /
//     50KB) is skipped for any tool whose result already sets
//     metadata.truncated, and packages/core/src/tool/bash.ts always does (it
//     only guards a 1MB in-memory capture safety limit), so bash's returned
//     output is otherwise uncapped. This is a gap Claude Code's Bash tool
//     shares too, hence bash-output-cap.sh existing at all.
//
// Static instructions (communication/standards/versioning) load via opencode.json's
// `instructions` array instead, no hook needed for those.
//
// experimental.chat.system.transform is not on opencode.ai/docs. Source of truth:
//   signature:  https://github.com/anomalyco/opencode/blob/dev/packages/plugin/src/index.ts
//   invocation: https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/session/llm/request.ts
//   session shape (tokens, time.updated in epoch ms): https://github.com/anomalyco/opencode/blob/dev/packages/core/src/session.ts
//
// tool.execute.after receives the live result object, not a copy: trigger()
// calls fn(input, output) directly on the same object and returns it
// (packages/opencode/src/plugin/index.ts), and packages/opencode/src/session/tools.ts
// awaits the trigger before returning `output` to the LLM. So mutating
// output.output here is honored, unlike Claude Code's PostToolUse, which is
// read-only (code.claude.com/docs/en/hooks).

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

// Same cap and "full output is the point" exemptions as bash-output-cap.sh,
// see the file header for the exemptions this side deliberately doesn't
// need. `&` is anchored to the end (a real trailing "run in background"),
// not matched anywhere in the string, an `&&` in the middle of a chained
// command isn't backgrounding and shouldn't skip the cap.
const BASH_OUTPUT_MAX_BYTES = 20000;
const boundedOutputPattern = /\|\s*(head|tail|less|wc|fzf)\b|&\s*$|>/;
const fullOutputCommandPattern = /^(git\s+(diff|log|show|blame)\b|diff\s|cat\s)/;

// Drops a UTF-8 sequence straddling the cut instead of decoding it with a
// replacement character, `head -c` truncation elsewhere in the stack cuts
// blind too, and a replacement character can be wider than the partial
// bytes it stands in for, pushing the result past maxBytes.
function truncateUtf8(bytes, maxBytes) {
  if (bytes.length <= maxBytes) return bytes;
  let end = maxBytes;
  // A continuation byte (10xxxxxx) right after the cut means it lands
  // inside a multi-byte character, back off to that character's start and
  // drop it whole. A lead byte or ASCII byte there means the cut is clean.
  if ((bytes[end] & 0xc0) === 0x80) {
    while (end > 0 && (bytes[end] & 0xc0) === 0x80) end--;
  }
  return bytes.subarray(0, end);
}

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
    "tool.execute.after": async (input, output) => {
      if (input.tool !== "bash") return;

      const command = String(input.args?.command ?? "");
      if (boundedOutputPattern.test(command) || fullOutputCommandPattern.test(command)) return;

      if (typeof output.output !== "string") return;
      // Byte length, not output.output.length (UTF-16 code units), to match
      // what bash-output-cap.sh's `head -c` actually counts.
      const encoded = new TextEncoder().encode(output.output);
      if (encoded.length <= BASH_OUTPUT_MAX_BYTES) return;
      const truncated = new TextDecoder("utf-8").decode(truncateUtf8(encoded, BASH_OUTPUT_MAX_BYTES));
      output.output = truncated + `\n\n[bash-output-cap: truncated at ${BASH_OUTPUT_MAX_BYTES} bytes]`;
    },
  };
};
