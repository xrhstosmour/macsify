// Runs the rules of the `Herdr` app's `pull-request` mod. Started by `tests/pull-request.sh`.
import { fileURLToPath } from "node:url";

const logicUrl = new URL("../.config/herdr-app/mods/pull-request/logic.js", import.meta.url);
const { classify, focusedFolder, isStale, keyOf, checkRows, checksSummary, reviewers, timeline, diffFiles, failedRuns, withoutImages, actionArgs, confirmed, isArmed, armId, isCurrent, needsLoad, REFRESH_MS, CONFIRM_MS, DOUBLE_CLICK_MS } = await import(fileURLToPath(logicUrl));

let failures = 0;
function expect(label, actual, wanted) {
  if (JSON.stringify(actual) !== JSON.stringify(wanted)) {
    console.log(`FAIL: ${label}: got ${JSON.stringify(actual)}, wanted ${JSON.stringify(wanted)}`);
    failures += 1;
  }
}

const open = { number: 7, state: "OPEN", title: "Add a thing", url: "https://github.com/owner/repo/pull/7", updatedAt: "2026-11-06T08:00:00Z" };

// The button shows only for an open pull request of the branch.
expect("an open pull request shows", classify({ code: 0, stdout: JSON.stringify(open), stderr: "" }).status, "open");
expect("a merged one does not", classify({ code: 0, stdout: JSON.stringify({ ...open, state: "MERGED" }), stderr: "" }), { status: "none" });
expect("a branch without one does not", classify({ code: 1, stdout: "", stderr: 'no pull requests found for branch "main"\n' }), { status: "none" });
expect("a folder outside git does not", classify({ code: 1, stdout: "", stderr: "failed to run git: fatal: not a git repository (or any of the parent directories): .git\n" }), { status: "none" });
expect("a repository without a GitHub remote does not", classify({ code: 1, stdout: "", stderr: "none of the git remotes configured for this repository point to a known GitHub host\n" }), { status: "none" });
// A failure is shown, never taken for no pull request.
expect("an auth failure is an error", classify({ code: 4, stdout: "", stderr: "To get started with GitHub CLI, please run:  gh auth login\nmore\n" }), { status: "error", message: "To get started with GitHub CLI, please run:  gh auth login" });
expect("a missing gh is an error", classify({ error: "gh: not found" }), { status: "error", message: "gh: not found" });
expect("a number that is not an integer is an error", classify({ code: 0, stdout: JSON.stringify({ ...open, number: "@/etc/hosts" }), stderr: "" }).status, "error");
expect("broken JSON is an error", classify({ code: 0, stdout: "<html>", stderr: "" }).status, "error");

// The watcher follows the focused terminal's live folder, a `cd` included, never the folder its space was made in.
const space = { folder: "/space" };
expect("the focused pane's live folder", focusedFolder({ pane: "p2" }, [{ pane: "p1", cwd: "/other" }, { pane: "p2", cwd: "/worktree" }], space), "/worktree");
expect("a terminal block's own folder", focusedFolder({ pane: null, cwd: "/block" }, [], space), "/block");
expect("the space's folder last", focusedFolder({ pane: "gone" }, [], space), "/space");
expect("nothing focused and no space", focusedFolder(null, [], null), null);

// The watcher asks again on a new branch and after a while, never on every tick.
const key = keyOf("/repo", "feature/a");
expect("no folder has no key", keyOf(null, "main"), null);
expect("first ask", isStale(undefined, key, 0), true);
expect("same branch, fresh answer", isStale({ key, at: 1000 }, key, 1000 + REFRESH_MS - 1), false);
expect("same branch, old answer", isStale({ key, at: 1000 }, key, 1000 + REFRESH_MS), true);
expect("another branch", isStale({ key, at: 1000 }, keyOf("/repo", "feature/b"), 1001), true);

