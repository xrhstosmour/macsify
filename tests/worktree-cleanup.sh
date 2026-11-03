#!/bin/bash

# Checks that `worktree-cleanup.sh` keeps a worktree when `herdr` returns a pane
# list it cannot read or when it holds untracked work, removes a clean one when
# the list is valid and empty, and removes it, with its branch, only when the
# branch is merged: into the origin default branch, or as the head of a merged
# pull request. An unmerged branch keeps its worktree, and so does a protected
# name such as `playground`. Runs against a temporary `HOME`, never touches
# real worktrees.

set -e

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Overridable so the test can be pointed at an older copy of the script.
CLEANUP_SCRIPT="${CLEANUP_SCRIPT:-$TESTS_SCRIPT_DIRECTORY/../.config/herdr-worktree-cleanup/worktree-cleanup.sh}"

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

export HOME="$TEST_HOME"
export XDG_CACHE_HOME="$TEST_HOME/.cache"
export GIT_CONFIG_GLOBAL="$TEST_HOME/.gitconfig"
git config --global user.name tester
git config --global user.email tester@example.invalid
git config --global init.defaultBranch main

mkdir -p "$TEST_HOME/bin" "$XDG_CACHE_HOME/herdr-worktree-cleanup"

# A fake `herdr` printing whatever the test put in `pane_list.json`, or from its
# second call on `pane_list_later.json` when there is one, a pane opening mid-sweep.
cat >"$TEST_HOME/bin/herdr" <<'FAKE'
#!/bin/bash
directory=$(dirname "$0")
calls=$(cat "$directory/calls" 2>/dev/null || echo 0)
echo $((calls + 1)) >"$directory/calls"
if [ "$calls" -ge 1 ] && [ -f "$directory/pane_list_later.json" ]; then
  cat "$directory/pane_list_later.json"
else
  cat "$directory/pane_list.json"
fi
FAKE
# A fake `gh` that prints the merged pull request heads a test puts in `merged_heads`,
# none by default, so only ancestry decides.
cat >"$TEST_HOME/bin/gh" <<'FAKE'
#!/bin/bash
cat "$(dirname "$0")/merged_heads" 2>/dev/null
exit 0
FAKE
chmod +x "$TEST_HOME/bin/herdr" "$TEST_HOME/bin/gh"
export PATH="$TEST_HOME/bin:$PATH"

origin="$TEST_HOME/origin.git"
repository="$TEST_HOME/Developer/project"
worktree="$TEST_HOME/Developer/worktrees/project/fix-example"
mkdir -p "$repository"
git init --quiet --bare "$origin"
git -C "$repository" init --quiet
git -C "$repository" commit --quiet --allow-empty -m 'Initial commit'
git -C "$repository" remote add origin "$origin"
git -C "$repository" push --quiet -u origin main
git -C "$repository" remote set-head origin main
git -C "$repository" worktree add --quiet "$worktree" -b fix/example

physical_worktree=$(cd "$worktree" && pwd -P)

# Usage:
#   branch_exists <branch>
branch_exists() {
  git -C "$repository" rev-parse --verify --quiet "refs/heads/$1" >/dev/null
}

# The script prepends `Homebrew`'s directories to `PATH`, which would put a real
# `herdr` ahead of the fake one, so run a copy without that line.
cleanup_copy="$TEST_HOME/worktree-cleanup.sh"
grep -v '^export PATH=' "$CLEANUP_SCRIPT" >"$cleanup_copy"

# Usage:
#   run_sweep [worktree path, defaults to the `fix/example` one]
run_sweep() {
  rm -f "$TEST_HOME/bin/calls"
  printf '%s\tworkspace-1\n' "${1:-$physical_worktree}" >"$XDG_CACHE_HOME/herdr-worktree-cleanup/tracked"
  # An unreadable pane list exits 1 on purpose, only the worktree outcome is asserted.
  bash "$cleanup_copy" sweep --detached || true
}

