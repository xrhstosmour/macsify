// Runs `sweepWorktree` from the `Herdr` app's `worktree-cleanup` mod against real
// temporary `git` repositories. Started by `tests/worktree-cleanup-application.sh`.
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const logicUrl = new URL("../.config/herdr-app/mods/worktree-cleanup/logic.js", import.meta.url);
const { discoverWorktrees, sweepWorktree, parseProtected, isProtected, isOccupiedBy, linkedWorktreeRoot, removalNotice, trackedWorktree } = await import(fileURLToPath(logicUrl));

const base = realpathSync(mkdtempSync(join(tmpdir(), "worktree-cleanup-")));
let failures = 0;
let mergedHeads = null;
// Set by a test to make every network call reject, as the app's `exec` does after its time limit.
let networkDown = false;

function fail(message) {
  console.log(`FAIL: ${message}`);
  failures += 1;
}

function git(cwd, ...args) {
  return execFileSync("git", args, { cwd, encoding: "utf8", env: { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.com", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.com" } }).trim();
}

// The same shape as the app's `exec`: resolves on a nonzero exit, rejects when it cannot start.
async function exec(command, args, options = {}) {
  // Network calls go through `env VARIABLE=value command`, run the command itself.
  if (command === "env") {
    if (networkDown) throw new Error("timed out");
    const rest = args.filter((argument, index) => !(argument.includes("=") && args.slice(0, index + 1).every((earlier) => earlier.includes("="))));
    return exec(rest[0], rest.slice(1), options);
  }
  // The merged pull request heads `gh pr list` would print, set by a test.
  if (command === "gh") return mergedHeads === null ? { code: 1, stdout: "", stderr: "no gh in tests" } : { code: 0, stdout: mergedHeads, stderr: "" };
  const result = spawnSync(command, args, { cwd: options.cwd, encoding: "utf8", env: { ...process.env, GIT_TERMINAL_PROMPT: "0" } });
  if (result.error) throw result.error;
  return { code: result.status, stdout: result.stdout, stderr: result.stderr };
}

// An `origin` with `main`, a clone of it, and a helper to add a linked worktree on a new branch.
const origin = join(base, "origin.git");
const checkout = join(base, "checkout");
execFileSync("git", ["init", "--bare", "--initial-branch=main", origin]);
git(base, "clone", "--quiet", origin, checkout);
git(checkout, "checkout", "--quiet", "-B", "main");
writeFileSync(join(checkout, "file"), "one\n");
git(checkout, "add", "file");
git(checkout, "commit", "--quiet", "-m", "first");
git(checkout, "push", "--quiet", "origin", "main");
git(checkout, "remote", "set-head", "origin", "main");

function worktree(name, { commit = false, merge = false } = {}) {
  const path = join(base, "worktrees", name);
  mkdirSync(join(base, "worktrees"), { recursive: true });
  git(checkout, "worktree", "add", "--quiet", "-b", `feature/${name}`, path);
  if (commit) {
    writeFileSync(join(path, `${name}.txt`), name);
    git(path, "add", ".");
    git(path, "commit", "--quiet", "-m", `work on ${name}`);
  }
  if (merge) {
    git(checkout, "merge", "--quiet", "--no-ff", "-m", "merge", `feature/${name}`);
    git(checkout, "push", "--quiet", "origin", "main");
  }
  return path;
}

async function check(label, path, expectedOutcome, expectGone, options = {}) {
  const { outcome, reason } = await sweepWorktree(path, { exec, ...options });
  if (outcome !== expectedOutcome) fail(`${label}: outcome '${outcome}' (${reason}), wanted '${expectedOutcome}'`);
  if (existsSync(path) === expectGone) fail(`${label}: worktree ${expectGone ? "still exists" : "was removed"}`);
}

const branchExists = (name) => git(checkout, "branch", "--list", `feature/${name}`) !== "";

// Merged and clean: the worktree and its branch go.
const merged = worktree("merged", { commit: true, merge: true });
await check("merged and clean", merged, "removed", true);
if (branchExists("merged")) fail("the merged branch was not deleted");

// A branch with no commits of its own is already on the default branch.
await check("fresh branch", worktree("fresh"), "removed", true);

// Work not merged: the worktree is kept whole, its branch too.
const unmerged = worktree("unmerged", { commit: true });
await check("not merged", unmerged, "kept", false);
if (!branchExists("unmerged")) fail("an unmerged branch was deleted");

