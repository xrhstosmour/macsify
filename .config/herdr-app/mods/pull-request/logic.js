// The rules of the `pull-request` mod, free of the `herdr` module so
// `tests/pull-request.sh` can run them in Node: which `gh` answers mean an open
// pull request, no pull request, or a failure to show, how its checks,
// reviewers, conversation and diff are laid out, and which `gh` call each button makes.

// Where the watcher shares its answer, `tabs-inline` reads it by this name to show the GitHub button.
export const STATE_KEY = "pull-request.state";

// What the watcher asks for, small, so asking every couple of minutes stays cheap.
export const SUMMARY_FIELDS = ["number", "state", "title", "url", "updatedAt"];
export const DETAIL_FIELDS = [
  "number", "title", "url", "state", "isDraft", "headRefOid", "author", "body", "baseRefName", "headRefName",
  "additions", "deletions", "changedFiles", "mergeable", "reviewDecision", "labels",
  "reviewRequests", "latestReviews", "reviews", "comments", "commits", "statusCheckRollup", "createdAt", "updatedAt",
];
// How long an answer, an error included, is kept before `gh` is asked again for the same branch.
export const REFRESH_MS = 120000;
// `exec` has no timeout, a `gh` call stalled on the network is given up after this.
export const STUCK_MS = 60000;
// How long the branch `git` named for a folder is trusted, a checkout in the same folder shows within it.
export const BRANCH_MS = 3000;

// `gh` says these when the folder simply has no pull request to show, which hides
// the button, anything else is a failure the person should see.
const NO_PULL_REQUEST = [
  /no pull requests found/i,
  /not a git repository/i,
  /none of the git remotes/i,
  /no git remotes/i,
];

// The live folder of the focused terminal, found as the shipped `changes` mod finds
// it: a pane by `focused().pane`, a terminal block by its own folder, the space last.
export function focusedFolder(focus, list, space) {
  const pane = focus?.pane ? list.find((each) => each.pane === focus.pane) : null;
  return pane?.cwd || focus?.cwd || space?.folder || null;
}

export function keyOf(cwd, branch) {
  return cwd && branch ? `${cwd}\n${branch}` : null;
}

// Whether the watcher asks `gh` again: a new folder or branch, or an old answer.
export function isStale(entry, key, now) {
  return !entry || entry.key !== key || now - entry.at >= REFRESH_MS;
}

// `result` is an `exec` result, or `{ error }` when `gh` could not start. Only an
// open pull request shows, a merged or closed one of the branch is no pull request.
export function classify(result) {
  if (result.error) return { status: "error", message: result.error };
  if (result.code !== 0) {
    const text = (result.stderr || result.stdout || "").trim();
    if (NO_PULL_REQUEST.some((pattern) => pattern.test(text))) return { status: "none" };
    return { status: "error", message: text.split("\n")[0] || `gh exited with ${result.code}` };
  }
  let pr;
  try {
    pr = JSON.parse(result.stdout);
  } catch {
    return { status: "error", message: "gh returned something that is not JSON" };
  }
  if (pr?.state !== "OPEN") return { status: "none" };
  // The number goes to `gh` as an argument, so only a positive integer is trusted.
  if (!Number.isInteger(pr.number) || pr.number < 1) return { status: "error", message: "gh returned a pull request without a number" };
  return { status: "open", number: pr.number, title: pr.title, url: pr.url, updatedAt: pr.updatedAt };
}

const FAILED = new Set(["FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"]);
const SKIPPED = new Set(["SKIPPED", "NEUTRAL", "STALE"]);
const ORDER = { failure: 0, pending: 1, success: 2, skipped: 3 };

// A check run or a commit status, as one row: failed first, then running, passed, skipped.
export function checkRows(rollup) {
  return (rollup ?? []).map((check) => {
    const run = check.__typename === "CheckRun";
    const result = run ? (check.status === "COMPLETED" ? check.conclusion : "PENDING") : check.state;
    const state = FAILED.has(result) ? "failure" : SKIPPED.has(result) ? "skipped" : result === "SUCCESS" ? "success" : "pending";
    return { name: run ? check.name : check.context, workflow: run ? check.workflowName ?? "" : "", state, url: run ? check.detailsUrl : check.targetUrl, run };
  }).sort((a, b) => ORDER[a.state] - ORDER[b.state] || a.name.localeCompare(b.name));
}

export function checksSummary(rows) {
  const count = (state) => rows.filter((row) => row.state === state).length;
  const parts = [[count("failure"), "failed"], [count("pending"), "running"], [count("success"), "passed"], [count("skipped"), "skipped"]];
  return parts.filter(([n]) => n > 0).map(([n, word]) => `${n} ${word}`).join(" · ") || "No checks";
}