// A page acts and draws only for the pull request the watcher points at now, and loads again when it is behind.
const state = { status: "open", cwd: "/a", number: 7, updatedAt: "2026-11-06T08:00:00Z" };
const page = { cwd: "/a", number: 7, updatedAt: "2026-11-06T08:00:00Z", at: 1000, pr: { number: 7, headRefOid: "a".repeat(40) } };
expect("the page of the pull request on screen is current", isCurrent(page, state), true);
expect("the same number in another folder is not", isCurrent(page, { ...state, cwd: "/b" }), false);
expect("another pull request of the folder is not", isCurrent(page, { ...state, number: 8 }), false);
expect("nothing is current without an open pull request", isCurrent(page, { status: "error", cwd: "/a", number: 7 }), false);
expect("a current page is kept", needsLoad(page, state, 1000 + REFRESH_MS - 1), false);
expect("another folder loads", needsLoad(page, { ...state, cwd: "/b" }, 1001), true);
expect("a newer pull request loads", needsLoad(page, { ...state, updatedAt: "2026-11-06T09:00:00Z" }, 1001), true);
expect("a page loaded after the watcher asked is kept", needsLoad({ ...page, updatedAt: "2026-11-06T09:00:00Z" }, state, 1001), false);
expect("an old page loads, finished checks do not move updatedAt", needsLoad(page, state, 1000 + REFRESH_MS), true);
expect("nothing loads without an open pull request", needsLoad(null, { status: "none" }, 1001), false);

const rollup = [
  { __typename: "CheckRun", name: "lint", status: "COMPLETED", conclusion: "SUCCESS", detailsUrl: "https://ci/lint", workflowName: "Lint" },
  { __typename: "CheckRun", name: "build", status: "IN_PROGRESS", conclusion: "", detailsUrl: "https://ci/build", workflowName: "Build" },
  { __typename: "StatusContext", context: "deploy", state: "FAILURE", targetUrl: "https://ci/deploy" },
  { __typename: "CheckRun", name: "docs", status: "COMPLETED", conclusion: "SKIPPED", detailsUrl: "https://ci/docs", workflowName: "Docs" },
];
const rows = checkRows(rollup);
expect("checks order failed, running, passed, skipped", rows.map((row) => `${row.name}:${row.state}`), ["deploy:failure", "build:pending", "lint:success", "docs:skipped"]);
expect("checks summary", checksSummary(rows), "1 failed · 1 running · 1 passed · 1 skipped");
expect("no checks", checksSummary([]), "No checks");

expect("a pending request wins over an older verdict", reviewers({
  latestReviews: [{ author: { login: "alice" }, state: "CHANGES_REQUESTED" }, { author: { login: "bob" }, state: "APPROVED" }],
  reviewRequests: [{ login: "alice" }, { name: "Core team" }],
}), [{ name: "alice", state: "REQUESTED" }, { name: "bob", state: "APPROVED" }, { name: "Core team", state: "REQUESTED" }]);

const entries = timeline({
  comments: [{ author: { login: "alice" }, body: "Looks close.", createdAt: "2026-11-06T10:00:00Z" }],
  reviews: [
    { author: { login: "bob" }, state: "COMMENTED", body: "", submittedAt: "2026-11-06T09:00:00Z" },
    { author: { login: "bob" }, state: "APPROVED", body: "Ship it.", submittedAt: "2026-11-06T11:00:00Z" },
  ],
}, [
  { id: 2, in_reply_to_id: 1, user: { login: "carol" }, body: "Done.", created_at: "2026-11-06T09:30:00Z", path: "a.js", line: 3 },
  { id: 1, in_reply_to_id: null, user: { login: "bob" }, body: "Rename this.", created_at: "2026-11-06T09:00:00Z", path: "a.js", line: 3 },
  { id: 3, in_reply_to_id: null, user: { login: "bob" }, body: "Old spot.", created_at: "2026-11-06T09:10:00Z", path: "b.js", line: null, original_line: 9 },
]);
expect("timeline order and kinds", entries.map((entry) => entry.kind), ["thread", "thread", "comment", "review"]);
expect("a reply joins its thread", entries[0].comments.map((comment) => comment.author), ["bob", "carol"]);
expect("an outdated thread keeps its old line", [entries[1].line, entries[1].outdated], [9, true]);

const diff = [
  "diff --git a/a.sql b/a.sql",
  "index 1..2 100644",
  "--- a/a.sql",
  "+++ b/a.sql",
  "@@ -1,2 +1,2 @@",
  " select 1;",
  "--- an old comment",
  "+-- a new comment",
  "diff --git a/b.js b/b.js",
  "new file mode 100644",
  "--- /dev/null",
  "+++ b/b.js",
  "@@ -0,0 +1 @@",
  "+export {};",
  "diff --git a/docs/a b/c.md b/docs/a b/c.md",
  "--- a/docs/a b/c.md",
  "+++ b/docs/a b/c.md",
  "@@ -1 +1 @@",
  "-old",
  "+new",
  "",
].join("\n");
const files = diffFiles(diff);
expect("one entry per file, a path with ` b/` in it whole", files.map((file) => file.path), ["a.sql", "b.js", "docs/a b/c.md"]);
expect("a deleted SQL comment is a deletion, not a header", files[0].lines.map((line) => line.kind), ["hunk", "context", "delete", "add"]);
expect("counts", files.map((file) => [file.additions, file.deletions]), [[1, 1], [1, 0], [1, 1]]);

