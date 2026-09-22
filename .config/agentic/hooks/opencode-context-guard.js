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
//   - Routes a new top-level session into a herdr space matching its git repo,
//     mirroring Claude Code's herdr-workspace-router.sh (SessionStart hook).
//     There's no dedicated "session started" hook key in this OpenCode plugin
//     API version (@opencode-ai/plugin's Hooks interface), so this listens on
//     the generic `event` hook for `session.created` and skips subsessions
//     (an `info.parentID`) the same way the Claude-side hook skips subagents.
//     herdr's env vars (HERDR_ENV/HERDR_PANE_ID/HERDR_SOCKET_PATH) are plain
//     shell env vars set on the pane before opencode is spawned inside it, so
//     they reach this plugin via `process.env` like any inherited OS env var,
//     no special OpenCode plumbing needed. Shares the same
//     ~/.config/herdr/workspace-router-map.json state file as the Claude-side
//     hook, and the same portable mkdir-based lock (Node has no fcntl.flock).
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

import { mkdirSync, readFileSync, rmdirSync, statSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import net from "node:net";
import os from "node:os";
import path from "node:path";

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

// Sends one newline-delimited JSON-RPC request to herdr's local unix socket
// and resolves with its `result` (or rejects on an `error` response or
// timeout). Mirrors the Claude-side hook's Python `rpc()` helper exactly,
// same wire shape, same one-request-one-line-response protocol.
function herdrRpc(socketPath, method, params) {
  return new Promise((resolve, reject) => {
    const client = net.createConnection({ path: socketPath });
    let buffer = "";
    const timer = setTimeout(() => {
      client.destroy();
      reject(new Error("herdr rpc timeout"));
    }, 1000);
    client.on("connect", () => {
      const requestId = `herdr:workspace-router:${Date.now()}:${Math.floor(Math.random() * 1_000_000)}`;
      client.write(JSON.stringify({ id: requestId, method, params }) + "\n");
    });
    client.on("data", (chunk) => {
      buffer += chunk.toString("utf-8");
      if (!buffer.includes("\n")) return;
      clearTimeout(timer);
      client.end();
      try {
        const response = JSON.parse(buffer);
        if (response.error) reject(new Error(response.error.message || "herdr rpc error"));
        else resolve(response.result);
      } catch (error) {
        reject(error);
      }
    });
    client.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

// Portable cross-process mutex for the shared repo-to-workspace map file,
// a plain `mkdir` is atomic on POSIX (fails with EEXIST if another process
// already holds it). Matches the Claude-side hook's own mkdir-based lock
// (see herdr-workspace-router.sh) so the two interoperate on the same file
// instead of racing with incompatible locking schemes.
// If the holder is killed before its `finally` block removes the lock
// directory, it would otherwise wedge every future run forever, so a lock
// older than the critical section could ever legitimately take is force-
// cleared instead of waited out.
const LOCK_STALE_MS = 15000;

async function withHerdrMapLock(mapPath, fn) {
  const lockPath = `${mapPath}.lock`;
  let acquired = false;
  for (let attempt = 0; attempt < 50; attempt++) {
    try {
      mkdirSync(lockPath);
      acquired = true;
      break;
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      try {
        const age = Date.now() - statSync(lockPath).mtimeMs;
        if (age > LOCK_STALE_MS) {
          try {
            rmdirSync(lockPath);
          } catch {
            // Another process may have already cleared it, just retry.
          }
          continue;
        }
      } catch {
        // Lock disappeared between the failed mkdir and this stat, retry immediately.
      }
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }
  if (!acquired) return;
  try {
    let repoMap = {};
    try {
      const content = readFileSync(mapPath, "utf-8");
      if (content.trim()) repoMap = JSON.parse(content);
    } catch {
      repoMap = {};
    }
    await fn(repoMap);
    const sortedMap = Object.fromEntries(Object.entries(repoMap).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
    writeFileSync(mapPath, `${JSON.stringify(sortedMap, null, 2)}\n`, "utf-8");
  } finally {
    try {
      rmdirSync(lockPath);
    } catch {
      // Best effort, a leftover lock dir self-heals via the staleness check above.
    }
  }
}

// Routes the pane a new top-level OpenCode session started in into a herdr
// space matching its git repo. Only ever runs for a pane herdr already
// knows about and running an agent, opening a plain shell tab with no
// repository never reaches this at all (no session, no event), and a cwd
// that isn't a git repo exits below before anything is created or moved.
async function routeHerdrWorkspace(info) {
  if (!info || info.parentID) return;
  if (process.env.HERDR_ENV !== "1") return;
  const paneId = process.env.HERDR_PANE_ID;
  const socketPath = process.env.HERDR_SOCKET_PATH;
  if (!paneId || !socketPath) return;

  try {
    const paneResult = await herdrRpc(socketPath, "pane.get", { pane_id: paneId });
    const pane = paneResult.pane;
    const currentWorkspaceId = pane.workspace_id;
    const cwd = pane.foreground_cwd || pane.cwd;

    const workspaceResult = await herdrRpc(socketPath, "workspace.list", {});
    const workspaces = Object.fromEntries(workspaceResult.workspaces.map((w) => [w.workspace_id, w]));
    if (!workspaces[currentWorkspaceId] || typeof cwd !== "string" || !cwd) return;

    // Identity is the worktree's own root (`--show-toplevel`), not
    // `--git-common-dir`: the common dir is shared by every linked worktree
    // of a repo, so keying on it would merge separate worktrees, each
    // usually a distinct, parallel unit of work, into one space. See the
    // matching comment in herdr-workspace-router.sh.
    let worktreeRoot;
    try {
      worktreeRoot = execFileSync(
        "git",
        ["-C", cwd, "rev-parse", "--path-format=absolute", "--show-toplevel"],
        { encoding: "utf-8", timeout: 2000 },
      ).trim();
    } catch {
      return;
    }
    if (!worktreeRoot) return;
    const repoName = path.basename(worktreeRoot) || "workspace";

    const mapPath = path.join(os.homedir(), ".config", "herdr", "workspace-router-map.json");
    mkdirSync(path.dirname(mapPath), { recursive: true });

    await withHerdrMapLock(mapPath, async (repoMap) => {
      // A stale mapping (workspace closed or renamed since) is cleared the
      // same way as no mapping at all, it must not leave this repo stuck.
      let mappedWorkspaceId = repoMap[worktreeRoot];
      if (mappedWorkspaceId && !workspaces[mappedWorkspaceId]) mappedWorkspaceId = null;
      let destination = null;

      if (mappedWorkspaceId && mappedWorkspaceId !== currentWorkspaceId) {
        destination = { type: "new_tab", workspace_id: mappedWorkspaceId };
      } else if (!mappedWorkspaceId) {
        const current = workspaces[currentWorkspaceId];
        if (current.pane_count === 1 && current.tab_count === 1) {
          repoMap[worktreeRoot] = currentWorkspaceId;
        } else {
          destination = { type: "new_workspace", label: repoName, tab_label: null };
        }
      }

      if (destination) {
        try {
          const moveResponse = await herdrRpc(socketPath, "pane.move", { pane_id: paneId, destination });
          const moveResult = moveResponse.move_result ?? {};
          let resolvedWorkspaceId = moveResult.pane?.workspace_id;
          if (moveResult.created_workspace) {
            resolvedWorkspaceId = moveResult.created_workspace.workspace_id ?? resolvedWorkspaceId;
          }
          if (resolvedWorkspaceId) repoMap[worktreeRoot] = resolvedWorkspaceId;
        } catch {
          // Best effort, never break session start over a routing failure.
        }
      }
    });
  } catch {
    // Best effort, never break session start over a routing failure.
  }
}

export const AgenticReminderPlugin = async ({ client }) => {
  return {
    event: async ({ event }) => {
      if (event.type === "session.created") {
        await routeHerdrWorkspace(event.properties?.info);
      }
    },
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
      if ((input.tool ?? "").toLowerCase() !== "webfetch") return;
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