// Everyone asked to review, with their latest verdict, a pending request wins over an older verdict.
export function reviewers(pr) {
  const rows = new Map();
  for (const review of pr.latestReviews ?? []) {
    const name = review.author?.login;
    if (name) rows.set(name, review.state);
  }
  for (const request of pr.reviewRequests ?? []) {
    const name = request.login ?? request.name ?? request.slug;
    if (name) rows.set(name, "REQUESTED");
  }
  return [...rows].map(([name, state]) => ({ name, state }));
}

// The conversation tab: comments, reviews and inline threads by time. `inline` is
// the REST list of review comments, a reply joins the thread of its first comment.
// A review that only carried inline comments says nothing of its own and is left out.
export function timeline(pr, inline) {
  const entries = [];
  for (const comment of pr.comments ?? []) {
    entries.push({ kind: "comment", author: comment.author?.login ?? "ghost", body: comment.body ?? "", at: comment.createdAt });
  }
  for (const review of pr.reviews ?? []) {
    if (review.state === "COMMENTED" && !review.body) continue;
    entries.push({ kind: "review", author: review.author?.login ?? "ghost", state: review.state, body: review.body ?? "", at: review.submittedAt });
  }
  const threads = new Map();
  for (const comment of [...(inline ?? [])].sort((a, b) => a.created_at.localeCompare(b.created_at))) {
    const entry = { author: comment.user?.login ?? "ghost", body: comment.body ?? "", at: comment.created_at };
    const thread = threads.get(comment.in_reply_to_id);
    if (thread) {
      thread.comments.push(entry);
      continue;
    }
    const root = { kind: "thread", id: comment.id, path: comment.path, line: comment.line ?? comment.original_line ?? null, outdated: comment.line == null, at: comment.created_at, comments: [entry] };
    threads.set(comment.id, root);
    entries.push(root);
  }
  return entries.sort((a, b) => (a.at ?? "").localeCompare(b.at ?? ""));
}

// Whether the loaded page is the pull request the watcher points at now. A write
// runs only then, so a page left from another folder never acts on that folder's
// pull request of the same number.
export function isCurrent(view, state) {
  return Boolean(view) && state?.status === "open" && view.cwd === state.cwd && view.number === state.number;
}

// The panel loads the page again for another pull request, a newer one on
// GitHub, or an old page, since a finished check does not move `updatedAt`.
export function needsLoad(view, state, now) {
  if (state?.status !== "open") return false;
  return !isCurrent(view, state) || (state.updatedAt ?? "") > (view.updatedAt ?? "") || now - view.at >= REFRESH_MS;
}

// Whether the block `id` is on screen in the `layout()` tree: no hidden block on
// its way and the shown child of every stack, the first one when it names none.
// Timers run while a block is hidden, so the panel asks this before calling `gh`.
export function isShown(node, id) {
  if (!node || node.hidden) return false;
  if (node.id === id) return true;
  const children = node.children ?? [];
  const shown = node.type === "stack" ? [children.find((child) => child.id === node.active) ?? children[0]] : children;
  return shown.some((child) => isShown(child, id));
}

