#!/usr/bin/env bash

# Runs what the `gfrb` fish abbreviation (`git_fetch_and_rebase`) does, in every
# herdr pane whose checkout is on `main` or `master`: fetch `origin`, then
# rebase onto the origin default branch with `--autosquash --autostash`. Only
# `origin` is fetched, unlike `gfrb`, the rebase reads nothing else and every
# extra remote would lengthen the pass that holds the lock. Run by
# herdr on startup and on workspace, worktree and tab events (see
# `herdr-plugin.toml`), or by hand with explicit paths. Checkouts on any other
# branch, with uncommitted changes, mid rebase, merge or cherry-pick, or whose
# own configuration or hooks would run code are left alone. A rebase that stops on a conflict is aborted, restoring the checkout, and
# logged. Each checkout is synced at most once per throttle window.
# Usage:
#   repository-sync.sh [event name] [--force] [path...]

set -u

REPOSITORY_SYNC_SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
STATE_DIRECTORY="${XDG_CACHE_HOME:-$HOME/.cache}/herdr-repository-sync"
LOG_FILE="$STATE_DIRECTORY/sync.log"
LOCK_DIRECTORY="$STATE_DIRECTORY/lock"
THROTTLE_SECONDS=600
LOG_MAX_BYTES=200000

# Never block on a credential or host-key prompt, herdr has no terminal to answer it.
export GIT_TERMINAL_PROMPT=0
# Abort a stalled transfer instead of hanging, over SSH and HTTPS alike.
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2"
export GIT_HTTP_LOW_SPEED_LIMIT=1000
export GIT_HTTP_LOW_SPEED_TIME=30

force=false
detached=false
event="manual"
paths=()
for argument in "$@"; do
  case "$argument" in
    --force) force=true ;;
    --detached) detached=true ;;
    *)
      if [ -d "$argument" ]; then
        paths+=("$(cd "$argument" && pwd)")
      else
        event="$argument"
      fi
      ;;
  esac
done

# Return to herdr right away, fetching every repository can take a while.
if [ "$detached" = false ]; then
  nohup bash "$REPOSITORY_SYNC_SCRIPT_PATH" "$@" --detached >/dev/null 2>&1 &
  exit 0
fi

mkdir -p "$STATE_DIRECTORY"

log() {
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$event" "$1" >>"$LOG_FILE"
}

file_age_seconds() {
  echo $(($(date +%s) - $(stat -f %m "$1")))
}

# One pass at a time. The lock holds its owner's PID, a lock whose owner is gone
# belongs to a killed run and is taken over.
# A lock with no PID yet is still being created by another run, unless it is old.
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
  # Remove and recreate, so only one of several runs seeing a dead owner wins.
  rm -rf "$LOCK_DIRECTORY"
  mkdir "$LOCK_DIRECTORY" 2>/dev/null || return 1
  echo $$ >"$LOCK_DIRECTORY/pid"
}

