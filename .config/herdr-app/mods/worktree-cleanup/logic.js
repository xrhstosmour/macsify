// The decisions of the `worktree-cleanup` mod, kept free of the `herdr` module
// so `tests/worktree-cleanup-application.sh` can run them against real `git` in Node.
// Mirrors `.config/herdr-worktree-cleanup/worktree-cleanup.sh`, the multiplexer
// plugin, with one stricter rule: a worktree whose work is not merged is kept
// whole, not only its branch.

// Worktrees kept on purpose, whatever their state. The same names the plugin
// skips, plus the scratch ones. More go in the shared `protected` file.
export const PROTECTED_NAMES = ["review", "reviews", "playground", "trivial", "trivials"];

// Git's own markers of an unfinished operation.
const IN_PROGRESS_STATES = ["rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG"];

// One entry per line, blank lines and `#` comments ignored.
export function parseProtected(text) {
  return (text ?? "").split("\n").map((line) => line.trim()).filter((line) => line && !line.startsWith("#"));
}

// A directory name or a physical absolute path, no `~`.
export function isProtected(path, entries = []) {
  const name = path.split("/").filter(Boolean).pop();
  return PROTECTED_NAMES.includes(name) || entries.includes(name) || entries.includes(path);
}

export function isInside(path, directory) {
  return directory === path || directory.startsWith(`${path}/`);
}

export function isUnderAny(path, roots) {
  return roots.some((root) => path.startsWith(`${root}/`));
}

// The same limits as `.config/herdr-repository-sync/repository-sync.sh`, so a
// fetch cannot hang on a prompt or a stalled transfer. `exec` takes no
// environment, so `env` sets it. `exec` also cuts a call off after 30 seconds,
// and every caller below treats a failed or cut off call as not merged, the
// worktree stays.
const NETWORK_ENVIRONMENT = [
  "GIT_TERMINAL_PROMPT=0",
  "GIT_SSH_COMMAND=ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2",
  "GIT_HTTP_LOW_SPEED_LIMIT=1000",
  "GIT_HTTP_LOW_SPEED_TIME=30",
];

function networkExec(exec, command, args, options) {
  return exec("env", [...NETWORK_ENVIRONMENT, command, ...args], options);
}

// Runs git in a folder and resolves to its trimmed output, or null on any failure.
async function git(exec, cwd, args) {
  try {
    const result = await exec("git", args, { cwd });
    return result.code === 0 ? result.stdout.trim() : null;
  } catch {
    return null;
  }
}

