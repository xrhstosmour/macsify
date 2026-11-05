#!/usr/bin/env bash
# The second write the `review-github-pr-watcher` skill is allowed unattended: one reply in a review thread you took part in, for a `reply` line of the detector.
# Allowed in claude/settings.json by its path, so the script validates every input itself and calls one fixed endpoint, never a caller supplied one.
#
# Usage: post-thread-reply.sh <owner/repo> <pull request number> <comment id> <body file>
#   comment id: the newest comment of the thread, written by a person of the organization or a collaborator other than you, never a bot
#   body file: a regular file the caller wrote in a temporary directory, nothing else is read for it
# Prints the URL of the reply.

set -e

if [ $# -ne 4 ]; then
  echo "usage: post-thread-reply.sh <owner/repo> <number> <comment id> <body file>" >&2
  exit 2
fi

repository="$1"
number="$2"
comment_id="$3"
body_file="$4"

# Whole string matches, grep would check line by line and let a newline through.
if ! [[ $repository =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$ ]]; then
  echo "invalid repository: $repository" >&2
  exit 2
fi
for value in "$number" "$comment_id"; do
  case "$value" in
    '' | *[!0-9]*)
      echo "invalid number: $value" >&2
      exit 2
      ;;
  esac
done
if [ -L "$body_file" ] || [ ! -s "$body_file" ]; then
  echo "body file missing, empty or a symlink" >&2
  exit 2
fi
# The script is allowed by path and reads this file for the caller, so a path the caller was talked into, such as a credential, must not be posted, the deny rules on `Read` never see it.
# The roots are fixed, `TMPDIR` is the caller's and could point at the home folder. The file has one link, a hard link to a credential would pass the path check, and it is read once, right here, so a swap after the check posts nothing else.
user_temporary_root="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"
if [ -n "$user_temporary_root" ]; then
  user_temporary_root="$(cd "$user_temporary_root" && pwd -P)"
fi
body_path="$(cd "$(dirname "$body_file")" && pwd -P)/$(basename "$body_file")"
case "$body_path" in
  /tmp/* | /private/tmp/*) ;;
  *)
    if [ -z "$user_temporary_root" ] || [[ $body_path != "$user_temporary_root"/* ]]; then
      echo "body file must be in a temporary directory: $body_path" >&2
      exit 2
    fi
    ;;
esac
if [ -z "$(find "$body_file" -prune -links 1)" ]; then
  echo "body file must have one link: $body_file" >&2
  exit 2
fi
body="$(
  cat -- "$body_file"
  printf x
)"
body="${body%x}"
# GitHub rejects a comment above 65536 characters, stop before the call.
if [ "${#body}" -gt 65000 ]; then
  echo "body file is too long" >&2
  exit 2
fi

current_state="$(gh api "repos/$repository/pulls/$number" --jq '"\(.state) \(.draft)"')"
if [ "$current_state" != "open false" ]; then
  echo "pull request is not open and ready, now: $current_state" >&2
  exit 1
fi

# Reply only to the newest comment of a thread you took part in, written by a person of the organization or a collaborator, and at most four times a day in one thread, so two watchers never answer each other for ever. The replies endpoint takes the first comment of the thread, so that is the id it is sent to.
# The comments are read first, so a failed read stops the script under `set -e`. The pages are slurped, jq would otherwise answer per page.
viewer="$(gh api user --jq .login)"
comments="$(gh api --paginate "repos/$repository/pulls/$number/comments?per_page=100")"
root="$(jq -s -e -r --arg viewer "$viewer" --argjson target "$comment_id" '
  (add // []) as $all
  | first($all[] | select(.id == $target)) as $comment
  | ($comment.in_reply_to_id // $comment.id) as $root
  | [$all[] | select(.id == $root or .in_reply_to_id == $root)] as $thread
  | select($comment.user.login != $viewer and $comment.user.type != "Bot"
      and ($comment.author_association | IN("OWNER", "MEMBER", "COLLABORATOR"))
      and any($thread[]; .user.login == $viewer)
      and ([$thread[] | select(.user.login == $viewer and (.created_at | fromdateiso8601) > (now - 86400))] | length) < 4
      and $comment.id == ($thread | max_by(.id) | .id))
  | $root' <<<"$comments")" || {
  echo "comment $comment_id is not the newest of a thread you took part in, by a member or collaborator, or the thread reached four replies today" >&2
  exit 1
}

jq -n --arg body "$body" '{body: $body}' | gh api "repos/$repository/pulls/$number/comments/$root/replies" --method POST --input - --jq .html_url
