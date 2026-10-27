#!/bin/bash

# Checks that `worktree-cleanup.sh` keeps a worktree when `herdr` returns a pane
# list it cannot read or when it holds untracked work, removes a clean one when
# the list is valid and empty, and deletes the branch only when it is merged
# into the origin default branch. Runs against a temporary `HOME`, never touches
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

# A fake `herdr` printing whatever the test put in `pane_list.json`.
cat >"$TEST_HOME/bin/herdr" <<'FAKE'
#!/bin/bash
cat "$(dirname "$0")/pane_list.json"
FAKE
# A fake `gh` that knows no merged pull request, so only ancestry decides.
printf '#!/bin/bash\n' >"$TEST_HOME/bin/gh"
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

# A clean worktree is removed, and its branch, merged into `origin/main`, goes too.
run_sweep
if [ -d "$worktree" ]; then
  echo "FAIL: clean worktree with no pane was not removed"
  exit 1
fi
if branch_exists fix/example; then
  echo "FAIL: merged branch fix/example was not deleted"
  exit 1
fi

# A branch with a commit `origin/main` does not have is kept after its worktree goes.
unmerged_worktree="$TEST_HOME/Developer/worktrees/project/feature-unmerged"
git -C "$repository" worktree add --quiet "$unmerged_worktree" -b feature/unmerged
git -C "$unmerged_worktree" commit --quiet --allow-empty -m 'Unmerged work'
run_sweep "$(cd "$unmerged_worktree" && pwd -P)"
if [ -d "$unmerged_worktree" ]; then
  echo "FAIL: clean worktree on an unmerged branch was not removed"
  exit 1
fi
if ! branch_exists feature/unmerged; then
  echo "FAIL: unmerged branch feature/unmerged was deleted"
  exit 1
fi

echo "PASS: worktree-cleanup"
