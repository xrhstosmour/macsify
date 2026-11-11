#!/usr/bin/env bash
# Shared checks of the review and green watcher scripts, sourced by the scripts next to it.
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

# A file name directly in `.github/workflows`, nothing the caller could turn into another path or endpoint.
require_workflow_file() {
  if ! [[ $1 =~ ^[A-Za-z0-9_][A-Za-z0-9._-]{0,99}\.ya?ml$ ]]; then
    echo "invalid workflow file: $1" >&2
    exit 2
  fi
}

# The caller reads the workflow and picks it as one that only tests, this is the backstop: a workflow naming a deploy, a release, a publish, a promotion, production, a migration or a GitHub environment, which is how a job gets production secrets, is never triggered unattended, whatever the caller decided.
# A comment line never runs and an `if:` only picks whether a step runs, so both are left out, an `if:` skipping a step on a deploy branch is not a deploy. It cannot see a deploy that names none of the words, which is why the caller only picks workflows that test.
deploy_lines() {
  grep -vE '^[[:space:]]*(#|(-[[:space:]]+)?if:)' <<<"$1" | grep -iE 'deploy|release|publish|promot|production|migrat|environment:|--prod|terraform apply|vercel'
}

# The workflow trees you approved, written only by `green-trust.sh`, which `claude/settings.json` asks you about each time.
# One `<owner/repo> .github/workflows/<file> <fingerprint>` per line, any other line or a symlink fails closed, a file nobody can read must not approve anything.
trust_file="$HOME/.config/green-github-prs-watcher/trusted-workflows"
# Set only by `require_test_only_tree` once the trust file approves the tree at `trust_ref`, never from the environment.
trusted_fingerprint=""
trust_line_pattern='^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100} \.github/workflows/[A-Za-z0-9_][A-Za-z0-9._-]{0,99}\.ya?ml [0-9a-f]{64}$'

require_trust_file() {
  if [ -L "$trust_file" ] || [ ! -f "$trust_file" ] || grep -qvE "$trust_line_pattern" "$trust_file"; then
    echo "$trust_file is not a plain file of trust lines, fix or remove it" >&2
    exit 1
  fi
}