expect("a thread is replied to through its first comment", entries[0].id, 1);

// Rerun takes each failed Actions run once, a status or another host is left alone.
expect("failed runs", failedRuns([
  { run: true, state: "failure", url: "https://github.com/o/r/actions/runs/11/job/1" },
  { run: true, state: "failure", url: "https://github.com/o/r/actions/runs/11/job/2" },
  { run: true, state: "failure", url: "https://ci.example/deploy" },
  { run: true, state: "failure", url: "https://evil.example/o/r/actions/runs/13" },
  { run: false, state: "failure", url: "https://github.com/o/r/actions/runs/14" },
  { run: true, state: "success", url: "https://github.com/o/r/actions/runs/12/job/3" },
]), ["11"]);

// An image is never drawn, so it is never fetched without a click.
expect("a markdown image becomes a link", withoutImages("see ![shot](https://x.example/p.png?pr=7)"), "see [shot](https://x.example/p.png?pr=7)");
expect("an HTML image becomes a link", withoutImages('a <img width="9" src="https://x.example/p.png"> b'), "a [image](https://x.example/p.png) b");
expect("an HTML image without a source is dropped", withoutImages("a <img alt=x> b"), "a  b");

// Every text is glued to its flag, so a body that looks like a flag or a file stays text.
const pr = { number: 7, headRefOid: "a".repeat(40) };
expect("a comment", actionArgs("comment", pr, { body: " --admin " }), ["pr", "comment", "7", "--body=--admin"]);
expect("an empty comment is not sent", actionArgs("comment", pr, { body: "  " }), null);
expect("an approval is pinned to the commit on screen and needs no text", actionArgs("approve", pr, {}), ["api", "--method", "POST", "repos/{owner}/{repo}/pulls/7/reviews", "-f", "event=APPROVE", "-f", `commit_id=${"a".repeat(40)}`]);
expect("an approval body is a raw field", actionArgs("approve", pr, { body: "@/etc/hosts" }).slice(-2), ["-f", "body=@/etc/hosts"]);
expect("an approval without a known commit is not sent", actionArgs("approve", { number: 7 }, {}), null);
expect("a change request needs text", actionArgs("request-changes", pr, { body: "" }), null);
expect("a reply is a raw field, never a file", actionArgs("reply", pr, { body: "@/etc/hosts", threadId: 1 }), ["api", "--method", "POST", "repos/{owner}/{repo}/pulls/7/comments/1/replies", "-f", "body=@/etc/hosts"]);
expect("a merge is pinned to the commit on screen", actionArgs("merge", pr, { method: "squash" }), ["pr", "merge", "7", "--squash", `--match-head-commit=${"a".repeat(40)}`]);
expect("a merge without a known commit is not sent", actionArgs("merge", { number: 7 }, { method: "squash" }), null);
expect("an unknown merge method is not sent", actionArgs("merge", pr, { method: "admin" }), null);
expect("a rerun takes a run number only", actionArgs("rerun", pr, { runId: "11 --x" }), null);
expect("an unknown action is not sent", actionArgs("delete", pr, {}), null);
expect("no pull request number, nothing is sent", actionArgs("close", { number: "7; rm" }, {}), null);

// Merge and close act on the second click, for the same folder, pull request and commit, not a double-click, not much later.
const id = armId(page);
const arm = { action: "merge", id, at: 1000 };
expect("a double-click does not merge", confirmed(arm, "merge", id, 1000 + DOUBLE_CLICK_MS - 1), false);
expect("a second click merges", confirmed(arm, "merge", id, 1000 + DOUBLE_CLICK_MS), true);
expect("a late click arms again", isArmed(arm, "merge", id, 1000 + CONFIRM_MS), false);
expect("a new commit needs a new confirm", confirmed(arm, "merge", armId({ ...page, pr: { headRefOid: "b".repeat(40) } }), 2000), false);
expect("the same number in another folder needs a new confirm", confirmed(arm, "merge", armId({ ...page, cwd: "/b" }), 2000), false);
expect("another button needs its own confirm", confirmed(arm, "close", id, 2000), false);

if (failures > 0) process.exit(1);
console.log("PASS: pull-request");
