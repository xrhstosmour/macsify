import { View, div } from "gpui-kit";
import { exec, home, machines, notify, panes, readTextFile, setShared, shared } from "herdr";
import { isOccupiedBy, linkedWorktreeRoot, parseProtected, sweepWorktree, trackedWorktree } from "./logic.js";

// Removes a linked worktree once the last terminal in it is gone. The app has
// no workspace-closed event, so this watches `panes()` and sweeps a tracked
// worktree after nothing has sat in it for `SETTLE_MS`. Quitting the app does
// not count, `herdr-core` keeps the terminals running. The rules, and the reason
// each exists, are in `logic.js`.

const TRACKED_KEY = "worktree-cleanup.tracked";
const TICK_MS = 5000;
const SETTLE_MS = 10000;
// A kept worktree is looked at again this long after, not on every tick, each
// look can cost a `git fetch` and a `gh` call.
const RETRY_MS = 10 * 60000;
const WORKTREE_ROOTS = [`${home()}/Developer/worktrees`, `${home()}/.herdr/worktrees`];
// A person's list of worktree folder names or absolute paths to never touch, one
// per line, `setup/agentic.sh` copies it here from its former place.
const PROTECTED_FILE = `${home()}/.config/herdr-app/worktree-cleanup-protected`;
const LOG_DIRECTORY = `${home()}/.cache/herdr-app/worktree-cleanup`;
const LOG_MAX_BYTES = 200000;

export default class WorktreeCleanup extends View {
  init(_props, cx) {
    const saved = shared(TRACKED_KEY);
    this.tracked = new Set(Array.isArray(saved) ? saved : []);
    // Folder a pane sits in -> the linked worktree it belongs to, or null.
    this.resolved = new Map();
    this.absentSince = new Map();
    this.retryAt = new Map();
    this.busy = false;
    cx.timer.every(TICK_MS, (cx) => this.tick(cx));
  }

  log(message) {
    const line = `${new Date().toISOString()} ${message}`;
    // Arguments, not interpolation, a message can hold anything.
    exec("sh", ["-c", 'mkdir -p "$2" && printf "%s\\n" "$1" >> "$2/app.log" && { [ "$(wc -c < "$2/app.log")" -le "$3" ] || { tail -n 500 "$2/app.log" > "$2/app.log.tmp" && mv "$2/app.log.tmp" "$2/app.log"; }; }', "sh", line, LOG_DIRECTORY, String(LOG_MAX_BYTES)]).catch(() => {});
  }

  // The linked worktree a folder is inside, wherever it is, for the occupancy check.
  async rootOf(folder) {
    if (!this.resolved.has(folder)) this.resolved.set(folder, await linkedWorktreeRoot(exec, folder));
    return this.resolved.get(folder);
  }

  // Only under the known roots, so a terminal in some other repository is never tracked.
  async worktreeOf(folder) {
    return trackedWorktree((path) => this.rootOf(path), folder, WORKTREE_ROOTS);
  }

  // Folders of the local terminal panes. Remote panes live on another
  // filesystem, their folders mean nothing here.
  paneFolders() {
    return [...new Set(panes().filter((pane) => pane.terminal && pane.cwd && !pane.pane.includes("/")).map((pane) => pane.cwd))];
  }

  tick(cx) {
    if (this.busy) return;
    // Until the layout is read the pane list is empty and every tracked worktree
    // would look abandoned. An empty list once it is ready is real, closing the
    // last space leaves none, and `absentSince` only starts counting from here.
    const local = machines().find((machine) => machine.name === null);
    if (!local || local.layout !== "ready") return;

    const folders = this.paneFolders();
    this.busy = true;
    cx.spawn(async (cx) => {
      try {
        const protectedEntries = parseProtected(await readTextFile(PROTECTED_FILE).catch(() => null));
        let changed = false;

        for (const folder of folders) {
          const root = await this.worktreeOf(folder);
          if (root && !this.tracked.has(root)) {
            this.tracked.add(root);
            changed = true;
            this.log(`tracking: ${root}`);
          }
        }

        const now = Date.now();
        const fetched = new Set();
        const rootOf = (folder) => this.rootOf(folder);
        for (const path of [...this.tracked]) {
          if (await isOccupiedBy(path, folders, rootOf)) {
            this.absentSince.delete(path);
            this.retryAt.delete(path);
            continue;
          }
          if (!this.absentSince.has(path)) this.absentSince.set(path, now);
          if (now - this.absentSince.get(path) < SETTLE_MS || now < (this.retryAt.get(path) ?? 0)) continue;

          const { outcome, reason } = await sweepWorktree(path, { exec, protectedEntries, fetched, isOccupied: () => isOccupiedBy(path, this.paneFolders(), rootOf) });
          this.log(`${outcome}: ${path} (${reason})`);
          if (outcome === "kept") {
            this.retryAt.set(path, now + RETRY_MS);
            continue;
          }
          this.tracked.delete(path);
          this.absentSince.delete(path);
          this.retryAt.delete(path);
          changed = true;
          if (outcome === "removed") notify({ title: "Worktree removed", body: path, level: "info", timeout: 6000 });
        }

        // Shared state re-renders every mod, so write it only when the list changed.
        if (changed) setShared(TRACKED_KEY, [...this.tracked]);
      } catch (error) {
        this.log(`tick failed: ${error}`);
      } finally {
        this.busy = false;
      }
    });
  }

  // Invisible, the mod only watches.
  render() {
    return div().id("worktree-cleanup");
  }
}
