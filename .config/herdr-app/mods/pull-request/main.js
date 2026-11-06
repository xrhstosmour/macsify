import { View, div } from "gpui-kit";
import { v_flex, h_flex, TextView, TextareaState, Textarea } from "gpui-base";
import { exec, focused, layout, notify, panes, props, settings, setShared, shared, spaces, theme } from "herdr";
import { BRANCH_MS, DETAIL_FIELDS, MERGE_LABELS, MERGE_QUERY, REFRESH_MS, STATE_KEY, STUCK_MS, SUMMARY_FIELDS, actionArgs, armId, canMerge, checkRows, checksSummary, classify, confirmed, diffFiles, failedRuns, focusedFolder, isArmed, isCurrent, isShown, isStale, keyOf, needsLoad, mergeStatus, mergeOptions, reviewers, timeline, withoutImages } from "./logic.js";

// The pull request of the branch in the focused terminal, as its GitHub page
// shows it, with its buttons: comment, approve, request changes, reply to a
// thread, merge, close, draft, rerun failed checks. Herdr has no web view, and a
// terminal browser such as `carbonyl` ships a Chromium years behind on security
// fixes, so the page is drawn here from `gh`, with the person's own `gh` login,
// the way the `Orca` app draws its pull request page. A write happens only on a
// click, approve pinned to the commit on screen. The merge box does what GitHub's
// does and nothing more: merge pinned to the commit on screen, merge when ready
// through the same mutation as GitHub's button, bypass only when its box is
// ticked, each after a confirm click, and never a push, a rebase or an
// autosquash. New line comments, resolving threads, reviewers, labels and
// reactions are left to GitHub. One mod, two copies. The watcher, an invisible
// block of the layout (`props.watch`), asks `gh` whether the branch has an open
// pull request and shares the answer under `STATE_KEY`, `tabs-inline` shows its
// GitHub button only then. A copy starts only once it shows, so the panel
// itself, hidden until the button is pressed, could not decide that. The panel
// copy, a child of the `panel-body` stack, loads the detail, the diff and the
// inline threads when the pull request it is shown changes, only while it is on
// screen.

const RETRY_KEY = "pull-request.retry";
const STALLED = "GitHub did not answer within a minute, Refresh tries again.";
const TICK_MS = 1000;
const FILE_LINES_MAX = 400;

const run = async (args, cwd) => {
  try {
    return await exec("gh", args, { cwd });
  } catch (error) {
    return { error: String(error?.message ?? error) };
  }
};
const failure = (result) => result.error ?? ((result.stderr || "").trim().split("\n")[0] || `gh exited with ${result.code}`);

const DONE = { comment: "Comment posted.", approve: "Approved.", "request-changes": "Changes requested.", reply: "Reply posted.", merge: "Merged.", enqueue: "Added to the merge queue.", dequeue: "Removed from the merge queue.", close: "Closed.", ready: "Marked ready for review.", draft: "Converted to draft.", rerun: "Failed jobs rerun." };
// GitHub's second button, once the first click armed it.
const CONFIRM = { rebase: "Confirm rebase and merge", merge: "Confirm merge", squash: "Confirm squash and merge", bypass: "Confirm bypass rules and merge", enqueue: "Confirm merge when ready", close: "Confirm close pull request" };
// The buttons whose only refusable input is the text box, any other refusal is a page without a commit or ID to pin to.
const WRITE_FIRST = new Set(["comment", "request-changes", "reply"]);
const REVIEW_WORDS = { APPROVED: "approved", CHANGES_REQUESTED: "requested changes", COMMENTED: "reviewed", DISMISSED: "review dismissed", PENDING: "pending review", REQUESTED: "review requested" };
const DECISION = { APPROVED: ["Approved", "good"], CHANGES_REQUESTED: ["Changes requested", "bad"], REVIEW_REQUIRED: ["Review required", "warn"] };
const MARKS = { failure: "✗", pending: "●", success: "✓", skipped: "–" };
const day = (iso) => (iso ?? "").slice(0, 10);
const mono = () => settings()?.font_family ?? "JetBrains Mono";