// Not merged but pushed in full: the remote holds every commit, so the worktree and branch go.
// A commit made after the push is only here, so it stays.
const pushed = worktree("pushed", { commit: true });
git(pushed, "push", "--quiet", "origin", "feature/pushed");
await check("pushed in full", pushed, "removed", true);
if (branchExists("pushed")) fail("a branch pushed in full was not deleted");
const pushedMore = worktree("pushed-more", { commit: true });
git(pushedMore, "push", "--quiet", "origin", "feature/pushed-more");
writeFileSync(join(pushedMore, "after.txt"), "after");
git(pushedMore, "add", ".");
git(pushedMore, "commit", "--quiet", "-m", "after the push");
await check("commit after the push", pushedMore, "kept", false);
if (!branchExists("pushed-more")) fail("a branch with an unpushed commit was deleted");

// A squash merge cannot be seen by ancestry, a merged pull request whose head is the
// branch tip proves it. A head from before later commits does not.
const squashed = worktree("squashed", { commit: true });
mergedHeads = `${git(squashed, "rev-parse", "HEAD~0")}\n`;
await check("merged as a pull request", squashed, "removed", true);
if (branchExists("squashed")) fail("a branch merged as a pull request was not deleted");
const stale = worktree("stale", { commit: true });
mergedHeads = `${git(stale, "rev-parse", "HEAD")}\n`;
writeFileSync(join(stale, "later.txt"), "later");
git(stale, "add", ".");
git(stale, "commit", "--quiet", "-m", "after the merge");
await check("commits after the pull request merged", stale, "kept", false);
mergedHeads = null;

// A merge check that times out keeps the worktree, even where the pull request would prove it merged.
const slow = worktree("slow", { commit: true });
mergedHeads = `${git(slow, "rev-parse", "HEAD")}\n`;
networkDown = true;
await check("merge check timed out", slow, "kept", false);
networkDown = false;
mergedHeads = null;

// A terminal opened during the merge check keeps a worktree that is otherwise removable.
await check("pane reopened before removal", worktree("reopened", { commit: true, merge: true }), "kept", false, { isOccupied: async () => true });

// A terminal reached through a symlink still occupies the worktree git resolved, so it is kept.
const linkedThrough = worktree("linked", { commit: true, merge: true });
const link = join(base, "link");
symlinkSync(join(base, "worktrees"), link);
const terminalFolder = join(link, "linked");
const rootOf = (folder) => linkedWorktreeRoot(exec, folder);
if ((await linkedWorktreeRoot(exec, terminalFolder)) !== linkedThrough) fail("a symlinked folder did not resolve to its worktree");
if (await isOccupiedBy(linkedThrough, [join(base, "worktrees", "unmerged")], rootOf)) fail("a terminal in another worktree occupied this one");
await check("terminal through a symlink", linkedThrough, "kept", false, { isOccupied: () => isOccupiedBy(linkedThrough, [terminalFolder], rootOf) });

// A terminal is tracked only inside the roots, as spelled and as git resolves it.
const roots = [join(base, "worktrees")];
if ((await trackedWorktree(rootOf, terminalFolder, [join(base, "link-root")])) !== null) fail("a folder outside the roots was tracked");
if ((await trackedWorktree(rootOf, join(base, "worktrees-old", "x"), roots)) !== null) fail("a folder next to a root, sharing its prefix, was tracked");
if ((await trackedWorktree(rootOf, join(base, "worktrees", "linked"), roots)) !== linkedThrough) fail("a worktree inside the roots was not tracked");
const outside = join(base, "outside");
git(checkout, "worktree", "add", "--quiet", "-b", "feature/outside", outside);
symlinkSync(outside, join(base, "worktrees", "escape"));
if ((await trackedWorktree(rootOf, join(base, "worktrees", "escape"), roots)) !== null) fail("a symlink inside the roots tracked a worktree outside them");

// The toast cuts its body to one line, so the project goes in the title and only the folder in the body.
const notice = (path) => JSON.stringify(removalNotice(path, ["/w", "/h"]));
if (notice("/w/project/fix-typo") !== JSON.stringify({ title: "Worktree removed in project", body: "fix-typo" })) fail(`a project worktree's notice was ${notice("/w/project/fix-typo")}`);
if (notice("/h/fix-typo") !== JSON.stringify({ title: "Worktree removed", body: "fix-typo" })) fail(`a worktree straight under a root got ${notice("/h/fix-typo")}`);

// Merged but dirty or untracked: kept.
const dirty = worktree("dirty", { commit: true, merge: true });
writeFileSync(join(dirty, "dirty.txt"), "changed");
await check("modified file", dirty, "kept", false);
const untracked = worktree("untracked", { commit: true, merge: true });
writeFileSync(join(untracked, "new-file"), "never added");
await check("untracked file", untracked, "kept", false);

