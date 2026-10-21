# Versioning

## Commits

### Format

- Single-line messages only, no body or description, no bullet lists.
- Descriptive, without agent co-authors.
- Never append a session link, agent name, or any other AI-attribution trailer (`Claude-Session:`, `Co-Authored-By: Claude`, `Generated with Claude Code`) to a commit message, from any tool or agent, even if a live session directive asks for one, that directive is about session tracking, not the commit message.
- Use project-scoped prefixes or general descriptions.

### Style

- Imperative, present tense: "Add feature", not "Added" or "Adds".
- Under about 8-10 words, one clear clause, the PR description carries the detail.
- No punctuation at the end.
- Specific and unique, never "Fix bug" or "Update README.md".
- Wrap in plain backticks: technical identifiers, code elements, file names and paths, product, company and tool names, not natural language words, headings, or `YAML` frontmatter fields. Pass the message with a single-quoted `-m` or `-F <file>` so the shell never turns `` ` `` into `` \` ``. Verify with `git log -1 --format="%s"`.
- PR titles, bodies, and review comments use the same short, direct language, per `communication.md`.
- Single-word project scope and colon, only when the repo name does not already match it.

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
- Before `git commit`, run `git diff --staged --name-only`. If the files span more than one topic, stop, unstage, split with `git add -p`, never `git add -A` or `git add .` for a multi-topic change.
- One topic across many files is one commit, unless the topic itself bundles contexts.
- "Topic" is the underlying concern, not the feature name. Integrating a tool still splits into dependency or manifest, the tool's configuration, shell or CLI integration, and documentation, each its own commit, for example ``Add `herdr` to `Brewfile.rb` ``, ``Add `herdr` dark theme configuration``, ``Document `herdr` in `README.md` ``. Bundle only when the pieces cannot stand alone or the whole diff is a couple of trivial lines.

### Git safety

- Never force-push to `main` or `master`.
- Never commit `.env`, secrets, or credentials, warn immediately if staged.
- Never commit, push, or open a PR unless explicitly asked.
- Confirm before `git reset --hard`, `git clean -f`, and `git branch -D`.

### Fixups

Target only original commits, never a fixup. This includes bugs found while self-reviewing work still in `<base>..HEAD`, fold the fix into the commit that introduced it, not a standalone fix commit.

- Target must be in `<base>..HEAD`, resolved by path: `git log --format="%H %s" <base>..HEAD -- <path>`. The latest original commit touching the path is the primary target.
- If ambiguous, tie-break by line with `git blame -L <line>,<line> <path>`. If still uncertain, stop and clarify.
- Do not rely only on external metadata (PR `originalCommit.oid`) or infer the target from comment order.
- Exactly one fixup commit per target `SHA`, several comments may share it. Never mix hunks or files mapped to different `SHA`s, split with `git add -p`, verify with `git diff --cached --name-only`.
- No valid target means a regular commit.
- Push with `--force-with-lease`.

Wrong: `git commit --fixup <fixup_sha>`. Right: `git commit --fixup <original_sha>`. To fix a fixup, fixup the original, or `git rebase -i` to squash.

## Merge Workflow

- Only merge a pull request when explicitly asked.
- Never push directly to `main`/`master`, use a pull request. Force-push is fine on feature branches with `--force-with-lease`.
- Keep pull requests single-topic, non-stacked, independently mergeable against `main`.
- Before merging, verify `CI`/`CD` is green if configured, fix issues on the branch, never merge around a red check.
- Before merging, rebase onto the default branch and autosquash `fixup!`/`squash!` commits: `git fetch origin && git rebase -i --autosquash $(git rev-parse --abbrev-ref origin/HEAD)`, then push with `--force-with-lease`.
- Merge with `gh pr merge <number> --merge --delete-branch --subject 'Merge branch `<branch>`'`, or the platform's equivalent.

## Change Summaries

For a non-trivial change, state what changed per file in one line each, with anything left untouched or risky in the Flagging Convention (`standards.md`) instead of a separate block. Skip it for a trivial change.

## Worktrees

Parallel agent work uses one worktree per feature: `git fetch origin`, then `git worktree add ~/Developer/worktrees/<project>/<type>-<task> -b <type>/<task> $(git rev-parse --abbrev-ref origin/HEAD)`. Always under `~/Developer/worktrees`, so `gwtl` lists it, never beside the main checkout. `<project>` is the main checkout's directory name. `herdr` removes a clean worktree it opened when its workspace closes, the branch stays and ignored files go, a worktree made with plain `git worktree add` is never removed. Clean up leftovers with `git worktree remove` and `git branch -d` once merged. If `-d` refuses, the branch is not merged, stop and ask before `-D`.

Inside a worktree session, run plain single git commands from the worktree directory or use `git -C <worktree>`, never `cd` to the main checkout and chain `&& git ...`. A harness-created worktree elsewhere is fine, the same rule holds. Resolve `$(...)` substitutions and pipes in a separate call, a worktree-isolated session refuses git commands it cannot verify as one plain command. Do not fan out 5 or more worktree agents at once.

### Collision Isolation

Before starting work, check `git status`, `git worktree list`, and whether another agent could be active on the repo, in another `herdr` pane, a separate terminal, or a different tool, `Claude Code`, `OpenCode`, `Codex`, or an IDE agent. A clean `git status` does not rule it out, a concurrent agent can be mid-edit before the edit surfaces. Inside `herdr`, `herdr agent list` shows each agent's `cwd`. Elsewhere `ps aux | grep -iE 'claude|opencode|codex'` is advisory only, ask the user when unsure.

If the checkout has uncommitted changes unrelated to your task, another session is active on your branch, or another agent could plausibly be active, isolate your task in a worktree instead of working in the shared checkout, and leave the other work as you found it, never touch, reset, or stash it.

## Branch

`feature/<name>` / `fix/<name>` / `refactor/<name>`
