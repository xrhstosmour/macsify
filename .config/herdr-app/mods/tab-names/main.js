import { View, div } from "gpui-kit";
import { home, machines, panes, run, setShared, shared, spaces } from "herdr";
import { autoName, nextName, withoutColor } from "./logic.js";

// The app's counterpart of the `herdr-automatic-rename` plugin: a tab nobody
// named gets `folder · program` and follows its terminal around, and a tab the
// person renamed is left alone for good. `LAST_KEY` remembers the name set per
// tab so a restart or a reload of this mod does not mistake it for the person's
// own rename. Coloring a tab, a leading 🔴 🟡 🟢 added by `herdr_tab_color`
// in `.config/fish/functions/herdr.fish`, is kept across renames.

const LAST_KEY = "tab-names.last";
const TICK_MS = 3000;

export default class TabNames extends View {
  init(_props, cx) {
    const saved = shared(LAST_KEY);
    this.last = new Map(Object.entries(saved && typeof saved === "object" ? saved : {}));
    cx.timer.every(TICK_MS, () => this.tick());
  }

  tick() {
    // Until the layout is read there are no tabs, and a tab of another machine is not ours to name.
    const local = machines().find((machine) => machine.name === null);
    if (!local || local.layout !== "ready") return;

    const terminals = panes().filter((pane) => pane.terminal && !pane.pane.includes("/"));
    const alive = new Set();
    let changed = false;

    for (const space of spaces().filter((space) => space.machine === null)) {
      for (const tab of space.tabs) {
        alive.add(tab.id);
        const inTab = terminals.filter((pane) => pane.tab === tab.id);
        const main = inTab.find((pane) => pane.focused) ?? inTab[0];
        const name = nextName({ currentName: tab.name, last: this.last.get(tab.id), wanted: main ? autoName(main, home()) : null });
        if (name === null) continue;
        run("tab.rename", { id: tab.id, name });
        this.last.set(tab.id, withoutColor(name));
        changed = true;
      }
    }

    for (const id of [...this.last.keys()]) {
      if (!alive.has(id)) {
        this.last.delete(id);
        changed = true;
      }
    }

    // Shared state re-renders every mod, so write it only when it changed.
    if (changed) setShared(LAST_KEY, Object.fromEntries(this.last));
  }

  // Invisible, the mod only watches.
  render() {
    return div().id("tab-names");
  }
}
