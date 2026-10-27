#!/usr/bin/env bash

# Removes a linked worktree under `~/Developer/worktrees` once it is done with.
# `worktree.created` and `worktree.opened` record the worktree path and its
# workspace ID from the event payload, only worktrees `herdr` created or opened
# are ever tracked. `workspace.closed` checks the worktrees of the closed
# workspace, the `sweep` action checks every tracked one. A worktree is removed
# with `git worktree remove` only when no herdr pane is left inside it, it is on a
# branch, it has no uncommitted or untracked changes and no rebase, merge,
# cherry-pick, revert or bisect is in progress. Anything else is kept and logged.
# Ignored files such as `.env` or a build cache go with the worktree. Its branch
# is deleted only when merged, see `delete_merged_branch`. A worktree named
# `review` or `reviews`, or listed in the `protected` file, is never touched. A
# process outside `herdr`, such as an editor, does not count as a pane. Runs from
# `~/.config` without the macsify repository, so it carries its own logging,
# like `herdr-repository-sync`.
# Usage:
#   worktree-cleanup.sh <event name>

set -u

CLEANUP_SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
STATE_DIRECTORY="${XDG_CACHE_HOME:-$HOME/.cache}/herdr-worktree-cleanup"
LOG_FILE="$STATE_DIRECTORY/cleanup.log"
# One `<worktree path><tab><workspace ID>` line per tracked worktree.
TRACKED_FILE="$STATE_DIRECTORY/tracked"
LOCK_DIRECTORY="$STATE_DIRECTORY/lock"
PROTECTED_FILE="$HOME/.config/herdr-worktree-cleanup/protected"
WORKTREES_ROOT="$HOME/Developer/worktrees"
LOG_MAX_BYTES=200000
# Upper bound for each network call made while the pass lock is held, a stalled
# one would otherwise make every later event give up and go untracked.
NETWORK_TIMEOUT_SECONDS=30
# Repositories already fetched during this pass, as `|path|` entries.
fetched_checkouts=""
# herdr can still list the panes of a workspace that just closed.
SETTLE_SECONDS=3

# herdr runs plugin commands with a minimal PATH.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

detached=false
event="manual"
for argument in "$@"; do
  case "$argument" in
    --detached) detached=true ;;
    *) event="$argument" ;;
  esac
done

# Return to herdr right away, the settle wait and the sweep can take a while.
if [ "$detached" = false ]; then
  nohup env HERDR_PLUGIN_EVENT_JSON="${HERDR_PLUGIN_EVENT_JSON:-}" bash "$CLEANUP_SCRIPT_PATH" "$@" --detached >/dev/null 2>&1 &
  exit 0
fi

mkdir -p "$STATE_DIRECTORY"
touch "$TRACKED_FILE"

log() {
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$event" "$1" >>"$LOG_FILE"
}

for tool in git herdr jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    log "missing tool: $tool"
    exit 1
  fi
done

file_age_seconds() {
  echo $(($(date +%s) - $(stat -f %m "$1")))
}

# One pass at a time. The lock holds its owner's PID, a lock whose owner is gone
# belongs to a killed run and is taken over.
take_lock() {
  if mkdir "$LOCK_DIRECTORY" 2>/dev/null; then
    echo $$ >"$LOCK_DIRECTORY/pid"
    return 0
  fi
  local owner
  owner=$(cat "$LOCK_DIRECTORY/pid" 2>/dev/null)
  if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
    return 1
  fi
  if [ -z "$owner" ] && [ "$(file_age_seconds "$LOCK_DIRECTORY")" -lt 30 ]; then
    return 1
  fi
  # Rename the stale lock away first, only one of several runs seeing a dead
  # owner can win the rename, the others retry.
  mv "$LOCK_DIRECTORY" "$LOCK_DIRECTORY.stale.$$" 2>/dev/null || return 1
  rm -rf "$LOCK_DIRECTORY.stale.$$"
  mkdir "$LOCK_DIRECTORY" 2>/dev/null || return 1
  echo $$ >"$LOCK_DIRECTORY/pid"
}

release_lock() {
  if [ "$(cat "$LOCK_DIRECTORY/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$LOCK_DIRECTORY"
  fi
}

# Wait outside the lock, so a recording event is not stuck behind it.
case "$event" in
  workspace.closed | sweep) sleep "$SETTLE_SECONDS" ;;
esac

# A concurrent run may be mid-record or mid-sweep, wait for it instead of dropping an event.
attempts=0
until take_lock; do
  attempts=$((attempts + 1))
  if [ "$attempts" -ge 30 ]; then
    log "skipped, another pass is running"
    exit 0
  fi
  sleep 1
done
trap release_lock EXIT

if [ -f "$LOG_FILE" ] && [ "$(stat -f %z "$LOG_FILE")" -gt "$LOG_MAX_BYTES" ]; then
  tail -n 500 "$LOG_FILE" >"$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

