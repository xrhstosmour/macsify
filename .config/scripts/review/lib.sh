#!/usr/bin/env bash
# Shared checks of the review and resolve watcher scripts, sourced by the scripts next to it.
# They run from ~/.config without the macsify repository, so `helpers/` is not there for them.
# Every check exits the calling script on a bad value, the scripts are allowed by path in claude/settings.json and must refuse anything they were not built for.

# Whole string matches, grep would check line by line and let a newline through.
require_repository() {
  if ! [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$ ]]; then
    echo "invalid repository: $1" >&2
    exit 2
  fi
}

require_number() {
  case "$2" in
    '' | *[!0-9]*)
      echo "invalid $1: $2" >&2
      exit 2
      ;;
  esac
}

require_sha() {
  if ! [[ $2 =~ ^[0-9a-f]{40}$ ]]; then
    echo "invalid $1: $2" >&2
    exit 2
  fi
}

# A branch name git accepts, checked as a full ref so `@{-1}` style shorthands are not expanded, and never starting with `-`, which git would read as an option.
require_branch() {
  if [[ $2 == -* ]] || ! git check-ref-format "refs/heads/$2"; then
    echo "invalid $1: $2" >&2
    exit 2
  fi
}

# A script allowed by path reads this file for the caller, so a path the caller was talked into, such as a credential, must not be posted, the deny rules on `Read` never see it.
# The roots are fixed, `TMPDIR` is the caller's and could point at the home folder. The file has one link, a hard link to a credential would pass the path check. The caller reads it once, right after, so a swap after the check posts nothing else.
require_temporary_file() {
  local label="$1" file="$2" user_temporary_root file_path
  if [ -L "$file" ] || [ ! -s "$file" ]; then
    echo "$label missing, empty or a symlink" >&2
    exit 2
  fi
  user_temporary_root="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"
  if [ -n "$user_temporary_root" ]; then
    user_temporary_root="$(cd "$user_temporary_root" && pwd -P)"
  fi
  file_path="$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file")"
  case "$file_path" in
    /tmp/* | /private/tmp/*) ;;
    *)
      if [ -z "$user_temporary_root" ] || [[ $file_path != "$user_temporary_root"/* ]]; then
        echo "$label must be in a temporary directory: $file_path" >&2
        exit 2
      fi
      ;;
  esac
  if [ -z "$(find "$file" -prune -links 1)" ]; then
    echo "$label must have one link: $file" >&2
    exit 2
  fi
}

# Reads a checked body file into `body`, the trailing newlines kept, and refuses one GitHub would reject, above 65536 characters.
read_body_file() {
  require_temporary_file "body file" "$1"
  body="$(
    cat -- "$1"
    printf x
  )"
  body="${body%x}"
  if [ "${#body}" -gt 65000 ]; then
    echo "body file is too long" >&2
    exit 2
  fi
}

# Prints the checkout of the repository under the developer directory, found by its `origin` whatever its folder is called, and clones it only when none matches.
# Never into a folder that belongs to another repository with the same name.
find_checkout() {
  local developer="$1" repository="$2" candidate url checkout
  for candidate in "$developer"/*/; do
    candidate="${candidate%/}"
    [ -e "$candidate/.git" ] || continue
    url="$(git -C "$candidate" config --get remote.origin.url)" || continue
    case "${url%.git}" in
      *"github.com:$repository" | *"github.com/$repository")
        echo "$candidate"
        return 0
        ;;
    esac
  done
  checkout="$developer/${repository##*/}"
  if [ -e "$checkout" ]; then
    checkout="$developer/${repository%%/*}-${repository##*/}"
  fi
  gh repo clone "$repository" "$checkout" >&2
  echo "$checkout"
}

# Fails unless the `.git` of the worktree is a plain file pointing into the `worktrees` folder of the checkout's git directory.
# A worktree the caller may edit could otherwise point git at a folder with a planted configuration, whose `core.fsmonitor` runs a command on the next `git status`, and whose remote takes the push.
require_worktree_of() {
  local worktree="$1" checkout="$2" pointer git_directory worktrees
  if [ -L "$worktree/.git" ] || [ ! -f "$worktree/.git" ]; then
    echo "$worktree is not a worktree of $checkout" >&2
    exit 1
  fi
  pointer="$(cat "$worktree/.git")"
  git_directory="${pointer#gitdir: }"
  case "$git_directory" in
    /*) ;;
    *) git_directory="$worktree/$git_directory" ;;
  esac
  worktrees="$(cd "$checkout/.git/worktrees" 2>/dev/null && pwd -P)" || worktrees=""
  if [ "$git_directory" = "$pointer" ] || [[ $pointer == *$'\n'* ]] || [ -z "$worktrees" ] || ! git_directory="$(cd "$git_directory" 2>/dev/null && pwd -P)" ||
    [[ $git_directory != "$worktrees"/* ]] || [[ ${git_directory#"$worktrees"/} == */* ]]; then
    echo "$worktree is not a worktree of $checkout" >&2
    exit 1
  fi
}

# Takes a lock named `<name>.lock` in the git directory of the checkout and frees it when the script exits, so two runs never fetch or move the same worktree at once.
# A lock older than ten minutes is left over from a run that died. `REVIEW_LOCK_ATTEMPTS` replaces the 120 seconds it is waited for, for the tests.
lock_checkout() {
  local attempts=0
  repository_lock="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)/$2.lock"
  until mkdir "$repository_lock" 2>/dev/null; do
    if [ -n "$(find "$repository_lock" -maxdepth 0 -mmin +10)" ]; then
      rmdir "$repository_lock"
      continue
    fi
    attempts=$((attempts + 1))
    if [ "$attempts" -gt "${REVIEW_LOCK_ATTEMPTS:-120}" ]; then
      echo "another run holds $repository_lock" >&2
      exit 1
    fi
    sleep 1
  done
  trap 'rmdir "$repository_lock"' EXIT
}