export default class PullRequest extends View {
  // A layout block's `props` reach a mod through `props()`, `init` gets none.
  init(_props, cx) {
    this.watch = Boolean(props()?.watch);
    if (this.watch) {
      this.entry = null;
      this.running = null;
      cx.timer.every(TICK_MS, (cx) => this.tick(cx));
      this.tick(cx);
      return;
    }
    this.tab = "conversation";
    this.expanded = new Set();
    this.view = null;
    this.loading = null;
    this.busy = null;
    this.notice = null;
    this.arm = null;
    this.method = null;
    this.bypass = false;
    this.waitUntil = 0;
    this.composer = TextareaState.new({ placeholder: "Leave a comment", rows: 4 });
    this.replying = null;
    this.reply = null;
    cx.timer.every(TICK_MS, (cx) => this.follow(cx));
    this.follow(cx);
  }

  // Watcher: asks `gh` on a new folder or branch, after `REFRESH_MS`, or when the panel asks for a retry.
  tick(cx) {
    if (this.running) {
      if (Date.now() - this.running.since < STUCK_MS) return;
      // A stalled `gh` is given up, its late answer is dropped, the error waits `REFRESH_MS` like any other.
      this.entry = { key: this.running.key, at: Date.now() };
      this.publish({ status: "error", message: "gh did not answer within a minute.", cwd: this.running.cwd, branch: this.running.branch });
      this.running = null;
      return;
    }
    const now = this.target();
    this.learnBranch(now?.cwd, cx);
    // A new folder waits a tick for its branch instead of flashing no pull request,
    // no folder at all is no pull request at once.
    if (now?.cwd && now.branch === undefined) return;
    if (!now?.key) {
      this.entry = null;
      this.publish({ status: "none" });
      return;
    }
    const retry = shared(RETRY_KEY) ?? 0;
    if (!isStale(this.entry, now.key, Date.now()) && retry <= this.entry.at) return;
    // The answer is as old as the question, so a retry asked while `gh` runs is not lost.
    const job = { ...now, since: Date.now() };
    this.running = job;
    cx.spawn(async (cx) => {
      const answer = classify(await run(["pr", "view", "--json", SUMMARY_FIELDS.join(",")], now.cwd));
      if (this.running !== job) return;
      this.running = null;
      // The person moved on while `gh` ran, the next tick asks for where they are now.
      if (this.target()?.key !== now.key) return;
      this.entry = { key: now.key, at: job.since };
      this.publish({ ...answer, cwd: now.cwd, branch: now.branch });
      cx.notify();
    });
  }

  // The focused terminal of this computer, a space on another machine has no `gh` of ours.
  // The branch is the one `git` last named for that folder, undefined until it has.
  target() {
    const space = spaces().find((each) => each.active);
    if (!space || space.machine !== null) return null;
    const cwd = focusedFolder(focused(), panes(), space);
    const branch = this.known?.cwd === cwd ? this.known.branch : undefined;
    return { cwd, branch, key: keyOf(cwd, branch) };
  }

  // `git` is asked in the folder itself, the pane's own facts can lag a `cd` or a checkout.
  learnBranch(cwd, cx) {
    if (!cwd || (this.asking && Date.now() - this.asking < STUCK_MS)) return;
    if (this.known?.cwd === cwd && Date.now() - this.known.at < BRANCH_MS) return;
    const since = Date.now();
    this.asking = since;
    cx.spawn(async () => {
      let result = null;
      try {
        result = await exec("git", ["--no-optional-locks", "branch", "--show-current"], { cwd });
      } catch {
        // No `git` to ask means no branch, `gh` could not find a pull request either.
      }
      if (this.asking !== since) return;
      this.asking = 0;
      this.known = { cwd, at: Date.now(), branch: result?.code === 0 ? result.stdout.trim() : "" };
    });
  }

