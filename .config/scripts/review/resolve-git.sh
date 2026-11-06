#!/usr/bin/env bash
# The only git writes of the `resolve-github-prs-comments-watcher` skill: a fixup commit, a push, and the autosquash rebase, all inside a `resolves` worktree made by `resolve-worktree.sh`.
# Allowed in claude/settings.json by its path, so it validates every input itself and runs only the fixed git commands below. The comments it acts on are untrusted, so the caller never picks the base of a rebase or the branch of a push, both come from the files `resolve-worktree.sh` wrote.
# Hooks are off for every git command as in `resolve-worktree.sh`, and `--no-update-refs` keeps a `rebase.updateRefs` setting of yours from moving a branch of yours with the rebase.
# A push is always a lease on the head the caller last saw, so a commit pushed by someone else in the meantime is never overwritten.
#
# Usage: resolve-git.sh fixup <worktree> <target sha> <file>...
#        resolve-git.sh push <worktree> <lease sha>
#        resolve-git.sh autosquash <worktree> <lease sha>
#   fixup       stages the files, which must be changed and inside the worktree, and commits them as `fixup!` of the target, a commit of the pull request that is not a fixup itself, nothing else may be staged
#   push        pushes the worktree head to the pull request branch
#   autosquash  rebases onto the base with `--autosquash`, aborts and exits 3 on a conflict, refuses a `fixup!`, `squash!` or `amend!` subject left over, then pushes like `push`
# Every command prints the worktree head when it is done.
# The developer directory is `~/Developer`, `REVIEW_DEVELOPER_DIRECTORY` replaces it for the tests.

set -e

# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  echo "usage: resolve-git.sh fixup <worktree> <target sha> <file>... | push <worktree> <lease sha> | autosquash <worktree> <lease sha>" >&2
  exit 2
}

[ $# -ge 3 ] || usage
command="$1"
worktree="$2"
sha="$3"
shift 3
case "$command" in
  fixup) [ $# -ge 1 ] || usage ;;
  push | autosquash) [ $# -eq 0 ] || usage ;;
  *) usage ;;
esac
require_sha "commit" "$sha"

# Submodules are never entered, a `.git` the caller planted in a submodule folder would bring its own configuration, `core.fsmonitor` included.
git_without_hooks() {
  GIT_LFS_SKIP_SMUDGE=1 git -c core.hooksPath=/dev/null -c core.symlinks=false -c core.fsmonitor=false -c submodule.recurse=false -c diff.ignoreSubmodules=all -C "$worktree" "$@"
}

# The worktree must be the top of a `resolves` worktree under the developer directory, compared as physical paths so a symlink cannot point it elsewhere.
developer="$(cd "${REVIEW_DEVELOPER_DIRECTORY:-$HOME/Developer}" && pwd -P)"
if [ ! -d "$worktree" ] || [ -L "$worktree" ]; then
  echo "not a resolves worktree: $worktree" >&2
  exit 2
fi
worktree="$(cd "$worktree" && pwd -P)"
if ! [[ $worktree == "$developer"/worktrees/*/resolves ]] || [[ ${worktree#"$developer"/worktrees/} == */*/* ]]; then
  echo "not a resolves worktree: $worktree" >&2
  exit 2
fi
# Before the first git command, the worktree is editable by the caller and its `.git` could point anywhere.
checkout_name="${worktree#"$developer"/worktrees/}"
require_worktree_of "$worktree" "$developer/${checkout_name%/resolves}"
if [ "$(git -C "$worktree" rev-parse --show-toplevel 2>/dev/null)" != "$worktree" ]; then
  echo "not a resolves worktree: $worktree" >&2
  exit 2
fi
git_directory="$(git -C "$worktree" rev-parse --path-format=absolute --git-dir)"
if [ ! -s "$git_directory/resolve-base" ] || [ ! -s "$git_directory/resolve-branch" ]; then
  echo "$worktree was not prepared by resolve-worktree.sh" >&2
  exit 2
fi
base="$(cat "$git_directory/resolve-base")"
branch="$(cat "$git_directory/resolve-branch")"
require_branch base "$base"
require_branch branch "$branch"
case "$branch" in
  main | master)
    echo "refusing to push to $branch" >&2
    exit 2
    ;;
esac

# Whether a commit is on the pull request, reachable from the head and not from the base.
on_pull_request() {
  git -C "$worktree" merge-base --is-ancestor "$1" HEAD && ! git -C "$worktree" merge-base --is-ancestor "$1" "refs/remotes/origin/$base"
}

push() {
  git_without_hooks push --quiet origin "HEAD:refs/heads/$branch" "--force-with-lease=refs/heads/$branch:$sha" >&2
}

case "$command" in
  fixup)
    if ! git -C "$worktree" cat-file -e "$sha^{commit}" 2>/dev/null || ! on_pull_request "$sha"; then
      echo "$sha is not a commit of the pull request" >&2
      exit 1
    fi
    if git -C "$worktree" log -1 --format=%s "$sha" | grep -qE '^(fixup|squash|amend)! '; then
      echo "$sha is a fixup itself, target the original commit" >&2
      exit 1
    fi
    if ! git -C "$worktree" diff --cached --quiet; then
      echo "something is staged already in $worktree" >&2
      exit 1
    fi
    for file in "$@"; do
      # A plain relative path, no option, no parent step, no symlink, so `git add` stays inside the worktree. Pathspecs are literal, a `*` or `:(top)` would stage more than the file.
      if [[ $file == /* || $file == -* || $file == ../* || $file == */../* || $file == *$'\n'* ]] || [ -L "$worktree/$file" ]; then
        echo "invalid file: $file" >&2
        exit 2
      fi
      # No submodule and no `.git`, in any case since macOS folders ignore it, a commit of either would point the pull request at a repository the caller picked.
      if [[ "$(printf '%s' "/$file/" | tr '[:upper:]' '[:lower:]')" == */.git/* ]] || [ -n "$(find "$worktree/$file" -iname .git -print -quit 2>/dev/null)" ] ||
        GIT_LITERAL_PATHSPECS=1 git_without_hooks ls-files --stage -- "$file" | grep -q '^160000 '; then
        echo "submodule or .git refused: $file" >&2
        exit 2
      fi
      if [ -z "$(GIT_LITERAL_PATHSPECS=1 git_without_hooks status --porcelain --ignore-submodules=all -- "$file")" ]; then
        echo "file has no change: $file" >&2
        exit 1
      fi
    done
    GIT_LITERAL_PATHSPECS=1 git_without_hooks add -- "$@"
    git_without_hooks commit --quiet --fixup "$sha" >&2
    ;;
  push)
    push
    ;;
  autosquash)
    git_without_hooks fetch --quiet origin "+refs/heads/$base:refs/remotes/origin/$base" >&2
    if ! GIT_SEQUENCE_EDITOR=: GIT_EDITOR=: git_without_hooks rebase --quiet --interactive --autosquash --no-update-refs "refs/remotes/origin/$base" >&2; then
      git_without_hooks rebase --abort >&2 || true
      echo "the rebase onto $base conflicts, aborted" >&2
      exit 3
    fi
    if git -C "$worktree" log --format=%s "refs/remotes/origin/$base..HEAD" | grep -qE '^(fixup|squash|amend)! '; then
      echo "a fixup commit is left after the rebase, nothing pushed" >&2
      exit 1
    fi
    push
    ;;
esac

git -C "$worktree" rev-parse HEAD
