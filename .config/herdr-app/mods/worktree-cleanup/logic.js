// The decisions of the `worktree-cleanup` mod, kept free of the `herdr` module
// so `tests/worktree-cleanup-application.sh` can run them against real `git` in Node.
// A worktree whose work is neither merged nor pushed is kept whole, not only its
// branch, and a clean one whose branch is pushed in full is removed too, the
// remote still holds every commit.

// Worktrees kept on purpose, whatever their state. More go in the
// `worktree-cleanup-protected` file under `~/.config/herdr-app`.
export const PROTECTED_NAMES = ["review", "reviews", "playground", "trivial", "trivials", "resolves", "resolves-1", "resolves-2", "resolves-3"];

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

// A removal notice, the project in the title and the folder alone in the body,
// the toast cuts a long body to one line and the full path never fit.
export function removalNotice(path, roots) {
  const root = roots.find((candidate) => path.startsWith(`${candidate}/`));
  const parts = (root ? path.slice(root.length + 1) : path).split("/");
  const folder = parts.pop();
  return { title: root && parts.length ? `Worktree removed in ${parts.join("/")}` : "Worktree removed", body: folder };
}

// The worktree a terminal folder may be tracked as, or null. Both the folder as
// spelled and the worktree root git reports are checked, a symlink under a root
// can point at a worktree elsewhere, and only the root is what gets removed.
export async function trackedWorktree(rootOf, folder, roots) {
  if (!isUnderAny(folder, roots)) return null;
  const root = await rootOf(folder);
  return root && isUnderAny(root, roots) ? root : null;
}

// The same limits as `.config/herdr-app/mods/repository-sync/repository-sync.sh`, so a
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
// whichever path led to it, the same as comparing with `pwd -P`.
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

function defaultBranch(exec, mainCheckout) {
  return git(exec, mainCheckout, ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]);
}

// Whether a commit is an ancestor of the origin default branch. One fetch per
// repository per pass, the caller passes `fetched` to share it.
async function commitMerged(exec, mainCheckout, commit, defaultReference, fetched) {
  const isAncestor = async () => {
    try {
      return (await exec("git", ["merge-base", "--is-ancestor", commit, defaultReference], { cwd: mainCheckout })).code === 0;
    } catch {
      return false;
    }
  };

  // Merged by the last known refs needs no network.
  if (await isAncestor()) return true;
  if (fetched.has(mainCheckout)) return false;
  fetched.add(mainCheckout);
  try {
    await networkExec(exec, "git", ["fetch", "origin", "--quiet"], { cwd: mainCheckout });
  } catch {
    // Fall through to the last known refs.
  }
  return isAncestor();
}