// Detached HEAD: removed on a merged commit, kept on one only reachable from here.
const detached = worktree("detached", { commit: true, merge: true });
git(detached, "checkout", "--quiet", "--detach");
await check("detached HEAD merged", detached, "removed", true);
const detachedUnmerged = worktree("detached-unmerged", { commit: true });
git(detachedUnmerged, "checkout", "--quiet", "--detach");
await check("detached HEAD not merged", detachedUnmerged, "kept", false);

// A worktree found by the scan, not by a terminal, goes only when a commit made in it is merged and it is idle.
const scanned = join(base, "scanned");
mkdirSync(join(scanned, "project"), { recursive: true });
git(checkout, "worktree", "add", "--quiet", "-b", "feature/scanned-pushed", join(scanned, "project", "pushed"));
git(checkout, "worktree", "add", "--quiet", "-b", "feature/scanned-fresh", join(scanned, "project", "fresh"));
const found = await discoverWorktrees(exec, [scanned]);
if (found.length !== 2 || !found.includes(join(scanned, "project", "fresh"))) fail(`the scan found ${JSON.stringify(found)}`);
if ((await discoverWorktrees(exec, [join(base, "missing")])).length !== 0) fail("a missing root yielded worktrees");
const scannedPushed = join(scanned, "project", "pushed");
writeFileSync(join(scannedPushed, "pushed.txt"), "pushed");
git(scannedPushed, "add", ".");
git(scannedPushed, "commit", "--quiet", "-m", "pushed work");
git(scannedPushed, "push", "--quiet", "origin", "feature/scanned-pushed");
await check("scanned and pushed, not merged", scannedPushed, "kept", false, { allowPushed: false });
await check("scanned and fresh, active", join(scanned, "project", "fresh"), "kept", false, { allowPushed: false, idleMinutes: 60 });
const age = (path) => {
  execFileSync("find", [path, git(path, "rev-parse", "--path-format=absolute", "--git-dir"), "-maxdepth", "1", "-exec", "touch", "-t", "202001010000", "{}", "+"]);
  // A sweep that kept it ran `git status`, which must not count as activity.
  git(path, "update-index", "--really-refresh");
};
// Fresh looks merged, its tip is the default branch, yet an agent may be about to start in it.
const scannedFresh = join(scanned, "project", "fresh");
age(scannedFresh);
await check("scanned and fresh, idle", scannedFresh, "kept", false, { allowPushed: false, idleMinutes: 60 });
const scannedMerged = join(scanned, "project", "merged");
git(checkout, "worktree", "add", "--quiet", "-b", "feature/scanned-merged", scannedMerged);
writeFileSync(join(scannedMerged, "scanned-merged.txt"), "scanned merged");
git(scannedMerged, "add", ".");
git(scannedMerged, "commit", "--quiet", "-m", "merged work");
git(checkout, "merge", "--quiet", "--no-ff", "-m", "merge", "feature/scanned-merged");
git(checkout, "push", "--quiet", "origin", "main");
age(scannedMerged);
await check("scanned, merged and idle", scannedMerged, "removed", true, { allowPushed: false, idleMinutes: 60 });

// A rebase in progress: kept.
const rebasing = worktree("rebasing", { commit: true, merge: true });
mkdirSync(join(git(rebasing, "rev-parse", "--path-format=absolute", "--git-path", "rebase-merge")), { recursive: true });
await check("rebase in progress", rebasing, "kept", false);

// Protected names are never touched, even clean and merged, and the shared file adds more.
for (const name of ["review", "reviews", "playground", "trivial", "trivials", "resolves", "resolves-1", "resolves-3"]) {
  await check(`protected '${name}'`, worktree(name, { commit: true, merge: true }), "untrack", false);
}
const listed = worktree("listed", { commit: true, merge: true });
await check("listed in the protected file", listed, "untrack", false, { protectedEntries: parseProtected("# kept\nlisted\n") });
if (isProtected("/a/b/other", parseProtected("listed"))) fail("an unlisted name counted as protected");

// A path that is not a git worktree any more is dropped from the watch list.
await check("gone", join(base, "does-not-exist"), "untrack", true);

// The main checkout is never removed.
await check("main checkout", checkout, "untrack", false);

rmSync(base, { recursive: true, force: true });
if (failures === 0) console.log("worktree-cleanup-application: all checks passed");
process.exit(failures === 0 ? 0 : 1);