  // Shared state re-renders every mod, so write it only when it changed.
  publish(value) {
    if (JSON.stringify(shared(STATE_KEY)) !== JSON.stringify(value)) setShared(STATE_KEY, value);
  }

  // Panel: loads the shown pull request again when it changed on GitHub, moved to another branch, or got old.
  follow(cx) {
    const now = Date.now();
    // An unconfirmed button goes back to its plain label.
    if (this.arm && !isArmed(this.arm, this.arm.action, this.arm.id, now)) {
      this.arm = null;
      cx.notify();
    }
    // A stalled `gh` is given up, the person checks GitHub before trying again, the write may have landed.
    if (this.busy && now - this.busy.since >= STUCK_MS) {
      this.busy = null;
      this.notice = { error: true, text: "GitHub did not answer within a minute, check the pull request before trying again." };
      cx.notify();
    }
    // `exec` cannot be stopped, so a stalled load is dropped and the next one waits
    // `REFRESH_MS` instead of piling more `gh` calls on it every tick.
    if (this.loading && now - this.loading.since >= STUCK_MS) {
      this.loading = null;
      this.waitUntil = now + REFRESH_MS;
      this.notice = { error: true, text: STALLED };
      cx.notify();
    }
    const state = shared(STATE_KEY);
    if (this.loading || now < this.waitUntil || !isShown(layout(), "pull-request") || !needsLoad(this.view, state, now)) return;
    this.load(state, cx);
  }

  load(state, cx) {
    const job = { since: Date.now() };
    this.loading = job;
    cx.spawn(async (cx) => {
      const number = String(state.number);
      const [detail, diff, inline, merge] = await Promise.all([
        run(["pr", "view", number, "--json", DETAIL_FIELDS.join(",")], state.cwd),
        run(["pr", "diff", number, "--color", "never"], state.cwd),
        run(["api", "--paginate", `repos/{owner}/{repo}/pulls/${number}/comments`, "--jq", ".[]"], state.cwd),
        run(["api", "graphql", "-F", "owner={owner}", "-F", "repo={repo}", "-F", `number=${number}`, "-f", `query=${MERGE_QUERY}`], state.cwd),
      ]);
      if (this.loading !== job) return;
      const view = { cwd: state.cwd, number: state.number, updatedAt: state.updatedAt, at: job.since, pr: null, error: null, files: null, diffError: null, inline: [], inlineError: null, merge: null, mergeError: null };
      try {
        if (detail.error || detail.code !== 0) throw new Error(failure(detail));
        view.pr = JSON.parse(detail.stdout);
        if ((view.pr.updatedAt ?? "") > (view.updatedAt ?? "")) view.updatedAt = view.pr.updatedAt;
      } catch (error) {
        view.error = error.message;
      }
      if (diff.error || diff.code !== 0) view.diffError = failure(diff);
      else view.files = diffFiles(diff.stdout);
      try {
        if (inline.error || inline.code !== 0) throw new Error(failure(inline));
        view.inline = inline.stdout.split("\n").filter(Boolean).map((line) => JSON.parse(line));
      } catch (error) {
        view.inlineError = error.message;
      }
      try {
        if (merge.error || merge.code !== 0) throw new Error(failure(merge));
        view.merge = mergeOptions(JSON.parse(merge.stdout));
        if (!view.merge) throw new Error("GitHub did not say how this pull request merges");
      } catch (error) {
        view.mergeError = error.message;
      }
      // Another pull request starts with GitHub's defaults, the bypass box unticked,
      // and a new commit unticks it too, a bypass is chosen for the commit on screen.
      if (this.view?.cwd !== view.cwd || this.view?.number !== view.number) {
        this.expanded = new Set();
        this.method = null;
        this.bypass = false;
        this.arm = null;
      } else if (this.view?.pr?.headRefOid !== view.pr?.headRefOid) this.bypass = false;
      this.view = view;
      this.loading = null;
      cx.notify();
    });
  }

