#!/usr/bin/env bash
# The only write the `review-github-prs-watcher` skill is allowed unattended: one review with inline comments on one open pull request.
# Allowed in claude/settings.json by its path, so the script validates every input itself and calls one fixed endpoint, never a caller supplied one.
#
# Usage: post-pr-review.sh <owner/repo> <pull request number> <head sha> <APPROVE|REQUEST_CHANGES|COMMENT> <body file> <comments file>
#   comments file: a JSON array of {"path": string, "line": number, "body": string}, can be empty
#   body file, comments file: regular files the caller wrote in a temporary directory, nothing else is read for them

set -e

if [ $# -ne 6 ]; then
  echo "usage: post-pr-review.sh <owner/repo> <number> <head sha> <event> <body file> <comments file>" >&2
  exit 2
fi

repository="$1"
number="$2"
head_sha="$3"
event="$4"
body_file="$5"
comments_file="$6"

# Whole string matches, grep would check line by line and let a newline through.
if ! [[ $repository =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$ ]]; then
  echo "invalid repository: $repository" >&2
  exit 2
fi
case "$number" in
  '' | *[!0-9]*)
    echo "invalid pull request number: $number" >&2
    exit 2
    ;;
esac
if ! [[ $head_sha =~ ^[0-9a-f]{40}$ ]]; then
  echo "invalid head sha: $head_sha" >&2
  exit 2
fi
case "$event" in
  APPROVE | REQUEST_CHANGES | COMMENT) ;;
  *)
    echo "invalid event: $event" >&2
    exit 2
    ;;
esac
# This runs unattended on text a pull request author wrote, so an approval from the user's account is posted only for a pull request the detector claimed at this commit in the last two hours, `watch-review-requests.sh` writes the claim. Text in a pull request cannot get one approved that is not in the current review queue. The two hours must equal `CLAIM_SECONDS` in `watch-review-requests.sh`, which writes the claim, this script runs from `~/.config` without the repository, so the value is not shared. The key may end in `+epoch` for a reply.
if [ "$event" = APPROVE ]; then
  claimed_file="${XDG_CACHE_HOME:-$HOME/.cache}/review-github-prs-watcher/claimed"
  if ! awk -v key="$repository#$number@$head_sha" -v now="$(date +%s)" '($2 == key || index($2, key "+") == 1) && now - $1 < 7200 { found = 1 } END { exit !found }' "$claimed_file" 2>/dev/null; then
    echo "APPROVE only for a pull request the watcher claimed at $head_sha in the last two hours" >&2
    exit 1
  fi
fi
if [ ! -f "$body_file" ] || [ ! -f "$comments_file" ]; then
  echo "body or comments file missing" >&2
  exit 2
fi
# The script is allowed by path and reads these files for the caller, so a path the caller was talked into, such as a credential, must not be posted, the deny rules on `Read` never see it. Same rule as `post-thread-reply.sh`.
# The roots are fixed, `TMPDIR` is the caller's and could point at the home folder. Each file is a regular file with one link, a hard link to a credential would pass the path check, and it is read once, right here, so a swap after the check posts nothing else.
user_temporary_root="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"
if [ -n "$user_temporary_root" ]; then
  user_temporary_root="$(cd "$user_temporary_root" && pwd -P)"
fi
for file in "$body_file" "$comments_file"; do
  if [ -L "$file" ]; then
    echo "body and comments files must not be symlinks: $file" >&2
    exit 2
  fi
  file_path="$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file")"
  case "$file_path" in
    /tmp/* | /private/tmp/*) ;;
    *)
      if [ -z "$user_temporary_root" ] || [[ $file_path != "$user_temporary_root"/* ]]; then
        echo "body and comments files must be in a temporary directory: $file_path" >&2
        exit 2
      fi
      ;;
  esac
  if [ -z "$(find "$file" -prune -links 1)" ]; then
    echo "body and comments files must have one link: $file" >&2
    exit 2
  fi
done
body="$(
  cat -- "$body_file"
  printf x
)"
body="${body%x}"
comments="$(cat -- "$comments_file")"

if ! jq -e 'type == "array" and all(.[]; (keys - ["path", "line", "body"] | length == 0) and (.path | type == "string") and (.line | type == "number") and (.body | type == "string"))' <<<"$comments" >/dev/null; then
  echo "comments file must be an array of path, line and body objects" >&2
  exit 2
fi

# Post only on a pull request that is still open at the reviewed commit, a push since then needs a fresh review.
current_state="$(gh api "repos/$repository/pulls/$number" --jq '"\(.state) \(.draft) \(.head.sha)"')"
if [ "$current_state" != "open false $head_sha" ]; then
  echo "pull request is not open and ready at $head_sha, now: $current_state" >&2
  exit 1
fi

# One review per head commit, whatever the detector's seen file says, a restarted watcher or a second one must not post twice.
# The reviews are read first, so a failed read stops the script under `set -e`, inside an `if` it would read as no review. The pages are slurped, jq would otherwise answer per page and `-e` keeps only the last.
viewer="$(gh api user --jq .login)"
reviews="$(gh api --paginate "repos/$repository/pulls/$number/reviews?per_page=100")"
if jq -s -e --arg viewer "$viewer" --arg commit "$head_sha" 'add // [] | any(.[]; .user.login == $viewer and .commit_id == $commit)' <<<"$reviews" >/dev/null; then
  echo "already reviewed at $head_sha" >&2
  exit 1
fi

payload="$(jq -n \
  --arg commit_id "$head_sha" \
  --arg event "$event" \
  --arg body "$body" \
  --argjson comments "$comments" \
  '{commit_id: $commit_id, event: $event, body: $body, comments: $comments}')"

printf '%s' "$payload" | gh api "repos/$repository/pulls/$number/reviews" --method POST --input - --jq .html_url
