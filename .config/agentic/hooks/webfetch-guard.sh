#!/bin/bash
# Blocks WebFetch on hosts that have a dedicated CLI/MCP/skill instead. github.com/sentry.io also sit in claude/settings.json's permissions.deny as a defense-in-depth fallback; self-hosted Phabricator/Grafana hostnames can't be expressed as a static domain rule, so those rely on this hook alone.
input=$(cat)
[ "$(echo "$input" | jq -r '.tool_name // empty')" = "WebFetch" ] || exit 0
url=$(echo "$input" | jq -r '.tool_input.url // empty')
# Match against the host only, not the full URL, so a path/query segment that
# happens to contain one of these words (e.g. blog.example.com/learn-grafana)
# isn't mistaken for the real host. Userinfo (`user@`) and a trailing root dot
# are stripped too, `https://u@github.com./` still names `github.com`. A `\` is
# read as `/` and the host is percent-decoded, as a browser's URL parser does,
# so `github.com\@x` and `github%2ecom` name `github.com` here too.
host=$(echo "${url//\\//}" | sed -E 's#^[a-zA-Z]+://##; s#[/?#].*##; s#^.*@##; s#:[0-9]+$##')
host=$(printf '%b' "${host//%/\\x}")
host="${host%.}"
if echo "$host" | grep -qiE '(^|\.)github\.com$'; then
  reason="Use the gh CLI per the read-github-pr/read-github-issue/read-github-files/manage-github-pr/manage-github-issue skills, not WebFetch."
elif echo "$host" | grep -qiE '(^|\.)phabricator\.'; then
  reason="Use the Phabricator MCP tools per the read-phabricator-task skill, not WebFetch."
elif echo "$host" | grep -qiE '(^|\.)sentry\.io$'; then
  reason="Use the Sentry MCP tools per the read-sentry-issue skill, not WebFetch."
elif echo "$host" | grep -qiE '(^|\.)grafana\.'; then
  reason="Use logcli per the search-grafana-logs skill, not WebFetch."
else
  exit 0
fi
jq -n --arg reason "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