# Panes without a `cwd` key mean `herdr` changed its output, nothing may be removed.
echo '{"result":{"panes":[{"directory":"/somewhere"}]}}' >"$TEST_HOME/bin/pane_list.json"
run_sweep
if [ ! -d "$worktree" ]; then
  echo "FAIL: worktree removed although the pane list had no cwd key"
  exit 1
fi

# A pane open inside the worktree keeps it.
printf '{"result":{"panes":[{"cwd":"%s"}]}}' "$physical_worktree" >"$TEST_HOME/bin/pane_list.json"
run_sweep
if [ ! -d "$worktree" ]; then
  echo "FAIL: worktree removed although a pane is open inside it"
  exit 1
fi

# From here on no pane is inside any worktree.
printf '{"result":{"panes":[{"cwd":"%s"}]}}' "$TEST_HOME" >"$TEST_HOME/bin/pane_list.json"

# A new, never added file is work worth keeping.
touch "$worktree/notes.txt"
run_sweep
if [ ! -d "$worktree" ]; then
  echo "FAIL: worktree removed although it had an untracked file"
  exit 1
fi
rm "$worktree/notes.txt"

# A clean worktree is removed, and its branch, merged into `origin/main`, goes
# too. Origin is unreachable, a branch merged by the last known refs needs no fetch.
mv "$origin" "$origin.offline"
run_sweep
mv "$origin.offline" "$origin"
if grep -q 'fetch failed' "$XDG_CACHE_HOME/herdr-worktree-cleanup/cleanup.log"; then
  echo "FAIL: fetched origin for a branch already merged by the last known refs"
  exit 1
fi
if [ -d "$worktree" ]; then
  echo "FAIL: clean worktree with no pane was not removed"
  exit 1
fi
if branch_exists fix/example; then
  echo "FAIL: merged branch fix/example was not deleted"
  exit 1
fi

# A branch with a commit `origin/main` does not have keeps its worktree whole, and its branch.
unmerged_worktree="$TEST_HOME/Developer/worktrees/project/feature-unmerged"
git -C "$repository" worktree add --quiet "$unmerged_worktree" -b feature/unmerged
git -C "$unmerged_worktree" commit --quiet --allow-empty -m 'Unmerged work'
run_sweep "$(cd "$unmerged_worktree" && pwd -P)"
if [ ! -d "$unmerged_worktree" ]; then
  echo "FAIL: clean worktree on an unmerged branch was removed"
  exit 1
fi
if ! branch_exists feature/unmerged; then
  echo "FAIL: unmerged branch feature/unmerged was deleted"
  exit 1
fi

# A merged pull request whose head is the branch tip (a squash merge, which
# ancestry cannot see) lets the worktree and branch go.
git -C "$unmerged_worktree" rev-parse HEAD >"$TEST_HOME/bin/merged_heads"
run_sweep "$(cd "$unmerged_worktree" && pwd -P)"
if [ -d "$unmerged_worktree" ]; then
  echo "FAIL: worktree on a branch merged as a pull request was not removed"
  exit 1
fi
if branch_exists feature/unmerged; then
  echo "FAIL: branch merged as a pull request was not deleted"
  exit 1
fi

# A pull request merged from an older tip does not count, the branch gained commits since.
stale_worktree="$TEST_HOME/Developer/worktrees/project/feature-stale"
git -C "$repository" worktree add --quiet "$stale_worktree" -b feature/stale
git -C "$stale_worktree" commit --quiet --allow-empty -m 'Merged part'
git -C "$stale_worktree" rev-parse HEAD >"$TEST_HOME/bin/merged_heads"
git -C "$stale_worktree" commit --quiet --allow-empty -m 'Added after the merge'
run_sweep "$(cd "$stale_worktree" && pwd -P)"
if [ ! -d "$stale_worktree" ]; then
  echo "FAIL: worktree with commits after its pull request merged was removed"
  exit 1
