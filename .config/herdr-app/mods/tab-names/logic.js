// The naming rules of the `tab-names` mod, free of the `herdr` module so
// `tests/tab-names.sh` can run them in Node. Mirrors `herdr-automatic-rename`
// as configured in `.config/herdr-automatic-rename/config.sh`: `folder · program`,
// no branch, no index, names cut at 40 characters, except that a program with an
// icon is left out of the name, which the plugin does not do.

export const COLORS = ["🔴", "🟡", "🟢"];
export const MAX_NAME_LENGTH = 40;

// A tab kept its automatic name only while its name is still what was set.
// Anything else is the person's own rename and the tab is left alone from then on.
export function colorOf(name) {
  return COLORS.find((color) => name.startsWith(`${color} `)) ?? "";
}

export function withoutColor(name) {
  const color = colorOf(name);
  return color ? name.slice(color.length + 1) : name;
}

function cut(text, length) {
  return text.length <= length ? text : `${text.slice(0, length - 1)}…`;
}

// `terminal` is the tab's main terminal pane: its `cwd` and its `program`
// (`name`, `shell`, `icon`). A shell adds nothing the folder does not say, and
// neither does a program with an icon, the tab draws it. A program without one
// keeps its name, it is the only thing that says what runs there.
export function autoName({ cwd, program }, home) {
  if (!cwd) return null;
  const folder = cwd === home ? "~" : cwd.split("/").filter(Boolean).pop() ?? "/";
  const name = program && !program.shell && !program.icon && program.name ? `${folder} · ${program.name}` : folder;
  return cut(name, MAX_NAME_LENGTH);
}

// The next name for a tab, or null to leave it. `last` is what the mod set before.
// A color prefix is kept across renames and ignored when comparing, so coloring a
// tab does not count as renaming it.
export function nextName({ currentName, last, wanted }) {
  if (!wanted) return null;
  const color = colorOf(currentName);
  const bare = withoutColor(currentName);
  // Never touched by the mod: only an unnamed tab (called by its position) is taken over.
  if (last === undefined && !/^\d+$/.test(bare)) return null;
  // Renamed by the person since the mod last set it.
  if (last !== undefined && bare !== last) return null;
  const name = color ? `${color} ${wanted}` : wanted;
  return name === currentName ? null : name;
}