  // The page stays on screen while it loads again.
  refresh(cx) {
    this.waitUntil = 0;
    setShared(RETRY_KEY, Date.now());
    const state = shared(STATE_KEY);
    if (state?.status !== "open" || this.loading) return;
    this.load(state, cx);
  }

  // One write at a time. `confirm` buttons arm on the first click and act on the second.
  act(action, input, cx, confirm = false) {
    const view = this.view, pr = view?.pr;
    if (!pr || this.busy || !isCurrent(view, shared(STATE_KEY))) return;
    const id = armId(view);
    if (confirm && !confirmed(this.arm, action, id, Date.now())) {
      if (!isArmed(this.arm, action, id, Date.now())) this.arm = { action, id, at: Date.now() };
      cx.notify();
      return;
    }
    this.arm = null;
    // Rerun takes every failed run of the commit, one `gh` call each.
    const calls = action === "rerun" ? input.runIds.map((runId) => actionArgs(action, pr, { runId })) : [actionArgs(action, pr, input)];
    if (calls.some((args) => !args)) {
      this.notice = { error: true, text: WRITE_FIRST.has(action) ? "Write something first." : "GitHub needs a newer page for this, Refresh and try again." };
      cx.notify();
      return;
    }
    const job = { action, since: Date.now() };
    this.busy = job;
    this.notice = null;
    cx.notify();
    cx.spawn(async (cx) => {
      let result = null;
      for (const args of calls) {
        result = await run(args, view.cwd);
        if (result.error || result.code !== 0) break;
      }
      if (this.busy !== job) return;
      this.busy = null;
      if (result.error || result.code !== 0) this.notice = { error: true, text: failure(result) };
      else {
        this.notice = { error: false, text: DONE[action] };
        // A merged or closed pull request leaves the panel at once, the toast keeps the answer.
        if (action === "merge" || action === "close") notify({ title: `#${pr.number} ${DONE[action].toLowerCase().replace(".", "")}`, body: pr.title, level: "success" });
        if (action === "reply") this.replying = null;
        else if (input.body) this.composer.set_value("");
        // One reload, `follow` takes the old page, the watcher's newer `updatedAt` then matches it.
        setShared(RETRY_KEY, Date.now());
        this.waitUntil = 0;
        if (this.view === view) view.at = 0;
      }
      cx.notify();
    });
  }

  render() {
    if (this.watch) return div().id("pull-request-watch");
    const t = theme();
    const state = shared(STATE_KEY);
    const frame = v_flex().id("pull-request").size_full().min_h(0).bg(t.surface).text_size(12.5).text_color(t.foreground);
    const note = (text, color) => frame.p(14).gap(10).child(div().text_color(color ?? t.muted).child(text));
    if (state?.status === "error") {
      return note(`GitHub could not be asked about this branch: ${state.message}`, t.ansi1)
        .child(this.button(t, "retry", "Try again", (cx) => this.refresh(cx)));
    }
    if (state?.status !== "open") return note("No open pull request for the branch of the focused terminal.");
    const view = this.view;
    // A page of another folder or pull request is never drawn with live buttons.
    if (!isCurrent(view, state) || !view.pr) {
      if (!this.loading && Date.now() < this.waitUntil) return note(STALLED, t.ansi1).child(this.button(t, "retry", "Try again", (cx) => this.refresh(cx)));
      if (isCurrent(view, state) && view.error) return note(`The pull request could not be loaded: ${view.error}`, t.ansi1).child(this.button(t, "retry", "Try again", (cx) => this.refresh(cx)));
      return note(`Loading #${state.number}…`);
    }
    const pr = view.pr;
    const entries = timeline(pr, view.inline);
    const rows = checkRows(pr.statusCheckRollup);
    const tabs = [
      ["conversation", `Conversation ${entries.length + 1}`],
      ["commits", `Commits ${pr.commits?.length ?? 0}`],
      ["checks", `Checks ${rows.length}`],
      ["files", `Files changed ${pr.changedFiles ?? 0}`],
    ];
    const body = this.tab === "commits" ? this.commits(t, pr) : this.tab === "checks" ? this.checks(t, rows) : this.tab === "files" ? this.files(t, pr, view) : this.conversation(t, pr, entries, view, rows);
    return frame
      .child(this.header(t, pr, rows))
      .child(h_flex().flex_none().px(12).gap(2).border_b(1).border_color(t.border).children(tabs.map(([id, label]) =>
        div().id(`tab-${id}`).px(8).py(6).text_size(12).cursor_pointer()
          .border_b(2).border_color(this.tab === id ? t.accent : t.surface).text_color(this.tab === id ? t.foreground : t.muted)
          .hover((s) => s.text_color(t.foreground)).on_click((_e, cx) => { this.tab = id; cx.notify(); }).child(label))))
      .child(v_flex().id(`body-${this.tab}`).flex_1().min_h(0).overflow_y_scrollbar().p(12).gap(10).child(body));
  }