# Usage:
#   untrack <path>
untrack() {
  local prefix temporary
  prefix=$(printf '%s\t' "$1")
  temporary=$(mktemp "$TRACKED_FILE.XXXXXX") || return
  # `grep` exits 1 when no line is left, that is fine, any higher status is a
  # real failure and must not replace the list with a truncated one.
  grep -vF -- "$prefix" "$TRACKED_FILE" >"$temporary"
  if [ $? -le 1 ]; then
    mv "$temporary" "$TRACKED_FILE"
  else
    rm -f "$temporary"
    log "could not update the tracked list"
  fi
}

record_worktree() {
  local path workspace
  if ! path=$(printf '%s' "${HERDR_PLUGIN_EVENT_JSON:-}" | jq -r '.data.worktree.path // .data.workspace.worktree.checkout_path // empty'); then
    log "could not parse the event payload"
    return
  fi
  workspace=$(printf '%s' "${HERDR_PLUGIN_EVENT_JSON:-}" | jq -r '.data.workspace.workspace_id // .data.worktree.open_workspace_id // empty')
  if [ -z "$path" ] || [ ! -d "$path" ]; then
    log "no worktree path in the event payload"
    return
  fi
  path=$(cd "$path" && pwd -P)
  case "$path" in
    "$WORKTREES_ROOT"/*) ;;
    *) return ;;
  esac
  if is_protected "$path"; then
    return
  fi
  # A reopened worktree belongs to its new workspace.
  untrack "$path"
  printf '%s\t%s\n' "$path" "$workspace" >>"$TRACKED_FILE"
  log "tracking: $path ($workspace)"
}

# Runs a command and kills it after a time limit, macOS has no `timeout`. The
# watchdog's output goes to `/dev/null` so a command substitution around this
# does not wait for its sleep.
# Usage:
#   run_bounded <seconds> <command and arguments...>
run_bounded() {
  local limit="$1" pid watchdog status
  shift
  "$@" &
  pid=$!
  (sleep "$limit" && kill "$pid" 2>/dev/null) >/dev/null 2>&1 &
  watchdog=$!
  wait "$pid"
  status=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  return "$status"
}

# A worktree kept on purpose, never tracked, removed or stripped of its branch.
# Any directory named `review` or `reviews`, plus every directory name or
# physical absolute path (symlinks resolved, no `~`) listed one per line in
# `~/.config/herdr-worktree-cleanup/protected`.
# Usage:
#   is_protected <path>
is_protected() {
  case "$(basename "$1")" in
    review | reviews) return 0 ;;
  esac
  [ -f "$PROTECTED_FILE" ] || return 1
  grep -qxF -e "$1" -e "$(basename "$1")" "$PROTECTED_FILE"
}

# Deletes the branch a removed worktree was on, only when its work is merged:
# the tip is an ancestor of the origin default branch, or the tip is exactly the
# head of a merged pull request, which covers squash and rebase merges. A branch
# that gained commits after its pull request merged is kept. The default branch
# is never deleted.
# Usage:
#   delete_merged_branch <main checkout> <branch>
delete_merged_branch() {
  local main_checkout="$1" branch="$2" default_reference tip merged_head
  default_reference=$(git -C "$main_checkout" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || {
    log "branch kept, no origin default branch: $branch"
    return
  }
  if [ "$branch" = "${default_reference#origin/}" ]; then
    return
  fi
  tip=$(git -C "$main_checkout" rev-parse --verify --quiet "refs/heads/$branch") || {
    log "branch kept, no local branch named: $branch"
    return
  }

  # Already merged by the last known refs needs no fetch, the network calls run
  # while the pass lock is held and every waiting event gives up after 30 s.
  # One fetch per repository per pass, the sweep can remove several worktrees.
  if ! git -C "$main_checkout" merge-base --is-ancestor "$tip" "$default_reference"; then
    case "$fetched_checkouts" in
      *"|$main_checkout|"*) ;;
      *)
        fetched_checkouts="$fetched_checkouts|$main_checkout|"
        if ! GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=10' run_bounded "$NETWORK_TIMEOUT_SECONDS" git -C "$main_checkout" fetch origin --quiet >>"$LOG_FILE" 2>&1; then
          log "fetch failed, checking merge state against the last known refs: $main_checkout"
        fi
        ;;
    esac
  fi

  if git -C "$main_checkout" merge-base --is-ancestor "$tip" "$default_reference"; then
    # `git branch -d` compares against the branch's upstream or the checkout's
    # `HEAD`, not the default branch, so it can refuse a provably merged branch.
    if git -C "$main_checkout" branch -D "$branch" >>"$LOG_FILE" 2>&1; then
      log "branch deleted, merged into $default_reference: $branch"
    else
      log "branch delete failed: $branch"
    fi
    return
  fi

  if command -v gh >/dev/null 2>&1; then
    merged_head=$(cd "$main_checkout" && run_bounded "$NETWORK_TIMEOUT_SECONDS" gh pr list --head "$branch" --state merged --json headRefOid --jq '.[].headRefOid' 2>>"$LOG_FILE") || merged_head=""
    if printf '%s\n' "$merged_head" | grep -qx -- "$tip"; then
      # `git branch -d` cannot see a squash merge, the tip match above is the proof.
      if git -C "$main_checkout" branch -D "$branch" >>"$LOG_FILE" 2>&1; then
        log "branch deleted, its tip is the head of a merged pull request: $branch"
      else
        log "branch delete failed: $branch"
      fi
      return
    fi
  fi
  log "branch kept, not merged: $branch"
}

# Usage:
#   pane_inside <path>, reads the pane directories in $pane_directories
pane_inside() {
  local directory
  while IFS= read -r directory; do
    case "$directory" in
      "$1" | "$1"/*) return 0 ;;
    esac
  done <<<"$pane_directories"
  return 1
}

# Usage:
#   sweep_worktree <path>
sweep_worktree() {
  local path="$1"

  if [ ! -d "$path" ]; then
    untrack "$path"
    return
  fi

  if is_protected "$path"; then
    log "kept, protected: $path"
    untrack "$path"
    return
  fi

  # A pane lists its launch directory and the live one of its foreground process,
  # an agent started with `claude -w` only shows up in the second.
  if pane_inside "$path"; then
    return
  fi

  local main_checkout
  main_checkout=$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
    log "not a git worktree, untracked: $path"
    untrack "$path"
    return
  }
  main_checkout="${main_checkout%/.git}"

  # Commits made on a detached HEAD are reachable from nothing once the worktree
  # and its reflog are gone.
  if ! git -C "$path" symbolic-ref --quiet HEAD >/dev/null; then
    log "kept, detached HEAD: $path"
    return
  fi

  # `--untracked-files=all` so a new, never added file counts as work worth keeping.
  local status_output
  if ! status_output=$(git -C "$path" status --porcelain --untracked-files=all 2>&1); then
    log "kept, git status failed: $path"
    return
  fi
  if [ -n "$status_output" ]; then
    log "kept, uncommitted or untracked changes: $path"
    return
  fi

  local state
  for state in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do
    if [ -e "$(git -C "$path" rev-parse --path-format=absolute --git-path "$state")" ]; then
      log "kept, $state in progress: $path"
      return
    fi
  done

  local branch
  # The full ref, `--short` gives `heads/<name>` when a tag has the same name.
  branch=$(git -C "$path" symbolic-ref HEAD)
  branch="${branch#refs/heads/}"

  # No `--force`, git itself refuses a locked or dirty worktree.
  if git -C "$main_checkout" worktree remove "$path" >>"$LOG_FILE" 2>&1; then
    log "removed, ignored files deleted: $path"
    untrack "$path"
    delete_merged_branch "$main_checkout" "$branch"
  else
    log "remove failed: $path"
  fi
}

case "$event" in
  worktree.created | worktree.opened)
    record_worktree
    exit 0
    ;;
esac

# A `workspace.closed` event sweeps only the closed workspace's worktrees. If its
# payload carries no workspace ID, fall back to every tracked worktree, the pane
# check still protects the ones in use.
closed_workspace=""
if [ "$event" = "workspace.closed" ]; then
  closed_workspace=$(printf '%s' "${HERDR_PLUGIN_EVENT_JSON:-}" | jq -r '.data.workspace_id // .data.workspace.workspace_id // empty' 2>/dev/null)
  if [ -z "$closed_workspace" ]; then
    log "no workspace ID in the event payload, sweeping every tracked worktree, payload keys: $(printf '%s' "${HERDR_PLUGIN_EVENT_JSON:-}" | jq -c '.data | keys' 2>/dev/null)"
  fi
fi

if ! pane_list=$(herdr pane list 2>>"$LOG_FILE"); then
  log "could not list herdr panes"
  exit 1
fi
# An unexpected output shape must stop the sweep, an empty directory list would
# read as no pane anywhere and every clean worktree would be removed. Panes with
# no `cwd` at all mean `herdr` renamed the key, an empty list is a real answer.
if ! printf '%s' "$pane_list" | jq -e '.result.panes | type == "array" and (length == 0 or any(.[]; (.cwd // "") != ""))' >/dev/null 2>&1; then
  log "unexpected herdr pane list output"
  exit 1
fi
if ! pane_directories=$(printf '%s' "$pane_list" | jq -r '.result.panes[] | (.cwd // empty), (.foreground_cwd // empty)'); then
  log "could not read the herdr pane directories"
  exit 1
fi

# Compare resolved paths, the tracked ones are resolved the same way.
normalized_directories=""
while IFS= read -r directory; do
  if [ -n "$directory" ] && [ -d "$directory" ]; then
    normalized_directories="$normalized_directories$(cd "$directory" && pwd -P)"$'\n'
  fi
done <<<"$pane_directories"
pane_directories="$normalized_directories"

while IFS=$'\t' read -r path workspace; do
  [ -n "$path" ] || continue
  if [ -n "$closed_workspace" ] && [ "$workspace" != "$closed_workspace" ]; then
    continue
  fi
  sweep_worktree "$path"
done <"$TRACKED_FILE"
