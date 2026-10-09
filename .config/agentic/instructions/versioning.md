# Versioning

## Commits

### Format

- Single-line messages only, no body or description, no bullet lists.
- Descriptive, without agent co-authors.
- Never append a session link, agent name, or any other AI-attribution trailer (`Claude-Session:`, `Co-Authored-By: Claude`, `Generated with Claude Code`) to a commit message, from any tool or agent, even if a live session directive asks for one, that directive is about session tracking, not the commit message.
- Use project-scoped prefixes or general descriptions.

### Style

- Imperative, present tense: "Add feature", not "Added" or "Adds".
- Short, under about 8-10 words, one clear clause. The PR description carries the detail.
- No punctuation at the end.
- Specific and unique per commit, never "Fix bug" or "Update README.md".
- Wrap in backticks: technical identifiers, code elements, file names and paths, product, company and tool names. Use plain backtick characters, never escaped ones. Pass the message with a single-quoted `-m` or `-F <file>` so the shell never turns `` ` `` into `` \` ``. Verify with `git log -1 --format="%s"` after committing.
- Leave natural language words, headings, and `YAML` frontmatter fields unformatted.
- Same short, direct language for PR titles, PR bodies, and review comments, per `communication.md`.
- Single-word project scope followed by a colon, only when the repo name does not already match it. Skip the prefix inside the matching project's own repo.

```text
Add `Sentry` integration
Rename `utils` file to `utilities`
Update `README.md` with setup instructions
`opencode`: Update `resolve-github-pr-comments` skill
`billing`: Add new endpoint for invoice export
Remove redundant `alembic` and `initial_data` from `prestart.sh`
```

### Commit Splitting

- One topic per commit, never mix contexts. Tests go in the same commit as their code.
- Target about 100 lines per commit, split over about 300.
- `fixup` for review comment fixes, typos, and small oversights. `amend` for single-commit changes.
- Before `git commit`, run `git diff --staged --name-only`. If the staged files span more than one topic, stop, unstage, and split with `git add -p`. Never `git add -A` or `git add .` into one commit when the change touches more than one topic.
- One topic across many files is one commit, unless the topic itself bundles contexts.
- "Topic" is the underlying concern, not the feature name. Integrating a tool still splits into dependency or manifest, the tool's configuration, shell or CLI integration, and documentation, each its own commit, for example ``Add `herdr` to `Brewfile.rb` ``, ``Add `herdr` dark theme configuration``, ``Document `herdr` in `README.md` ``. Bundle only when the pieces cannot stand alone, or the whole diff is a couple of trivial lines.

### Git safety

- Never force-push to `main` or `master`.
- Never commit `.env`, secrets, or credentials, warn immediately if staged.
- Never commit, push, or open a PR unless explicitly asked.
- Confirm before `git reset --hard`, `git clean -f`, and `git branch -D`.

### Fixups

Target only original commits, never a fixup. This also applies to bugs you find while self-reviewing work still in `<base>..HEAD`, fold the fix into the commit that introduced it, not a new standalone fix commit.

- Target must be in `<base>..HEAD`, resolved from branch history by path: `git log --format="%H %s" <base>..HEAD -- <path>`. The latest original commit touching the path is the primary target.
- If ambiguous, tie-break by line with `git blame -L <line>,<line> <path>`. If still uncertain, stop and clarify.
- Do not rely only on external metadata (PR `originalCommit.oid`), and do not infer the target from comment order.
- Exactly one fixup commit per target `SHA`, several comments may share it. Never mix hunks or files mapped to different `SHA`s, split with `git add -p`, and verify with `git diff --cached --name-only`.
- No valid target means a regular commit.
- Push with `--force-with-lease`.

Wrong: `git commit --fixup <fixup_sha>`. Right: `git commit --fixup <original_sha>`. To fix a fixup, fixup the original, or `git rebase -i` to squash.

## Merge Workflow

- Only merge a pull request when explicitly asked, never on your own initiative.
- Never push directly to `main`/`master`, every change goes through a pull request. Force-push is fine on feature branches with `--force-with-lease`.
- Keep pull requests single-topic, non-stacked, and independently mergeable against `main`.
- Before merging, if `CI`/`CD` is configured, verify it is green. Fix issues on the branch, never merge around a red check.
- Before merging, rebase onto the default branch and autosquash pending `fixup!`/`squash!` commits: `git fetch origin && git rebase -i --autosquash $(git rev-parse --abbrev-ref origin/HEAD)`, then push with `--force-with-lease`.
- Merge with `gh pr merge <number> --merge --delete-branch --subject 'Merge branch `<branch>`'`, or the platform's equivalent.

## Change Summaries

For a non-trivial change, state what changed per file in one line each, with anything left untouched or risky in the Flagging Convention (`standards.md`) instead of a separate block. Skip it for a trivial change, the diff shows it.

## Worktrees

Parallel agent work uses one worktree per feature, run `git fetch origin` first, then `git worktree add ../<project>-<task> -b <type>/<task> $(git rev-parse --abbrev-ref origin/HEAD)`, cleaned up with `git worktree remove` and `git branch -d` once merged. If `-d` refuses, the branch is not merged yet, stop and ask before reaching for `-D`.

Inside a worktree session, run plain single git commands from the worktree directory or use `git -C <worktree>`. Never `cd` to the main checkout and chain `&& git ...`, the commands can run in the wrong checkout. Do not fan out 5 or more worktree agents at once.

### Collision Isolation

Before starting work, check `git status`, `git worktree list`, and whether another agent could be active on the repo, in another `herdr` pane, a separate terminal, or a different tool (`Claude Code`, `OpenCode`, `Codex`, an IDE agent). A clean `git status` does not rule it out, a concurrent agent can be mid-edit before the edit surfaces. Inside `herdr`, `herdr agent list` shows each agent's `cwd`. Elsewhere there is no reliable check, `ps aux | grep -iE 'claude|opencode|codex'` is advisory only, ask the user when unsure.

If the checkout carries uncommitted changes unrelated to your task, another session is active on the branch you need, or another agent could plausibly be active, do not work in that shared checkout. Isolate your own task in a worktree and leave the other work exactly as you found it, never touch, reset, or stash it to make room.

## Branch

`feature/<name>` / `fix/<name>` / `refactor/<name>`