fi
rm -f "$TEST_HOME/bin/merged_heads"

# A pane that opens after the first pane list, while the merge is checked, keeps a merged worktree.
reopened_worktree="$TEST_HOME/Developer/worktrees/project/feature-reopened"
git -C "$repository" worktree add --quiet "$reopened_worktree" -b feature/reopened
physical_reopened=$(cd "$reopened_worktree" && pwd -P)
printf '{"result":{"panes":[{"cwd":"%s"}]}}' "$physical_reopened" >"$TEST_HOME/bin/pane_list_later.json"
run_sweep "$physical_reopened"
rm -f "$TEST_HOME/bin/pane_list_later.json"
if [ ! -d "$reopened_worktree" ]; then
  echo "FAIL: worktree removed although a pane opened in it before the removal"
  exit 1
fi

# A worktree kept unmerged when its workspace closed goes on a later close of another
# workspace, once its branch is merged.
closed_worktree="$TEST_HOME/Developer/worktrees/project/feature-closed"
git -C "$repository" worktree add --quiet "$closed_worktree" -b feature/closed
git -C "$closed_worktree" commit --quiet --allow-empty -m 'Unmerged when closed'
rm -f "$TEST_HOME/bin/calls"
printf '%s\tworkspace-1\n' "$(cd "$closed_worktree" && pwd -P)" >"$XDG_CACHE_HOME/herdr-worktree-cleanup/tracked"
HERDR_PLUGIN_EVENT_JSON='{"data":{"workspace_id":"workspace-1"}}' bash "$cleanup_copy" workspace.closed --detached || true
if [ ! -d "$closed_worktree" ]; then
  echo "FAIL: worktree on an unmerged branch was removed when its workspace closed"
  exit 1
fi
git -C "$closed_worktree" rev-parse HEAD >"$TEST_HOME/bin/merged_heads"
rm -f "$TEST_HOME/bin/calls"
HERDR_PLUGIN_EVENT_JSON='{"data":{"workspace_id":"workspace-2"}}' bash "$cleanup_copy" workspace.closed --detached || true
rm -f "$TEST_HOME/bin/merged_heads"
if [ -d "$closed_worktree" ]; then
  echo "FAIL: worktree kept unmerged at its workspace's close was not removed once merged"
  exit 1
fi

# A detached HEAD and a rebase in progress keep a merged worktree, as in the app mod's
# `tests/worktree-cleanup-application.mjs`, the two must decide alike.
detached_worktree="$TEST_HOME/Developer/worktrees/project/feature-detached"
git -C "$repository" worktree add --quiet --detach "$detached_worktree"
run_sweep "$(cd "$detached_worktree" && pwd -P)"
if [ ! -d "$detached_worktree" ]; then
  echo "FAIL: worktree on a detached HEAD was removed"
  exit 1
fi
rebasing_worktree="$TEST_HOME/Developer/worktrees/project/feature-rebasing"
git -C "$repository" worktree add --quiet "$rebasing_worktree" -b feature/rebasing
mkdir -p "$(git -C "$rebasing_worktree" rev-parse --path-format=absolute --git-path rebase-merge)"
run_sweep "$(cd "$rebasing_worktree" && pwd -P)"
if [ ! -d "$rebasing_worktree" ]; then
  echo "FAIL: worktree with a rebase in progress was removed"
  exit 1
fi

# Protected names are never touched, even clean and merged.
for protected_name in review reviews playground trivial trivials; do
  protected_worktree="$TEST_HOME/Developer/worktrees/project/$protected_name"
  git -C "$repository" worktree add --quiet "$protected_worktree" -b "feature/$protected_name"
  run_sweep "$(cd "$protected_worktree" && pwd -P)"
  if [ ! -d "$protected_worktree" ]; then
    echo "FAIL: protected worktree $protected_name was removed"
    exit 1
  fi
done

echo "PASS: worktree-cleanup"