  // `tone`: "primary" is GitHub's green button, "danger" a red one.
  button(t, id, label, action, tone) {
    const fill = tone === "primary" ? t.ansi2 : tone === "danger" ? t.ansi1 : null;
    return div().id(`action-${id}`).flex_none().px(8).h(24).flex().items_center().rounded(6).border(1).border_color(fill ?? t.border)
      .text_size(12).text_color(fill ?? t.muted).cursor_pointer().hover((s) => s.bg(t.hover).text_color(fill ?? t.foreground))
      .on_click((_e, cx) => action(cx)).child(label);
  }

  textarea(t, state) {
    return Textarea.new(state).w_full().px(8).py(6).rounded(6).border(1).border_color(t.input).bg(t.surface).text_size(12.5).text_color(t.foreground);
  }

  // A confirm button shows GitHub's confirm label while armed, with Cancel next to it.
  confirmButton(t, key, action, label, confirmLabel, run, tone) {
    const armed = isArmed(this.arm, action, armId(this.view), Date.now());
    return h_flex().gap(6)
      .child(this.button(t, key, armed ? confirmLabel : label, run, tone))
      .when(armed, (el) => el.child(this.button(t, `${key}-cancel`, "Cancel", (cx) => { this.arm = null; cx.notify(); })));
  }

  // The bottom of the Conversation tab, GitHub's merge box: its words, the methods
  // the repository allows, the merge queue and the bypass box, the same calls as its buttons.
  mergeBox(t, pr, rows, view) {
    const tone = { good: t.ansi2, bad: t.ansi1, warn: t.ansi3, muted: t.muted };
    const merge = view.merge;
    const method = merge?.methods.includes(this.method) ? this.method : merge?.methods[0];
    // The box counts only while GitHub still lets the viewer bypass, `--admin` is never sent otherwise.
    const bypass = this.bypass && Boolean(merge?.canBypass);
    // With a merge queue every merge goes through it, unless the person bypasses the rules.
    const queued = merge?.queue && !bypass;
    const offer = canMerge(pr, merge) && (queued || Boolean(method));
    const pick = (cx, change) => { change(); this.arm = null; cx.notify(); };
    return this.card(t, "Merge", [
      ...mergeStatus(pr, rows, merge).map((line) => div().text_color(tone[line.tone]).child(line.text)),
      ...(merge ? [] : [div().text_size(11.5).text_color(t.ansi1).child(`How this repository merges could not be loaded, merge on GitHub: ${view.mergeError}`)]),
      ...(offer && merge.canBypass ? [div().id("merge-bypass").flex().items_center().gap(6).cursor_pointer().text_size(11.5).text_color(t.ansi1)
        .on_click((_e, cx) => pick(cx, () => { this.bypass = !this.bypass; }))
        .child(div().font_family(mono()).child(bypass ? "[x]" : "[ ]"))
        .child("Merge without waiting for requirements to be met (bypass rules)")] : []),
      ...(offer && !queued && merge.methods.length > 1 ? [h_flex().gap(4).flex_wrap().children(merge.methods.map((each) => div().id(`method-${each}`).px(6).h(20).flex().items_center().rounded(4).text_size(11.5).cursor_pointer()
        .bg(method === each ? t.selected : t.background).text_color(method === each ? t.foreground : t.muted)
        .on_click((_e, cx) => pick(cx, () => { this.method = each; })).child(MERGE_LABELS[each])))] : []),
      h_flex().gap(6).flex_wrap()
        .when(offer && queued, (el) => el.child(this.confirmButton(t, "enqueue", "enqueue", "Merge when ready", CONFIRM.enqueue, (cx) => this.act("enqueue", { id: merge.id }, cx, true), "primary")))
        .when(offer && !queued, (el) => el.child(this.confirmButton(t, "merge", "merge", bypass ? "Bypass rules and merge" : MERGE_LABELS[method], bypass ? CONFIRM.bypass : CONFIRM[method], (cx) => this.act("merge", { method, bypass }, cx, true), bypass ? "danger" : "primary")))
        .when(Boolean(merge?.queued), (el) => el.child(this.button(t, "dequeue", "Remove from queue", (cx) => this.act("dequeue", { id: merge.id }, cx))))
        .child(this.confirmButton(t, "close", "close", "Close pull request", CONFIRM.close, (cx) => this.act("close", {}, cx, true))),
    ]);
  }

