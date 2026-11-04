// Runs `sweepWorktree` from the `Herdr` app's `worktree-cleanup` mod against real
// temporary `git` repositories. Started by `tests/worktree-cleanup-application.sh`.
// `tests/worktree-cleanup.sh` runs the same cases against the multiplexer plugin,
// a case added here belongs there too, the two must decide alike, except the
// pushed branch cases below, which only the app's mod keeps.
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const logicUrl = new URL("../.config/herdr-app/mods/worktree-cleanup/logic.js", import.meta.url);
const { sweepWorktree, parseProtected, isProtected, isOccupiedBy, linkedWorktreeRoot, PROTECTED_NAMES } = await import(fileURLToPath(logicUrl));

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
// A commit made after the push is only here, so it stays. This is the app's own rule, the plugin
// keeps an unmerged branch.
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

// Merged but dirty or untracked: kept.
const dirty = worktree("dirty", { commit: true, merge: true });
writeFileSync(join(dirty, "dirty.txt"), "changed");
await check("modified file", dirty, "kept", false);
const untracked = worktree("untracked", { commit: true, merge: true });
writeFileSync(join(untracked, "new-file"), "never added");
await check("untracked file", untracked, "kept", false);

// Detached HEAD: kept.
const detached = worktree("detached", { commit: true, merge: true });
git(detached, "checkout", "--quiet", "--detach");
await check("detached HEAD", detached, "kept", false);

// A rebase in progress: kept.
const rebasing = worktree("rebasing", { commit: true, merge: true });
mkdirSync(join(git(rebasing, "rev-parse", "--path-format=absolute", "--git-path", "rebase-merge")), { recursive: true });
await check("rebase in progress", rebasing, "kept", false);

// Protected names are never touched, even clean and merged, and the shared file adds more.
for (const name of ["review", "reviews", "playground", "trivial", "trivials"]) {
  await check(`protected '${name}'`, worktree(name, { commit: true, merge: true }), "untrack", false);
}
const listed = worktree("listed", { commit: true, merge: true });
await check("listed in the protected file", listed, "untrack", false, { protectedEntries: parseProtected("# kept\nlisted\n") });
if (isProtected("/a/b/other", parseProtected("listed"))) fail("an unlisted name counted as protected");

// The multiplexer plugin keeps its own copy of the protected names, they must not drift.
const scriptNames = readFileSync(new URL("../.config/herdr-worktree-cleanup/worktree-cleanup.sh", import.meta.url), "utf8").match(/^PROTECTED_NAMES="(.*)"$/m)?.[1].split(" ");
if (JSON.stringify(scriptNames) !== JSON.stringify(PROTECTED_NAMES)) fail(`protected names differ: plugin ${scriptNames}, mod ${PROTECTED_NAMES}`);

// A path that is not a git worktree any more is dropped from the watch list.
await check("gone", join(base, "does-not-exist"), "untrack", true);

// The main checkout is never removed.
await check("main checkout", checkout, "untrack", false);

rmSync(base, { recursive: true, force: true });
if (failures === 0) console.log("worktree-cleanup-application: all checks passed");
process.exit(failures === 0 ? 0 : 1);