release_lock() {
  if [ "$(cat "$LOCK_DIRECTORY/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$LOCK_DIRECTORY"
  fi
}

if ! take_lock; then
  log "skipped, another pass is running"
  exit 0
fi
trap release_lock EXIT

if [ -f "$LOG_FILE" ] && [ "$(stat -f %z "$LOG_FILE")" -gt "$LOG_MAX_BYTES" ]; then
  tail -n 500 "$LOG_FILE" >"$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

if [ ${#paths[@]} -eq 0 ]; then
  if ! pane_directories=$(herdr pane list 2>>"$LOG_FILE" | jq -r '.result.panes[].cwd // empty'); then
    log "could not list herdr panes"
    exit 1
  fi
  while IFS= read -r path; do
    [ -n "$path" ] && paths+=("$path")
  done < <(printf '%s\n' "$pane_directories" | sort -u)
fi

# A checkout's own configuration and hooks run code during `status`, `fetch` and
# `rebase`. A plain clone has neither, one copied or extracted from elsewhere can
# carry both, and this runs unattended in every pane, so such a checkout is left
# alone. `core.fsmonitor` set to `true` or `false` is the built-in monitor, not a
# command. Only the repository's own scopes count, `local` and `worktree`, the
# user's global signing program or credential helper is trusted.
# Usage:
#   repository_code_reason <checkout path>, prints why and succeeds when it would run code
repository_code_reason() {
  local checkout="$1" setting hooks_directory hook
  setting=$(git -C "$checkout" config --show-scope --includes --get-regexp '^(core\.(sshcommand|gitproxy|fsmonitor|hookspath|askpass)|remote\..*\.uploadpack|filter\..*\.(clean|smudge|process)|merge\..*\.driver|credential\.(.*\.)?helper|gpg\.(.*\.)?program|protocol\.(.*\.)?allow)$' 2>/dev/null | grep -E '^(local|worktree)[[:space:]]' | grep -viE '[[:space:]]core\.fsmonitor (true|false)$' | head -n 1)
  if [ -n "$setting" ]; then
    setting=$(printf '%s' "$setting" | cut -f2)
    echo "sets ${setting%% *}"
    return 0
  fi
  hooks_directory=$(git -C "$checkout" rev-parse --path-format=absolute --git-path hooks)
  for hook in pre-rebase post-rewrite post-checkout post-merge post-index-change reference-transaction pre-auto-gc; do
    if [ -x "$hooks_directory/$hook" ]; then
      echo "has a $hook hook"
      return 0
    fi
  done
  return 1
}

# Usage:
#   sync_checkout <checkout path> <throttle stamp file>
sync_checkout() {
  local checkout="$1"
  local stamp="$2"

  local branch
  branch=$(git -C "$checkout" symbolic-ref --quiet --short HEAD) || return
  case "$branch" in
    main | master) ;;
    *) return ;;
  esac

  if ! git -C "$checkout" remote get-url origin >/dev/null 2>&1; then
    return
  fi

  # Before `status` below, it already runs `core.fsmonitor`.
  local reason
  if reason=$(repository_code_reason "$checkout"); then
    log "skipped $branch, the repository $reason: $checkout"
    return
  fi

  # Unlike an interactive `gfrb`, nobody is there to resolve an autostash that
  # conflicts on re-apply, and an agent may be editing the files right now, so a
  # checkout with uncommitted changes is left alone.
  if [ -n "$(git -C "$checkout" status --porcelain --untracked-files=no)" ]; then
    log "skipped $branch, uncommitted changes: $checkout"
    return
  fi

  if ! git -C "$checkout" fetch origin --prune --quiet 2>>"$LOG_FILE"; then
    log "fetch failed: $checkout"
    return
  fi
  # Only a successful fetch starts the throttle window, a failed one retries on the next event.
  touch "$stamp"

  # Same base as `git_get_default_branch`, read from the local `origin/HEAD` instead of
  # asking the remote again.
  local base
  base=$(git -C "$checkout" symbolic-ref --quiet --short refs/remotes/origin/HEAD)
  if [ -z "$base" ]; then
    git -C "$checkout" remote set-head origin --auto >/dev/null 2>&1
    base=$(git -C "$checkout" symbolic-ref --quiet --short refs/remotes/origin/HEAD)
  fi
  if [ -z "$base" ]; then
    log "no default branch for origin: $checkout"
    return
  fi

  # The fetch can take a while, recheck the branch and leave a rebase, merge or
  # cherry-pick someone started meanwhile alone, aborting it would discard their work.
  if [ "$(git -C "$checkout" symbolic-ref --quiet --short HEAD)" != "$branch" ]; then
    return
  fi
  local state
  for state in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD; do
    if [ -e "$(git -C "$checkout" rev-parse --path-format=absolute --git-path "$state")" ]; then
      log "skipped $branch, $state in progress: $checkout"
      return
    fi
  done

  local before
  before=$(git -C "$checkout" rev-parse HEAD)
  # `gfrb` rebases interactively, the no-op editors accept the autosquashed todo list
  # and any `squash!` message as is, since nobody is there to edit them.
  if GIT_SEQUENCE_EDITOR=: GIT_EDITOR=: git -C "$checkout" rebase -i "refs/remotes/$base" --autosquash --autostash --quiet >>"$LOG_FILE" 2>&1; then
    if [ "$(git -C "$checkout" rev-parse HEAD)" != "$before" ]; then
      log "rebased $branch onto $base: $checkout"
    fi
  else
    # No rebase was in progress before, so one left behind now is this script's own.
    if [ -e "$(git -C "$checkout" rev-parse --path-format=absolute --git-path rebase-merge)" ]; then
      git -C "$checkout" rebase --abort >/dev/null 2>&1
    fi
    log "rebase of $branch onto $base failed, aborted: $checkout"
  fi
}

# Several panes in one checkout share its top level, sync it once.
seen=" "
for path in ${paths[@]+"${paths[@]}"}; do
  [ -d "$path" ] || continue
  checkout=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null) || continue
  case "$seen" in
    *" $checkout "*) continue ;;
  esac
  seen="$seen$checkout "

  stamp="$STATE_DIRECTORY/$(printf '%s' "$checkout" | shasum | cut -c1-16).stamp"
  if [ "$force" = false ] && [ -f "$stamp" ] && [ "$(file_age_seconds "$stamp")" -lt "$THROTTLE_SECONDS" ]; then
    continue
  fi

  sync_checkout "$checkout" "$stamp"
done
