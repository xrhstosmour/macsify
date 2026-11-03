import { View, div } from "gpui-kit";
import { exec, home, machines, panes } from "herdr";

// The app's counterpart of the `herdr-repository-sync` plugin. The sync itself
// is that plugin's `repository-sync.sh`, reused as is: it fetches `origin` and
// rebases onto the default branch only a clean checkout on `main` or `master`,
// throttled per checkout, and aborts on a conflict. The app has no tab or
// workspace events, so this hands it every folder a terminal sits in the first
// time that folder shows up, and once when the mod loads.

const SCRIPT = `${home()}/.config/herdr-repository-sync/repository-sync.sh`;
const TICK_MS = 5000;

export default class RepositorySync extends View {
  init(_props, cx) {
    this.seen = new Set();
    cx.timer.every(TICK_MS, () => this.tick());
  }

  tick() {
    // Until the layout is read the pane list is empty.
    const local = machines().find((machine) => machine.name === null);
    if (!local || local.layout !== "ready") return;

    // Remote panes live on another filesystem, their folders mean nothing here.
    const fresh = [...new Set(panes().filter((pane) => pane.terminal && pane.cwd && !pane.pane.includes("/")).map((pane) => pane.cwd))].filter((folder) => !this.seen.has(folder));
    if (fresh.length === 0) return;
    fresh.forEach((folder) => this.seen.add(folder));

    // The script detaches at once and logs to `~/.cache/herdr-repository-sync/sync.log`.
    exec("bash", [SCRIPT, "app", ...fresh]).catch(() => {});
  }

  // Invisible, the mod only watches.
  render() {
    return div().id("repository-sync");
  }
}