# Collects the workflow or action text and every workflow or local action it calls with `uses:` into `tree_paths` and `tree_contents`, read at the ref with `read_repository_file <ref> <path>`, which the caller defines and which fails when it cannot read the file. The deploy scan and the trust fingerprint read this one collection, so a file can never be scanned without being fingerprinted.
# A reusable workflow of another repository cannot be read here, so it is refused, trusted or not. A nesting deeper than GitHub's own limit is refused too, which also ends a loop.
collect_tree() {
  local ref="$1" path="$2" content="$3" depth="${4:-0}" callees callee callee_content
  tree_paths+=("$path")
  tree_contents+=("$content")
  callees="$(grep -oE "(^|[[:space:]{,])uses:[[:space:]]*[\"']?[^\"'[:space:],}#]+" <<<"$content" | sed -E "s/^.*uses:[[:space:]]*[\"']?//")"
  while IFS= read -r callee; do
    case "$callee" in
      '') continue ;;
      ./*) ;;
      */.github/workflows/*)
        echo "$path calls a reusable workflow of another repository, trigger it by hand" >&2
        exit 1
        ;;
      *) continue ;;
    esac
    if [ "$depth" -ge 10 ] || ! [[ $callee =~ ^\./[A-Za-z0-9._][A-Za-z0-9._/-]*$ ]] || [[ $callee/ == */../* ]]; then
      echo "$path calls $callee, which cannot be checked, trigger it by hand" >&2
      exit 1
    fi
    callee="${callee#./}"
    callee="${callee%/}"
    if [[ $callee == *.yml || $callee == *.yaml ]]; then
      callee_content="$(read_repository_file "$ref" "$callee")" || exit 1
    elif callee_content="$(read_repository_file "$ref" "$callee/action.yml" 2>/dev/null)"; then
      callee="$callee/action.yml"
    else
      callee="$callee/action.yaml"
      callee_content="$(read_repository_file "$ref" "$callee")" || exit 1
    fi
    collect_tree "$ref" "$callee" "$callee_content" $((depth + 1))
  done <<<"$callees"
}

# A hash over each path of the collected tree and the git object id of its text, so a change to any file of the tree changes it. No filter runs on the text.
tree_fingerprint() {
  local index
  for index in "${!tree_paths[@]}"; do
    printf '%s %s\n' "${tree_paths[$index]}" "$(printf '%s' "${tree_contents[$index]}" | git hash-object --no-filters --stdin)"
  done | LC_ALL=C sort -u | shasum -a 256 | cut -d ' ' -f 1
}

# Fails with exit 5 when the workflow at the path, or a workflow or local action it calls, mentions a deploy.
# Only the workflow the caller was asked to run, `trust_workflow`, read at the commit it runs at, `trust_ref`, can be trusted, for `trust_repository`, all set by the caller from its own checks, never from an argument. Its exit 5 prints the `green-trust.sh` command for that exact tree, run only after you read the lines it prints. Any other workflow the trigger starts or chains is never trusted, approving the tests must not approve a deploy that runs next to them. The same file read at another ref, the default branch for a `workflow_run`, passes only as the very tree approved at `trust_ref`, which the callers check first, so two versions never take turns replacing each other's line.
require_test_only_tree() {
  local ref="$1" path="$2" content="$3" index matches="" fingerprint
  tree_paths=()
  tree_contents=()
  collect_tree "$ref" "$path" "$content"
  for index in "${!tree_paths[@]}"; do
    if deploy_lines "${tree_contents[$index]}" >/dev/null; then
      matches+="$(deploy_lines "${tree_contents[$index]}" | sed "s|^|  ${tree_paths[$index]}: |")"$'\n'
    fi
  done
  [ -z "$matches" ] && return 0
  fingerprint="$(tree_fingerprint)"
  if [ -z "${trust_repository:-}" ] || [ "$path" != "${trust_workflow:-}" ] ||
    { [ "$ref" != "${trust_ref:-}" ] && [ "$fingerprint" != "${trusted_fingerprint:-}" ]; }; then
    printf '%s mentions a deploy, release, publish, promotion, production, migration or environment, trigger it by hand:\n%s' "$path" "$matches" >&2
    exit 5
  fi
  [ "$ref" != "$trust_ref" ] && return 0
  if [ -e "$trust_file" ] || [ -L "$trust_file" ]; then
    require_trust_file
    if grep -qxF -- "$trust_repository $path $fingerprint" "$trust_file"; then
      trusted_fingerprint="$fingerprint"
      return 0
    fi
  fi
  printf '%s mentions a deploy, release, publish, promotion, production, migration or environment, trigger it by hand or trust it.\n' "$path" >&2
  printf 'Its files:\n' >&2
  printf '  %s\n' "${tree_paths[@]}" >&2
  printf 'The lines the scan matched:\n%s' "$matches" >&2
  printf 'To trust this exact tree:\n  ~/.config/scripts/review/green-trust.sh %s %s %s\n' "$trust_repository" "$path" "$fingerprint" >&2
  exit 5
}

# Fails when a workflow of `.github/workflows` at the ref that the trigger also starts could deploy: one a push to the branch starts, when a branch is given, or one a `workflow_run` or `create` chains.
# The caller defines `read_repository_file` as above and `list_workflows <ref>`, which prints the file names of `.github/workflows` at the ref, one per line, and fails when it cannot.
require_no_deploy_started() {
  local ref="$1" branch="$2" files file content
  files="$(list_workflows "$ref")"
  while IFS= read -r file; do
    case "$file" in
      *.yml | *.yaml) ;;
      *) continue ;;
    esac
    require_workflow_file "$file"
    content="$(read_repository_file "$ref" ".github/workflows/$file")"
    if { [ -n "$branch" ] && starts_on_push "$branch" "$content"; } || starts_after_trigger "$content"; then
      require_test_only_tree "$ref" ".github/workflows/$file" "$content"
    fi
  done <<<"$files"
}

# Prints the top level `on:` block of the workflow text, so a `push:` or `branches:` key of a step is never read as a trigger. YAML reads a bare `on` as true, so it may be quoted.
trigger_block() {
  local line inside=0
  while IFS= read -r line; do
    if [[ $line =~ ^[\"\']?on[\"\']?: ]]; then
      inside=1
    elif [[ $line =~ ^[^[:space:]#] ]]; then
      inside=0
    fi
    if [ "$inside" = 1 ]; then
      printf '%s\n' "$line"
    fi
  done <<<"$1"
}

# Prints the block style `branches:` items of the `push` trigger in the workflow text, one per line, never `paths:` or `branches-ignore:` items, or the `branches:` of another trigger. A flow style list `[a, b]` prints nothing, so it fails visibly instead of being guessed. An item it cannot read prints `**`, a push to every branch, so it is never dropped.
push_branch_patterns() {
  local line event="" in_branches=0
  local item="^[[:space:]]*-[[:space:]]*[\"']?([^\"'[:space:]]+)[\"']?[[:space:]]*\$"
  while IFS= read -r line; do
    # A trailing comment, a branch name never holds a space.
    line="${line%%[[:space:]]#*}"
    if [[ $line =~ ^[[:space:]]*(push|pull_request|pull_request_target|merge_group|workflow_run|workflow_dispatch|workflow_call|schedule|release|create|delete):[[:space:]]*$ ]]; then
      event="${BASH_REMATCH[1]}"
      in_branches=0
    elif [[ $line =~ ^[[:space:]]*branches:[[:space:]]*$ ]]; then
      in_branches=1
    elif [ "$in_branches" = 1 ] && [[ $line =~ $item ]]; then
      if [ "$event" = push ]; then
        echo "${BASH_REMATCH[1]}"
      fi
    elif [ "$in_branches" = 1 ] && [ "$event" = push ] && [[ $line =~ ^[[:space:]]*- ]]; then
      echo "**"
    elif ! [[ $line =~ ^[[:space:]]*(#.*)?$ ]]; then
      in_branches=0
    fi
  done < <(trigger_block "$1")
}

# Whether the workflow text has a YAML anchor `&name`, alias `*name` or merge key `<<:`, which can move a trigger where the line readers below do not look, so such a workflow always counts as started. A shell glob like `*tmp` also matches, which errs the same way.
has_yaml_references() {
  grep -qE '(^|[][[:space:]:,{-])[&*][A-Za-z0-9_-]|<<:' <<<"$1"
}

# Whether a push to the branch starts the workflow. A `push` trigger without `branches:` runs on every branch, and a `branches-ignore:` is read as no filter, so a doubt counts as a start. Bash patterns let `*` cross a slash, which also errs towards a start, and a pattern with `?`, `+`, `[` or a `!` negation, which GitHub reads differently, counts as a start.
starts_on_push() {
  local branch="$1" content="$2" pattern patterns
  has_yaml_references "$content" && return 0
  patterns="$(push_branch_patterns "$content")"
  if [ -z "$patterns" ]; then
    trigger_block "$content" | grep -qE '^[[:space:]]+push:|^[^[:space:]]+:.*[^a-z_]push([^a-z_]|$)'
    return
  fi
  while IFS= read -r pattern; do
    [[ $pattern == *[?+[]* || $pattern == !* ]] && return 0
    # shellcheck disable=SC2053
    [[ $branch == $pattern ]] && return 0
  done <<<"$patterns"
  return 1
}

# Whether the workflow can start from another trigger: a `workflow_run` after any other workflow, or a `create` when a branch is made. A trigger push or a dispatch may set either off, so any such workflow counts, without reading which workflows it waits for.
starts_after_trigger() {
  has_yaml_references "$1" && return 0
  trigger_block "$1" | grep -qE '^[[:space:]]+(workflow_run|create):|^[^[:space:]]+:.*[^a-z_](workflow_run|create)([^a-z_]|$)'
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

# Takes the lock directory and frees it when the script exits, a subshell frees it when the subshell ends.
# A lock older than ten minutes is left over from a run that died. `REVIEW_LOCK_ATTEMPTS` replaces the 120 seconds it is waited for, for the tests.
lock_directory() {
  local attempts=0
  held_lock="$1"
  until mkdir "$held_lock" 2>/dev/null; do
    # The holder can free it between the `mkdir` and this check.
    if [ -n "$(find "$held_lock" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
      # Another waiter can remove it first.
      rmdir "$held_lock" 2>/dev/null || true
      continue
    fi
    attempts=$((attempts + 1))
    if [ "$attempts" -gt "${REVIEW_LOCK_ATTEMPTS:-120}" ]; then
      echo "another run holds $held_lock" >&2
      exit 1
    fi
    sleep 1
  done
  trap 'rmdir "$held_lock"' EXIT
}

# Takes a lock named `<name>.lock` in the git directory of the checkout, so two runs never fetch or move the same worktree at once.
lock_checkout() {
  lock_directory "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)/$2.lock"
}

# Takes the lock of a watcher's state files. The detector rewrites a file to keep its latest entries while `--mark` and `green-git.sh` append to it from other processes, a line appended to the file it is replacing would be lost.
lock_state() {
  mkdir -p "$1"
  lock_directory "$1/state.lock"
}
