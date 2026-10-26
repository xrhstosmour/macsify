# Opens the git worktree a pane `cd`s into as a `herdr` worktree workspace, so
# it gets its own sidebar entry and the `herdr-worktree-cleanup` plugin tracks
# it. `herdr` has no event for a pane changing directory, so this hooks `PWD`.
# Only linked worktrees under `~/Developer/worktrees` that no workspace has open
# yet are opened, without taking focus so the current pane keeps its place. The
# open itself is `_herdr_open_worktree_pane` in `functions/git.fish`, which
# groups the workspace under the right repository. A `git checkout` never moves
# a pane into another worktree, only a `cd` does.
status is-interactive; or return
set -q HERDR_ENV; or return

function __herdr_worktree_open --on-variable PWD
    set -l root (git rev-parse --show-toplevel 2>/dev/null); or return
    string match -q "$HOME/Developer/worktrees/*" "$root"; or return
    set -l common_directory (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); or return
    test (git rev-parse --path-format=absolute --git-dir) != "$common_directory"; or return
    # The same worktree is only checked once per shell, so every `cd` after the first is free.
    contains -- "$root" $__herdr_worktree_checked; and return

    command -q jq; or return
    set -l worktree_list (herdr worktree list 2>/dev/null); or return
    set -l open_workspace (printf '%s' "$worktree_list" | jq -re --arg path "$root" '.result.worktrees[]? | select(.path == $path) | .open_workspace_id // empty')
    if test -n "$open_workspace"
        set -g __herdr_worktree_checked $__herdr_worktree_checked "$root"
        return
    end

    # The main checkout is the parent of the common git directory, `herdr` groups the workspace under it.
    set -l repository_root (path dirname "$common_directory")
    if _herdr_open_worktree_pane "$repository_root" "$root" (path basename "$root") (path basename "$repository_root") no-focus >/dev/null 2>&1
        set -g __herdr_worktree_checked $__herdr_worktree_checked "$root"
    end
end