  commentBox(t) {
    const body = () => ({ body: this.composer.value() });
    return this.card(t, "Add a comment", [
      this.textarea(t, this.composer),
      h_flex().gap(6).flex_wrap()
        .child(this.button(t, "comment", "Comment", (cx) => this.act("comment", body(), cx), "primary"))
        .child(this.button(t, "approve", "Approve", (cx) => this.act("approve", body(), cx)))
        .child(this.button(t, "request-changes", "Request changes", (cx) => this.act("request-changes", body(), cx))),
    ]);
  }

  chip(t, text, color) {
    return div().flex_none().px(6).h(18).flex().items_center().rounded(4).border(1).border_color(t.border).text_size(10.5).text_color(color ?? t.muted).child(text);
  }

  header(t, pr, rows) {
    const tone = (name) => name === "good" ? t.ansi2 : name === "bad" ? t.ansi1 : name === "warn" ? t.ansi3 : t.muted;
    const decision = DECISION[pr.reviewDecision];
    const failed = rows.some((row) => row.state === "failure"), running = rows.some((row) => row.state === "pending");
    const people = reviewers(pr);
    return v_flex().flex_none().p(12).gap(7).border_b(1).border_color(t.border)
      .child(div().font_semibold().text_size(14).child(`${pr.title} #${pr.number}`))
      .child(h_flex().gap(6).items_center().flex_wrap().text_size(11.5).text_color(t.dim)
        .child(this.chip(t, pr.isDraft ? "Draft" : "Open", pr.isDraft ? t.muted : t.ansi2))
        .child(div().child(`${pr.author?.login ?? "ghost"} wants to merge ${pr.commits?.length ?? 0} commits into`))
        .child(div().font_family(mono()).child(pr.baseRefName))
        .child(div().child("from"))
        .child(div().font_family(mono()).min_w(0).truncate().child(pr.headRefName)))
      .child(h_flex().gap(6).items_center().flex_wrap()
        .child(this.chip(t, checksSummary(rows), failed ? t.ansi1 : running ? t.ansi3 : rows.length ? t.ansi2 : t.muted))
        .when(Boolean(decision), (el) => el.child(this.chip(t, decision[0], tone(decision[1]))))
        .when(pr.mergeable === "CONFLICTING", (el) => el.child(this.chip(t, "Has conflicts", t.ansi1)))
        .child(h_flex().gap(5).text_size(11.5).text_color(t.dim)
          .child(div().text_color(t.ansi2).child(`+${pr.additions}`))
          .child(div().text_color(t.ansi1).child(`−${pr.deletions}`))))
      .when((pr.labels ?? []).length > 0, (el) => el.child(h_flex().gap(4).flex_wrap().children(pr.labels.map((label) => this.chip(t, label.name)))))
      .when(people.length > 0, (el) => el.child(h_flex().gap(8).flex_wrap().text_size(11.5).text_color(t.dim)
        .child(div().child("Reviewers"))
        .children(people.map((person) => div().child(`${person.name} ${REVIEW_WORDS[person.state] ?? person.state.toLowerCase()}`)))))
      .child(h_flex().gap(6).flex_wrap()
        .child(this.button(t, "open", "Open on GitHub", (cx) => cx.open_url(pr.url)))
        .child(this.button(t, "refresh", this.loading ? "Refreshing…" : "Refresh", (cx) => this.refresh(cx)))
        .child(pr.isDraft
          ? this.button(t, "ready", "Ready for review", (cx) => this.act("ready", {}, cx))
          : this.button(t, "draft", "Convert to draft", (cx) => this.act("draft", {}, cx))))
      .when(Boolean(this.busy), (el) => el.child(div().text_size(11.5).text_color(t.muted).child("Sending to GitHub…")))
      .when(Boolean(this.notice) && !this.busy, (el) => el.child(div().text_size(11.5).text_color(this.notice.error ? t.ansi1 : t.ansi2).child(this.notice.text)));
  }

