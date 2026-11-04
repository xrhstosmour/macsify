// Runs the naming rules of the `Herdr` app's `tab-names` mod. Started by `tests/tab-names.sh`.
import { fileURLToPath } from "node:url";

const logicUrl = new URL("../.config/herdr-app/mods/tab-names/logic.js", import.meta.url);
const { autoName, nextName, withoutColor, MAX_NAME_LENGTH } = await import(fileURLToPath(logicUrl));

let failures = 0;
function expect(label, actual, wanted) {
  if (actual !== wanted) {
    console.log(`FAIL: ${label}: got ${JSON.stringify(actual)}, wanted ${JSON.stringify(wanted)}`);
    failures += 1;
  }
}

const home = "/Users/someone";
const shell = { name: "zsh", shell: true };
const agent = { name: "Claude Code", shell: false, icon: "icons/claude.svg" };
const unlisted = { name: "htop", shell: false, icon: null };

expect("a program with an icon adds nothing", autoName({ cwd: `${home}/Developer/macsify`, program: agent }, home), "macsify");
expect("a program without an icon keeps its name", autoName({ cwd: `${home}/Developer/macsify`, program: unlisted }, home), "macsify · htop");
expect("a shell adds nothing", autoName({ cwd: `${home}/Developer/macsify`, program: shell }, home), "macsify");
expect("home", autoName({ cwd: home, program: shell }, home), "~");
expect("no folder yet", autoName({ cwd: null, program: shell }, home), null);
expect("long names are cut", autoName({ cwd: `${home}/${"a".repeat(80)}`, program: shell }, home).length, MAX_NAME_LENGTH);

// An unnamed tab (called by its position) is taken over.
expect("takes an unnamed tab", nextName({ currentName: "2", last: undefined, wanted: "macsify" }), "macsify");
// A tab named by the person is not.
expect("leaves a named tab", nextName({ currentName: "fix login", last: undefined, wanted: "macsify" }), null);
// Follows the folder while the name is still the one it set.
expect("follows the terminal", nextName({ currentName: "macsify", last: "macsify", wanted: "api · Claude Code" }), "api · Claude Code");
expect("nothing to change", nextName({ currentName: "macsify", last: "macsify", wanted: "macsify" }), null);
// A rename after the mod set the name opts the tab out for good.
expect("respects a later rename", nextName({ currentName: "my name", last: "macsify", wanted: "api" }), null);
expect("no terminal", nextName({ currentName: "2", last: undefined, wanted: null }), null);

// A color survives renames and does not count as a rename.
expect("keeps the color", nextName({ currentName: "🔴 macsify", last: "macsify", wanted: "api" }), "🔴 api");
expect("colored unnamed tab", nextName({ currentName: "🟢 3", last: undefined, wanted: "api" }), "🟢 api");
expect("renamed behind a color", nextName({ currentName: "🔴 mine", last: "macsify", wanted: "api" }), null);
expect("strip", withoutColor("🟡 api"), "api");

if (failures === 0) console.log("tab-names: all checks passed");
process.exit(failures === 0 ? 0 : 1);