// Whether a branch's work is on the origin default branch: its tip is an ancestor
// of it, or the tip is exactly the head of a merged pull request, which covers
// squash and rebase merges. A branch that gained commits after its pull request
// merged is not merged. Resolves to `{ merged, reason }`.
export async function branchMerged(exec, mainCheckout, branch, fetched = new Set()) {
  const defaultReference = await defaultBranch(exec, mainCheckout);
  if (!defaultReference) return { merged: false, reason: "no origin default branch" };
  if (branch === defaultReference.replace(/^origin\//, "")) return { merged: false, reason: "on the default branch" };

  const tip = await git(exec, mainCheckout, ["rev-parse", "--verify", "--quiet", `refs/heads/${branch}`]);
  if (!tip) return { merged: false, reason: "no local branch" };

  if (await commitMerged(exec, mainCheckout, tip, defaultReference, fetched)) return { merged: true, reason: `merged into ${defaultReference}` };

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

// Whether every commit of a branch is on its own origin branch, as of the last
// fetch, so deleting the local branch loses nothing. Never true for a branch
// with no origin counterpart, or one with commits made after the last push.
export async function branchPushed(exec, mainCheckout, branch) {
  const tip = await git(exec, mainCheckout, ["rev-parse", "--verify", "--quiet", `refs/heads/${branch}`]);
  const remote = await git(exec, mainCheckout, ["rev-parse", "--verify", "--quiet", `refs/remotes/origin/${branch}`]);
  if (!tip || !remote) return false;
  try {
    return (await exec("git", ["merge-base", "--is-ancestor", tip, remote], { cwd: mainCheckout })).code === 0;
  } catch {
    return false;
  }
}

// The linked worktrees under the roots, found by the `.git` file each one has at
// its top, for worktrees no terminal of the app ever sat in. A root missing or
// unreadable yields nothing.
export async function discoverWorktrees(exec, roots) {
  const found = new Set();
  const rootOf = (folder) => linkedWorktreeRoot(exec, folder);
  for (const root of roots) {
    let listing;
    try {
      listing = await exec("find", [root, "-mindepth", "2", "-maxdepth", "3", "-name", ".git", "-type", "f"]);
    } catch {
      continue;
    }
    for (const marker of listing.stdout.split("\n").filter(Boolean)) {
      const worktree = await trackedWorktree(rootOf, marker.replace(/\/\.git$/, ""), roots);
      if (worktree) found.add(worktree);
    }
  }
  return [...found];
}

// Whether anything at the top of the worktree or in its own git directory
// changed in the last `minutes`, a sign someone outside the app works there.
// The index and the git directory itself are left out, every `git status`,
// this mod's own included, may rewrite the index, and a staged change already
// keeps the worktree as uncommitted. Only one level deep, a write further down
// with nothing new at the top passes as idle.
async function recentlyActive(exec, path, minutes) {
  const gitDirectory = await git(exec, path, ["rev-parse", "--path-format=absolute", "--git-dir"]);
  if (!gitDirectory) return true;
  const age = ["-mmin", `-${minutes}`];
  try {
    const top = await exec("find", [path, "-maxdepth", "1", ...age], { cwd: path });
    const own = await exec("find", [gitDirectory, "-mindepth", "1", "-maxdepth", "1", "!", "-name", "index*", ...age], { cwd: path });
    return top.code !== 0 || own.code !== 0 || `${top.stdout}${own.stdout}`.trim() !== "";
  } catch {
    // Unknown counts as active, the worktree stays.
    return true;
  }
}

// Removes one linked worktree when it is safe to, and its branch once the work
// is merged or pushed. Resolves to `{ outcome, reason }` with outcome one of `removed`,
// `kept` (check again later) or `untrack` (nothing left to watch). Never forces:
// git itself refuses a locked or dirty worktree. `isOccupied` is asked right
// before the removal, the merge check can take a while and a terminal may have
// opened in the folder since the caller looked. A worktree no terminal of the
// app sat in passes `allowPushed: false` and `idleMinutes`, an agent in another
// terminal may still be working on a pushed branch or a fresh one, so it also
// needs a commit made in it.
export async function sweepWorktree(path, { exec, protectedEntries = [], fetched = new Set(), isOccupied = async () => false, allowPushed = true, idleMinutes = null }) {
  if (isProtected(path, protectedEntries)) return { outcome: "untrack", reason: "protected" };

  const common = await git(exec, path, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  if (!common) return { outcome: "untrack", reason: "not a git worktree any more" };
  const mainCheckout = common.replace(/\/\.git$/, "");
  if (mainCheckout === path) return { outcome: "untrack", reason: "the main checkout" };

  if (idleMinutes !== null && (await recentlyActive(exec, path, idleMinutes))) return { outcome: "kept", reason: `active in the last ${idleMinutes} minutes` };

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

  // A fresh worktree, `HEAD` never on another commit since `git worktree add`,
  // sits on the default branch and so looks merged, yet an agent may be about to
  // start in it. Distinct commits, `worktree add` itself logs `HEAD` twice. A
  // missing reflog counts as fresh too.
  if (idleMinutes !== null) {
    const moves = await git(exec, path, ["reflog", "show", "--format=%H", "HEAD"]);
    if (!moves || new Set(moves.split("\n")).size < 2) return { outcome: "kept", reason: "no commits made in it yet" };
  }

  const remove = async () => {
    if (await isOccupied()) return "a terminal opened in it";
    const removal = await exec("git", ["worktree", "remove", path], { cwd: mainCheckout });
    return removal.code === 0 ? null : `remove failed: ${removal.stderr.trim()}`;
  };

  // Commits on a detached HEAD are reachable from nothing once the worktree is
  // gone, so only one already on the default branch goes.
  const headReference = await git(exec, path, ["symbolic-ref", "--quiet", "HEAD"]);
  if (!headReference) {
    const head = await git(exec, path, ["rev-parse", "--verify", "--quiet", "HEAD"]);
    const defaultReference = await defaultBranch(exec, mainCheckout);
    if (!head || !defaultReference || !(await commitMerged(exec, mainCheckout, head, defaultReference, fetched))) return { outcome: "kept", reason: "detached HEAD not merged" };
    const failure = await remove();
    return failure ? { outcome: "kept", reason: failure } : { outcome: "removed", reason: `detached HEAD merged into ${defaultReference}` };
  }
  const branch = headReference.replace(/^refs\/heads\//, "");

  // Merged, or pushed in full, either way no commit exists only here.
  const merged = await branchMerged(exec, mainCheckout, branch, fetched);
  if (!merged.merged && allowPushed && (await branchPushed(exec, mainCheckout, branch))) {
    merged.merged = true;
    merged.reason = "pushed to origin";
  }
  if (!merged.merged) return { outcome: "kept", reason: `branch '${branch}' ${merged.reason}${allowPushed ? ", not pushed" : ""}` };

  const failure = await remove();
  if (failure) return { outcome: "kept", reason: failure };

  const deletion = await exec("git", ["branch", "-D", branch], { cwd: mainCheckout });
  return { outcome: "removed", reason: deletion.code === 0 ? `branch '${branch}' deleted, ${merged.reason}` : `branch '${branch}' kept, delete failed` };
}