// The Files changed tab: `gh pr diff` cut into one entry per file, each line tagged
// so the view colors it without parsing again.
export function diffFiles(diff) {
  const files = [];
  let file = null;
  for (const line of (diff ?? "").split("\n")) {
    if (line.startsWith("diff --git ")) {
      // Unrenamed, the line is `a/<path> b/<path>`, so its halves give the path even with ` b/` inside it.
      const names = line.slice("diff --git ".length), half = (names.length - 1) / 2;
      const same = Number.isInteger(half) && names.slice(2, half) === names.slice(half + 3);
      file = { path: same ? names.slice(2, half) : line.replace(/^diff --git a\/.* b\//, ""), additions: 0, deletions: 0, lines: [] };
      files.push(file);
      continue;
    }
    if (!file) continue;
    // The file header ends at the first hunk, after it a `--- ` line is a deleted `-- ` line.
    if (!file.lines.length && !line.startsWith("@@")) continue;
    const kind = line.startsWith("@@") ? "hunk" : line.startsWith("+") ? "add" : line.startsWith("-") ? "delete" : "context";
    if (kind === "add") file.additions += 1;
    if (kind === "delete") file.deletions += 1;
    file.lines.push({ kind, text: line });
  }
  // The split leaves the newline at the very end as an empty context line.
  for (const each of files) {
    const last = each.lines.at(-1);
    if (last?.kind === "context" && last.text === "") each.lines.pop();
  }
  return files;
}

// A failed GitHub Actions check links to its run, the run is what `gh` reruns. Only a
// check run on github.com counts, a commit status can carry any URL and would pick
// another run of the repository.
export function runIdOf(url) {
  return /^https:\/\/github\.com\/[^/]+\/[^/]+\/actions\/runs\/(\d+)(?:\/|$)/.exec(url ?? "")?.[1] ?? null;
}

export function failedRuns(rows) {
  return [...new Set(rows.filter((row) => row.run && row.state === "failure").map((row) => runIdOf(row.url)).filter(Boolean))];
}

// Anyone can put an image in a pull request, and drawing it would fetch it with no
// click, telling its host who opened the page and when. It becomes a link instead.
export function withoutImages(text) {
  return (text ?? "")
    .replace(/<img\b[^>]*?\bsrc\s*=\s*["']?([^"'\s>]+)[^>]*>/gi, "[image]($1)")
    .replace(/<img\b[^>]*>/gi, "")
    .replace(/!\[/g, "[");
}

// GitHub's order, the first one the repository allows is the one its merge box offers first.
export const MERGE_METHODS = ["rebase", "merge", "squash"];
export const MERGE_LABELS = { rebase: "Rebase and merge", merge: "Create a merge commit", squash: "Squash and merge" };
// What the merge box needs that `gh pr view` does not give: the methods the
// repository allows, its merge queue, whether the branch is behind, and whether
// the viewer may bypass the rules. `{owner}` and `{repo}` are filled in by `gh` from the folder.
export const MERGE_QUERY = "query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){mergeCommitAllowed rebaseMergeAllowed squashMergeAllowed pullRequest(number:$number){id isMergeQueueEnabled isInMergeQueue mergeQueueEntry{position} mergeStateStatus viewerCanMergeAsAdmin}}}";

// The mutations GitHub's own Merge when ready and Remove from queue buttons call,
// enqueue pinned to the commit on screen like a merge.
const ENQUEUE = "mutation($id:ID!,$oid:GitObjectID!){enqueuePullRequest(input:{pullRequestId:$id,expectedHeadOid:$oid}){mergeQueueEntry{position}}}";
const DEQUEUE = "mutation($id:ID!){dequeuePullRequest(input:{id:$id}){mergeQueueEntry{position}}}";
const NODE_ID = /^PR_[A-Za-z0-9_-]+$/;
const OID = /^[0-9a-f]{40}$/;

// The `MERGE_QUERY` answer as the merge box reads it, null when GitHub did not answer it.
export function mergeOptions(answer) {
  const repo = answer?.data?.repository, pr = repo?.pullRequest;
  if (!pr) return null;
  const allowed = { rebase: repo.rebaseMergeAllowed, merge: repo.mergeCommitAllowed, squash: repo.squashMergeAllowed };
  return { id: pr.id, methods: MERGE_METHODS.filter((method) => allowed[method]), queue: Boolean(pr.isMergeQueueEnabled), queued: Boolean(pr.isInMergeQueue), position: pr.mergeQueueEntry?.position ?? null, state: pr.mergeStateStatus ?? null, canBypass: Boolean(pr.viewerCanMergeAsAdmin) };
}

// `fixup!`, `squash!` and `amend!` commits are meant to be squashed before the merge,
// GitHub would land them as they are.
export function unsquashed(commits) {
  return (commits ?? []).filter((commit) => /^(fixup|squash|amend)! /.test(commit.messageHeadline ?? "")).length;
}

// The rows of GitHub's merge box, in its words, each with a tone: "good", "bad", "warn" or "muted".
export function mergeStatus(pr, rows, merge) {
  const lines = [];
  const decision = { APPROVED: ["Changes approved", "good"], CHANGES_REQUESTED: ["Changes requested", "bad"], REVIEW_REQUIRED: ["Review required", "warn"] }[pr.reviewDecision];
  if (decision) lines.push({ text: decision[0], tone: decision[1] });
  if (rows.some((row) => row.state === "failure")) lines.push({ text: "Some checks were not successful", tone: "bad" });
  else if (rows.some((row) => row.state === "pending")) lines.push({ text: "Some checks haven't completed yet", tone: "warn" });
  else if (rows.length) lines.push({ text: "All checks have passed", tone: "good" });
  if (pr.isDraft) lines.push({ text: "This pull request is still a work in progress", tone: "muted" });
  else if (pr.mergeable === "CONFLICTING") lines.push({ text: "This branch has conflicts that must be resolved", tone: "bad" });
  else if (merge?.state === "BEHIND") lines.push({ text: "This branch is out-of-date with the base branch", tone: "warn" });
  else if (pr.mergeable === "MERGEABLE") lines.push({ text: "No conflicts with base branch", tone: "good" });
  const fixups = unsquashed(pr.commits);
  if (fixups) lines.push({ text: `${fixups} fixup! ${fixups === 1 ? "commit is" : "commits are"} left, squash ${fixups === 1 ? "it" : "them"} before merging`, tone: "bad" });
  if (merge?.queued) lines.push({ text: merge.position ? `Queued to merge, position ${merge.position}` : "Queued to merge", tone: "warn" });
  else if (merge?.queue) lines.push({ text: `This repository uses the merge queue for all merges into the ${pr.baseRefName} branch.`, tone: "muted" });
  return lines;
}

// Whether the merge box offers a merge at all. GitHub itself refuses a merge its rules
// do not allow, so only what it can never take is held here: a draft, conflicts,
// no answer about how the repository merges, and `fixup!` commits that are meant
// to be squashed by a local rebase and a force push, which the panel never does.
export function canMerge(pr, merge) {
  return Boolean(merge) && !pr.isDraft && pr.mergeable !== "CONFLICTING" && unsquashed(pr.commits) === 0 && !merge.queued && (merge.queue || merge.methods.length > 0);
}

// Merge, merge when ready and close take a second click on the same button, for the
// same folder, pull request and commit (`id`), within this window, as GitHub asks to confirm.
export const CONFIRM_MS = 6000;
// A second click sooner than this is a double-click, not a decision.
export const DOUBLE_CLICK_MS = 400;

export function armId(view) {
  return `${view.cwd}\n${view.number}\n${view.pr?.headRefOid}`;
}

export function isArmed(arm, action, id, now) {
  return Boolean(arm) && arm.action === action && arm.id === id && now - arm.at < CONFIRM_MS;
}

export function confirmed(arm, action, id, now) {
  return isArmed(arm, action, id, now) && now - arm.at >= DOUBLE_CLICK_MS;
}

// The `gh` arguments of a button, or null when its input is not something to send.
// They go to `exec` as a list, no shell, and every text rides as `--flag=value` or
// `-f key=value`, so a body starting with `-` or `@` is never read as a flag or a file.
export function actionArgs(action, pr, input = {}) {
  const number = Number.isInteger(pr?.number) && pr.number > 0 ? String(pr.number) : null;
  if (!number) return null;
  const body = (input.body ?? "").trim();
  switch (action) {
    case "comment":
      return body ? ["pr", "comment", number, `--body=${body}`] : null;
    case "approve":
      // Pinned to the commit on screen like GitHub's button, a later push is not approved with it.
      return OID.test(pr.headRefOid ?? "") ? ["api", "--method", "POST", `repos/{owner}/{repo}/pulls/${number}/reviews`, "-f", "event=APPROVE", "-f", `commit_id=${pr.headRefOid}`, ...(body ? ["-f", `body=${body}`] : [])] : null;
    case "request-changes":
      return body ? ["pr", "review", number, "--request-changes", `--body=${body}`] : null;
    case "reply":
      return body && Number.isInteger(input.threadId) ? ["api", "--method", "POST", `repos/{owner}/{repo}/pulls/${number}/comments/${input.threadId}/replies`, "-f", `body=${body}`] : null;
    case "merge":
      // Pinned to the commit on screen, GitHub refuses it when someone pushed since. `--admin`
      // is GitHub's bypass rules box, only ever sent when the person ticked it.
      return MERGE_METHODS.includes(input.method) && OID.test(pr.headRefOid ?? "") ? ["pr", "merge", number, `--${input.method}`, `--match-head-commit=${pr.headRefOid}`, ...(input.bypass === true ? ["--admin"] : [])] : null;
    case "enqueue":
      return NODE_ID.test(input.id ?? "") && OID.test(pr.headRefOid ?? "") ? ["api", "graphql", "-f", `query=${ENQUEUE}`, "-f", `id=${input.id}`, "-f", `oid=${pr.headRefOid}`] : null;
    case "dequeue":
      return NODE_ID.test(input.id ?? "") ? ["api", "graphql", "-f", `query=${DEQUEUE}`, "-f", `id=${input.id}`] : null;
    case "close":
      return ["pr", "close", number];
    case "ready":
      return ["pr", "ready", number];
    case "draft":
      return ["pr", "ready", number, "--undo"];
    case "rerun":
      return /^\d+$/.test(input.runId ?? "") ? ["run", "rerun", input.runId, "--failed"] : null;
    default:
      return null;
  }
}
