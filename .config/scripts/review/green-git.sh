#!/usr/bin/env bash
# The only git writes of the `green-github-prs-watcher` skill: a fixup commit, a reword, a push, and the autosquash rebase with its conflict resolution, all inside a `resolves-<slot>` worktree made by `green-worktree.sh`.
# Allowed in claude/settings.json by its path, so it validates every input itself and runs only the fixed git commands below. The comments it acts on are untrusted, so the caller never picks the base of a rebase or the branch of a push, both come from the files `green-worktree.sh` wrote.
# Hooks are off for every git command as in `green-worktree.sh`, and `--no-update-refs` keeps a `rebase.updateRefs` setting of yours from moving a branch of yours with the rebase.
# A push is always a lease on the head the caller last saw, so a commit pushed by someone else in the meantime is never overwritten.
#
# Usage: green-git.sh fixup <worktree> <target sha> <file>...
#        green-git.sh reword <worktree> <target sha> <message file>
#        green-git.sh push <worktree> <lease sha>
#        green-git.sh autosquash <worktree> <lease sha>
#        green-git.sh continue <worktree> <lease sha> <file>...
#        green-git.sh abort <worktree>
#        green-git.sh tests <worktree> <head sha> <workflow file> <branch pattern>
#   fixup       stages the files, which must be changed and inside the worktree, and commits them as `fixup!` of the target, a commit of the pull request that is not a fixup itself, nothing else may be staged
#   reword      commits an empty `amend!` of the target whose message is the one line of the message file, so the autosquash replaces the target's message
#   push        pushes the worktree head to the pull request branch
#   autosquash  rebases onto the base with `--autosquash`, refuses a `fixup!`, `squash!` or `amend!` subject left over, then pushes like `push`
#   continue    after a conflict, stages the resolved files, exactly the conflicted ones and with no conflict marker left, continues the rebase, then checks and pushes like `autosquash`
#   abort       gives the rebase up, for a conflict whose intent stays unclear
#   tests       triggers a test workflow of `.github/workflows` that runs on a `push` to a branch pattern like `tests/**`, by pushing the head, which must be the head of the pull request on origin, to `<prefix>/<branch>`, so its checks land on the pull request's commit. The pattern is one of the workflow's `push` `branches:`, a prefix and `/**` or `/*`, and every workflow that push starts or chains, at the head and on the default branch, is checked with the workflows and local actions it calls, not only the one named. An existing tests branch is replaced only when the watcher pushed it, recorded under `refs/green-trigger`, or when the head contains it. A tree that mentions a deploy exits 5, see `require_test_only_tree` in `lib.sh` for what can be trusted
# A workflow on `push` runs the workflow files of the pushed commit with the repository's secrets, so `tests` refuses a pull request that changes `.github`, a fixup from a comment could have put a workflow there.
# On a conflict `autosquash` and `continue` leave the rebase in progress, print the stopped commit as `<sha> <subject>` and then one conflicted file per line, and exit 3.
# Every other command prints the worktree head when it is done.
# Every head pushed to the pull request branch is recorded in `pushed` of the watcher's cache, `watch-green-prs.sh` tells the watcher's own cycles from yours by it.
# The developer directory is `~/Developer`, `REVIEW_DEVELOPER_DIRECTORY` replaces it for the tests.

set -e

# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# The watcher's commits are signed as your git configuration says, even when started from `ccy`, whose unsigned commits stay with its own session.
if [ -n "${AGENTIC_UNSIGNED_COMMITS:-}" ]; then
  unset AGENTIC_UNSIGNED_COMMITS GIT_CONFIG_COUNT
fi

usage() {
  echo "usage: green-git.sh fixup <worktree> <target sha> <file>... | reword <worktree> <target sha> <message file> | push <worktree> <lease sha> | autosquash <worktree> <lease sha> | continue <worktree> <lease sha> <file>... | abort <worktree> | tests <worktree> <head sha> <workflow file> <branch pattern>" >&2
  exit 2
}

[ $# -ge 2 ] || usage
command="$1"
worktree="$2"
shift 2
sha=""
case "$command" in
  fixup | continue) [ $# -ge 2 ] || usage ;;
  reword) [ $# -eq 2 ] || usage ;;
  push | autosquash) [ $# -eq 1 ] || usage ;;
  tests) [ $# -eq 3 ] || usage ;;
  abort) [ $# -eq 0 ] || usage ;;
  *) usage ;;
