#!/usr/bin/env bash
# The only write the `review-github-pr-watcher` skill is allowed unattended: one review with inline comments on one open pull request.
# Meant to be allowed in claude/settings.json by its path, that rule is not shipped and is added by hand, so the script validates every input itself and calls one fixed endpoint, never a caller supplied one.
#
# Usage: post-pr-review.sh <owner/repo> <pull request number> <head sha> <APPROVE|REQUEST_CHANGES|COMMENT> <body file> <comments file>
#   comments file: a JSON array of {"path": string, "line": number, "body": string}, can be empty

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
if [ ! -f "$body_file" ] || [ ! -f "$comments_file" ]; then
  echo "body or comments file missing" >&2
  exit 2
fi

if ! jq -e 'type == "array" and all(.[]; (keys - ["path", "line", "body"] | length == 0) and (.path | type == "string") and (.line | type == "number") and (.body | type == "string"))' "$comments_file" >/dev/null; then
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
  --rawfile body "$body_file" \
  --slurpfile comments "$comments_file" \
  '{commit_id: $commit_id, event: $event, body: $body, comments: $comments[0]}')"

printf '%s' "$payload" | gh api "repos/$repository/pulls/$number/reviews" --method POST --input - --jq .html_url