// The top folder of the linked worktree a folder is in, or null for a main
// checkout or no repository. `git` resolves symlinks, so the root is physical
// whichever path led to it, the way the plugin compares with `pwd -P`.
export async function linkedWorktreeRoot(exec, folder) {
  const top = await git(exec, folder, ["rev-parse", "--path-format=absolute", "--show-toplevel"]);
  const gitDirectory = await git(exec, folder, ["rev-parse", "--path-format=absolute", "--git-dir"]);
  const common = await git(exec, folder, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  // Linked worktrees have their own git directory apart from the shared one.
  return top && gitDirectory && common && gitDirectory !== common ? top : null;
}

// Whether a terminal sits in the worktree. A plain path match is not enough, a
// terminal reached through a symlink has another spelling of the same folder,
// so each folder is also mapped to its root by `rootOf`.
export async function isOccupiedBy(path, folders, rootOf) {
  for (const folder of folders) {
    if (isInside(path, folder) || (await rootOf(folder)) === path) return true;
  }
  return false;
}

// Whether a branch's work is on the origin default branch: its tip is an ancestor
// of it, or the tip is exactly the head of a merged pull request, which covers
// squash and rebase merges. A branch that gained commits after its pull request
// merged is not merged. One fetch per repository per pass, the caller passes
// `fetched` to share it. Resolves to `{ merged, reason }`.
export async function branchMerged(exec, mainCheckout, branch, fetched = new Set()) {
  const defaultReference = await git(exec, mainCheckout, ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]);
  if (!defaultReference) return { merged: false, reason: "no origin default branch" };
  if (branch === defaultReference.replace(/^origin\//, "")) return { merged: false, reason: "on the default branch" };

  const tip = await git(exec, mainCheckout, ["rev-parse", "--verify", "--quiet", `refs/heads/${branch}`]);
  if (!tip) return { merged: false, reason: "no local branch" };

  const isAncestor = async () => {
    try {
      return (await exec("git", ["merge-base", "--is-ancestor", tip, defaultReference], { cwd: mainCheckout })).code === 0;
    } catch {
      return false;
    }
  };

  // Merged by the last known refs needs no network.
  if (await isAncestor()) return { merged: true, reason: `merged into ${defaultReference}` };

  if (!fetched.has(mainCheckout)) {
    fetched.add(mainCheckout);
    try {
      await networkExec(exec, "git", ["fetch", "origin", "--quiet"], { cwd: mainCheckout });
    } catch {
      // Fall through to the last known refs.
    }
    if (await isAncestor()) return { merged: true, reason: `merged into ${defaultReference}` };
  }

  try {
    const pulls = await networkExec(exec, "gh", ["pr", "list", "--head", branch, "--state", "merged", "--json", "headRefOid", "--jq", ".[].headRefOid"], { cwd: mainCheckout });
    if (pulls.code === 0 && pulls.stdout.split("\n").map((line) => line.trim()).includes(tip)) {
      return { merged: true, reason: "tip is the head of a merged pull request" };
    }
  } catch {
    // No `gh`, the pull request cannot be proven merged.
  }
  return { merged: false, reason: "not merged" };
}

// Removes one linked worktree when it is safe to, and its branch once the work
// is merged. Resolves to `{ outcome, reason }` with outcome one of `removed`,
// `kept` (check again later) or `untrack` (nothing left to watch). Never forces:
// git itself refuses a locked or dirty worktree. `isOccupied` is asked right
// before the removal, the merge check can take a while and a terminal may have
// opened in the folder since the caller looked.
export async function sweepWorktree(path, { exec, protectedEntries = [], fetched = new Set(), isOccupied = async () => false }) {
  if (isProtected(path, protectedEntries)) return { outcome: "untrack", reason: "protected" };

  const common = await git(exec, path, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  if (!common) return { outcome: "untrack", reason: "not a git worktree any more" };
  const mainCheckout = common.replace(/\/\.git$/, "");
  if (mainCheckout === path) return { outcome: "untrack", reason: "the main checkout" };

  // Commits on a detached HEAD are reachable from nothing once the worktree is gone.
  const headReference = await git(exec, path, ["symbolic-ref", "--quiet", "HEAD"]);
  if (!headReference) return { outcome: "kept", reason: "detached HEAD" };
  const branch = headReference.replace(/^refs\/heads\//, "");

  // `--untracked-files=all` so a new, never added file counts as work worth keeping.
  const status = await git(exec, path, ["status", "--porcelain", "--untracked-files=all"]);
  if (status === null) return { outcome: "kept", reason: "git status failed" };
  if (status !== "") return { outcome: "kept", reason: "uncommitted or untracked changes" };

  for (const state of IN_PROGRESS_STATES) {
    const marker = await git(exec, path, ["rev-parse", "--path-format=absolute", "--git-path", state]);
    if (marker && (await exec("test", ["-e", marker], { cwd: path })).code === 0) {
      return { outcome: "kept", reason: `${state} in progress` };
    }
  }

  const merged = await branchMerged(exec, mainCheckout, branch, fetched);
  if (!merged.merged) return { outcome: "kept", reason: `branch '${branch}' ${merged.reason}` };

  if (await isOccupied()) return { outcome: "kept", reason: "a terminal opened in it" };

  const removal = await exec("git", ["worktree", "remove", path], { cwd: mainCheckout });
  if (removal.code !== 0) return { outcome: "kept", reason: `remove failed: ${removal.stderr.trim()}` };

  const deletion = await exec("git", ["branch", "-D", branch], { cwd: mainCheckout });
  return { outcome: "removed", reason: deletion.code === 0 ? `branch '${branch}' deleted, ${merged.reason}` : `branch '${branch}' kept, delete failed` };
}