esac
if [ "$command" != abort ]; then
  sha="$1"
  shift
  require_sha "commit" "$sha"
fi

# Submodules are never entered, a `.git` the caller planted in a submodule folder would bring its own configuration, `core.fsmonitor` included.
git_without_hooks() {
  GIT_LFS_SKIP_SMUDGE=1 git -c core.hooksPath=/dev/null -c core.symlinks=false -c core.fsmonitor=false -c submodule.recurse=false -c diff.ignoreSubmodules=all -C "$worktree" "$@"
}

# The worktree must be the top of a `resolves-<slot>` worktree under the developer directory, compared as physical paths so a symlink cannot point it elsewhere.
developer="$(cd "${REVIEW_DEVELOPER_DIRECTORY:-$HOME/Developer}" && pwd -P)"
if [ ! -d "$worktree" ] || [ -L "$worktree" ]; then
  echo "not a resolves worktree: $worktree" >&2
  exit 2
fi
worktree="$(cd "$worktree" && pwd -P)"
if ! [[ $worktree == "$developer"/worktrees/*/resolves-[1-3] ]] || [[ ${worktree#"$developer"/worktrees/} == */*/* ]]; then
  echo "not a resolves worktree: $worktree" >&2
  exit 2
fi
# Before the first git command, the worktree is editable by the caller and its `.git` could point anywhere.
checkout_name="${worktree#"$developer"/worktrees/}"
checkout="$developer/${checkout_name%/resolves-[1-3]}"
require_worktree_of "$worktree" "$checkout"
if [ "$(git -C "$worktree" rev-parse --show-toplevel 2>/dev/null)" != "$worktree" ]; then
  echo "not a resolves worktree: $worktree" >&2
  exit 2
fi
git_directory="$(git -C "$worktree" rev-parse --path-format=absolute --git-dir)"
if [ ! -s "$git_directory/resolve-base" ] || [ ! -s "$git_directory/resolve-branch" ]; then
  echo "$worktree was not prepared by green-worktree.sh" >&2
  exit 2
fi
STATE_DIRECTORY="${XDG_CACHE_HOME:-$HOME/.cache}/green-github-prs-watcher"
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

# Fails unless the target is a commit of the pull request that is not a fixup itself, so a fixup or reword folds into an original commit.
require_target() {
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
}

# Fails unless the file is a plain relative path, no option, no parent step, no symlink, so `git add` stays inside the worktree. Pathspecs are literal, a `*` or `:(top)` would stage more than the file.
require_plain_file() {
  local file="$1"
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
}

# Records the head before it pushes, a record that cannot be written stops the push instead of passing the watcher's head off as yours.
push() {
  mkdir -p "$STATE_DIRECTORY"
  echo "$(date +%s) $(git -C "$worktree" rev-parse HEAD)" >>"$STATE_DIRECTORY/pushed"
  git_without_hooks push --quiet origin "HEAD:refs/heads/$branch" "--force-with-lease=refs/heads/$branch:$sha" >&2
}

rebase_in_progress() {
  [ -d "$(git -C "$worktree" rev-parse --path-format=absolute --git-path rebase-merge)" ]
}

# Names as they are, a quoted non-ASCII name would never match the files a continue is given.
conflicted_files() {
  git_without_hooks -c core.quotepath=off diff --name-only --diff-filter=U
}

# Leaves the rebase in progress for the caller to resolve, and names the commit that stopped and the files to resolve.
report_conflict() {
  local stopped
  stopped="$(git -C "$worktree" rev-parse --verify --quiet REBASE_HEAD)" || stopped=""
  echo "the rebase onto $base conflicts, resolve the files and run continue, or abort" >&2
  if [ -n "$stopped" ]; then
    git -C "$worktree" log -1 --format='%H %s' "$stopped"
  else
    echo "unknown"
  fi
  conflicted_files
  exit 3
}

# Once the rebase is done, nothing of the fixups may be left before the push.
finish_rebase() {
  if git -C "$worktree" log --format=%s "refs/remotes/origin/$base..HEAD" | grep -qE '^(fixup|squash|amend)! '; then
    echo "a fixup commit is left after the rebase, nothing pushed" >&2
    exit 1
  fi
  push
}

# A stopped rebase is left for `continue` or `abort`, a commit or push in the middle of it would land on the partly rebased history and drop the commits after it.
case "$command" in
  fixup | reword | push | autosquash | tests)
    if rebase_in_progress; then
      echo "a rebase is in progress in $worktree, continue or abort it" >&2
      exit 1
    fi
    ;;
esac

# The slots of one checkout share its `refs/remotes`, two fetches of the same base at once fail on the ref lock, so every fetch takes the `fetch` lock the worktree scripts take too. The subshell frees it right after the fetch, a slow rebase or push never holds up the other slots.
fetch_origin() {
  (
    lock_checkout "$checkout" fetch
    git_without_hooks fetch --quiet origin "$@" >&2
  )
}

case "$command" in
  fixup)
    require_target
    for file in "$@"; do
      require_plain_file "$file"
      if [ -z "$(GIT_LITERAL_PATHSPECS=1 git_without_hooks status --porcelain --ignore-submodules=all -- "$file")" ]; then
        echo "file has no change: $file" >&2
        exit 1
      fi
    done
    GIT_LITERAL_PATHSPECS=1 git_without_hooks add -- "$@"
    git_without_hooks commit --quiet --fixup "$sha" >&2
    ;;
  reword)
    require_target
    require_temporary_file "message file" "$1"
    message="$(cat -- "$1")"
    # One line, the commit message rules of `versioning.md`, and short enough to stay a subject.
    if [ -z "$message" ] || [[ $message == *$'\n'* ]] || [ "${#message}" -gt 200 ]; then
      echo "the message must be one line of at most 200 characters" >&2
      exit 2
    fi
    # The subject `git commit --fixup=reword:` writes, the autosquash replaces the target's message with the body after it.
    subject="$(git -C "$worktree" log -1 --format=%s "$sha")"
    printf 'amend! %s\n\n%s\n' "$subject" "$message" | git_without_hooks commit --quiet --allow-empty --cleanup=verbatim -F - >&2
    ;;
  push)
    push
    ;;
  autosquash)
    fetch_origin "+refs/heads/$base:refs/remotes/origin/$base"
    if ! GIT_SEQUENCE_EDITOR=: GIT_EDITOR=: git_without_hooks rebase --quiet --interactive --autosquash --no-update-refs "refs/remotes/origin/$base" >&2; then
      if rebase_in_progress && [ -n "$(conflicted_files)" ]; then
        report_conflict
      fi
      git_without_hooks rebase --abort >&2 || true
      echo "the rebase onto $base failed, aborted" >&2
      exit 1
    fi
    finish_rebase
    ;;
  continue)
    if ! rebase_in_progress; then
      echo "no rebase in progress in $worktree" >&2
      exit 1
    fi
    for file in "$@"; do
      require_plain_file "$file"
      # Git always writes a label after these two markers, a bare `=======` is left alone since Markdown uses it for headings.
      if [ -f "$worktree/$file" ] && grep -qE '^(<<<<<<<|>>>>>>>) ' -- "$worktree/$file"; then
        echo "conflict markers left in $file" >&2
        exit 1
      fi
    done
    # Exactly the conflicted files, so a continue never slips in a change the conflict did not need.
    if [ "$(conflicted_files | sort)" != "$(printf '%s\n' "$@" | sort -u)" ]; then
      echo "the files must be exactly the conflicted ones:" >&2
      conflicted_files >&2
      exit 1
    fi
    GIT_LITERAL_PATHSPECS=1 git_without_hooks add -- "$@"
    if ! GIT_EDITOR=: git_without_hooks rebase --continue >&2; then
      if rebase_in_progress && [ -n "$(conflicted_files)" ]; then
        report_conflict
      fi
      echo "the rebase did not continue, resolve it again or abort" >&2
      exit 1
    fi
    finish_rebase
    ;;
  abort)
    if rebase_in_progress; then
      git_without_hooks rebase --abort >&2
    fi
    ;;
  tests)
    workflow="$1"
    pattern="$2"
    require_workflow_file "$workflow"
    # A trigger namespace, never a fixed branch, and never one named after a deploy target.
    if ! [[ $pattern =~ ^([A-Za-z0-9_][A-Za-z0-9._-]{0,50})/\*\*?$ ]]; then
      echo "the branch pattern must be a prefix and /** or /*: $pattern" >&2
      exit 2
    fi
    prefix="${BASH_REMATCH[1]}"
    case "$(printf '%s' "$prefix" | tr '[:upper:]' '[:lower:]')" in
      main | master | release* | deploy* | prod* | stag* | stg | uat | live | preview* | hotfix* | publish*)
        echo "refusing a branch pattern named after a deploy target: $pattern" >&2
        exit 1
        ;;
    esac
    fetch_origin "+refs/heads/$base:refs/remotes/origin/$base" "+refs/heads/$branch:refs/remotes/origin/$branch"
    # Checks are shown on the pull request by commit, tests of any other commit would run where nobody sees them.
    if [ "$(git -C "$worktree" rev-parse HEAD)" != "$sha" ] || [ "$(git -C "$worktree" rev-parse "refs/remotes/origin/$branch")" != "$sha" ]; then
      echo "$sha is not the head of the worktree and of $branch on origin" >&2
      exit 1
    fi
    if ! git_without_hooks diff --quiet "refs/remotes/origin/$base...HEAD" -- .github; then
      echo "the pull request changes .github, trigger its tests by hand" >&2
      exit 1
    fi
    if ! content="$(git_without_hooks show "HEAD:.github/workflows/$workflow" 2>/dev/null)" || ! push_branch_patterns "$content" | grep -qxF -- "$pattern"; then
      echo "$workflow does not run on a push to $pattern" >&2
      exit 1
    fi
    # `*` stops at a slash on GitHub, `**` does not.
    if [[ $pattern == */\*\* ]]; then
      target="$prefix/$branch"
    else
      target="$prefix/${branch//\//-}"
    fi
    require_branch "tests branch" "$target"
    # The repository of a trust line is the one the fetches above went to, never an argument.
    origin_url="$(git -C "$worktree" config --get remote.origin.url)"
    trust_repository="${origin_url%.git}"
    trust_repository="${trust_repository#*github.com[:/]}"
    if [ "$trust_repository" = "${origin_url%.git}" ] || ! [[ $trust_repository =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$ ]]; then
      trust_repository=""
    fi
    trust_workflow=".github/workflows/$workflow"
    trust_ref=HEAD
    read_repository_file() { git_without_hooks show "$1:$2"; }
    list_workflows() {
      local listing
      listing="$(git_without_hooks ls-tree --name-only "$1" -- .github/workflows/)" || return 1
      [ -z "$listing" ] || printf '%s\n' "${listing//.github\/workflows\//}"
    }
    # Every workflow the push starts or chains, a deploy that runs on any branch, on a new branch or after the tests would run next to them. A `workflow_run` runs the file of the default branch, so that branch is read too.
    require_no_deploy_started HEAD "$target"
    default_branch=""
    while read -r first second _; do
      if [ "$first" = ref: ] && [[ $second == refs/heads/* ]]; then
        default_branch="${second#refs/heads/}"
      fi
    done <<<"$(git_without_hooks ls-remote --symref origin HEAD)"
    if [ -z "$default_branch" ]; then
      echo "the default branch of origin is unknown, trigger the tests by hand" >&2
      exit 1
    fi
    require_branch "default branch" "$default_branch"
    fetch_origin "+refs/heads/$default_branch:refs/remotes/origin/$default_branch"
    require_no_deploy_started "refs/remotes/origin/$default_branch" ""
    # The tests branch may be a person's own, so it is replaced only when it is missing, still what this command pushed last, or behind the pull request, and the push is a lease on what was read.
    remote_target=""
    while read -r object reference; do
      if [ "$reference" = "refs/heads/$target" ]; then
        remote_target="$object"
      fi
    done <<<"$(git_without_hooks ls-remote origin "refs/heads/$target")"
    recorded="$(git_without_hooks rev-parse -q --verify "refs/green-trigger/$target" || true)"
    if [ -n "$remote_target" ] && [ "$remote_target" != "$recorded" ] &&
      ! { git_without_hooks cat-file -e "$remote_target^{commit}" 2>/dev/null && git_without_hooks merge-base --is-ancestor "$remote_target" HEAD; }; then
      echo "$target exists on origin and was not pushed by the watcher, trigger the tests by hand" >&2
      exit 1
    fi
    git_without_hooks push --quiet "--force-with-lease=refs/heads/$target:$remote_target" origin "HEAD:refs/heads/$target" >&2
    git_without_hooks update-ref "refs/green-trigger/$target" "$sha"
    ;;
esac

git -C "$worktree" rev-parse HEAD