  markdown(t, id, text) {
    // Anyone can write a link or an image in a pull request, images become links and
    // `open_url` opens only `http` and `https`.
    return TextView.markdown(id, withoutImages(text)).on_link_click((url, cx) => cx.open_url(url)).selectable(true).text_size(12.5).text_color(t.foreground);
  }

  card(t, title, children) {
    return v_flex().flex_none().rounded(8).border(1).border_color(t.border).bg(t.background)
      .child(h_flex().px(10).py(6).gap(6).border_b(1).border_color(t.border).text_size(11.5).text_color(t.dim).child(title))
      .child(v_flex().p(10).gap(8).children(children));
  }

  conversation(t, pr, entries, view, rows) {
    const items = [this.card(t, `${pr.author?.login ?? "ghost"} opened this on ${day(pr.createdAt)}`, [this.markdown(t, "description", pr.body || "No description provided.")])];
    entries.forEach((entry, index) => {
      if (entry.kind === "comment") items.push(this.card(t, `${entry.author} commented on ${day(entry.at)}`, [this.markdown(t, `comment-${index}`, entry.body)]));
      else if (entry.kind === "review") items.push(this.card(t, `${entry.author} ${REVIEW_WORDS[entry.state] ?? entry.state.toLowerCase()} on ${day(entry.at)}`, entry.body ? [this.markdown(t, `review-${index}`, entry.body)] : []));
      else items.push(this.card(t, `${entry.path}${entry.line ? `:${entry.line}` : ""}${entry.outdated ? " (outdated)" : ""}`, [
        ...entry.comments.map((comment, at) =>
          v_flex().gap(3).child(div().text_size(11.5).text_color(t.dim).child(`${comment.author} on ${day(comment.at)}`)).child(this.markdown(t, `thread-${index}-${at}`, comment.body))),
        this.replyBox(t, entry.id),
      ]));
    });
    if (view.inlineError) items.push(div().text_color(t.ansi1).child(`Inline comments could not be loaded: ${view.inlineError}`));
    items.push(this.mergeBox(t, pr, rows, view), this.commentBox(t));
    return v_flex().gap(10).children(items);
  }

