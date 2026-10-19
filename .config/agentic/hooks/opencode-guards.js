// OpenCode adapter for the agentic hooks. Mirrors what Claude Code does via
// settings.json:
//   - Blocks WebFetch on service URLs that have a dedicated CLI, since OpenCode
//     cannot deny WebFetch by host in config (Claude uses permissions.deny).
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
// Static instructions (communication/standards/versioning/privacy/security) load via opencode.json's
// `instructions` array instead, no hook needed for those.
//
// tool.execute.after receives the live result object, not a copy: trigger()
// calls fn(input, output) directly on the same object and returns it
// (packages/opencode/src/plugin/index.ts), and packages/opencode/src/session/tools.ts
// awaits the trigger before returning `output` to the LLM. So mutating
// output.output here is honored, unlike Claude Code's PostToolUse, which is
// read-only (code.claude.com/docs/en/hooks).

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

export const AgenticGuardsPlugin = async () => {
  return {
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