  // One reply box at a time, its state is made on the click, never in `render`.
  replyBox(t, id) {
    if (this.replying !== id) {
      return h_flex().child(this.button(t, `reply-${id}`, "Reply", (cx) => {
        this.reply?.release();
        this.reply = TextareaState.new({ placeholder: "Reply", rows: 3 });
        this.replying = id;
        this.reply.focus();
        cx.notify();
      }));
    }
    return v_flex().gap(6).child(this.textarea(t, this.reply))
      .child(h_flex().gap(6)
        .child(this.button(t, `send-${id}`, "Reply", (cx) => this.act("reply", { body: this.reply.value(), threadId: id }, cx), "primary"))
        .child(this.button(t, `cancel-${id}`, "Cancel", (cx) => { this.replying = null; cx.notify(); })));
  }

  commits(t, pr) {
    return v_flex().gap(2).children((pr.commits ?? []).map((commit) => h_flex().gap(8).items_center().py(3)
      .child(div().flex_none().font_family(mono()).text_size(11).text_color(t.accent).child(commit.oid.slice(0, 7)))
      .child(div().flex_1().min_w(0).truncate().child(commit.messageHeadline))
      .child(div().flex_none().text_size(11).text_color(t.dim).child(`${commit.authors?.[0]?.login ?? ""} ${day(commit.committedDate)}`))));
  }

  checks(t, rows) {
    if (!rows.length) return div().text_color(t.muted).child("No checks reported for the last commit.");
    const color = { failure: t.ansi1, pending: t.ansi3, success: t.ansi2, skipped: t.dim };
    const runs = failedRuns(rows);
    return v_flex().gap(2)
      .when(runs.length > 0, (el) => el.child(h_flex().pb(6).child(this.button(t, "rerun", "Re-run failed jobs", (cx) => this.act("rerun", { runIds: runs }, cx)))))
      .children(rows.map((row, index) => h_flex().id(`check-${index}`).gap(8).items_center().px(6).py(4).rounded(6)
      .when(Boolean(row.url), (el) => el.cursor_pointer().hover((s) => s.bg(t.hover)).on_click((_e, cx) => cx.open_url(row.url)))
      .child(div().flex_none().w(12).text_color(color[row.state]).child(MARKS[row.state]))
      .child(div().flex_1().min_w(0).truncate().child(row.workflow ? `${row.workflow} / ${row.name}` : row.name))));
  }

  files(t, pr, view) {
    if (view.diffError) return div().text_color(t.ansi1).child(`The diff could not be loaded: ${view.diffError}`);
    const color = { add: t.ansi2, delete: t.ansi1, hunk: t.accent, context: t.foreground };
    const shade = { add: t.selection, delete: t.hover, hunk: t.raised, context: t.background };
    return v_flex().gap(8).children(view.files.map((file, index) => {
      const open = this.expanded.has(file.path);
      const lines = file.lines.slice(0, FILE_LINES_MAX);
      return v_flex().flex_none().rounded(8).border(1).border_color(t.border).bg(t.background)
        .child(h_flex().id(`file-${index}`).px(10).py(6).gap(8).items_center().cursor_pointer().hover((s) => s.bg(t.hover))
          .on_click((_e, cx) => { if (open) this.expanded.delete(file.path); else this.expanded.add(file.path); cx.notify(); })
          .child(div().flex_none().text_color(t.dim).child(open ? "▾" : "▸"))
          .child(div().flex_1().min_w(0).truncate().font_family(mono()).text_size(11.5).child(file.path))
          .child(div().flex_none().text_size(11).text_color(t.ansi2).child(`+${file.additions}`))
          .child(div().flex_none().text_size(11).text_color(t.ansi1).child(`−${file.deletions}`)))
        .when(open, (el) => el.child(v_flex().border_t(1).border_color(t.border).font_family(mono()).text_size(11.5)
          .children(lines.map((line) => div().px(10).whitespace_nowrap().bg(shade[line.kind]).text_color(color[line.kind]).child(line.text || " ")))
          .when(file.lines.length > FILE_LINES_MAX, (body) => body.child(div().px(10).py(4).text_color(t.dim)
            .child(`${file.lines.length - FILE_LINES_MAX} more lines, open the pull request on GitHub for the rest.`)))));
    }));
  }
}
