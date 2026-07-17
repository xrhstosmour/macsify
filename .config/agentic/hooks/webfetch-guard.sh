#!/bin/bash
# Blocks WebFetch on self-hosted Phabricator/Grafana hosts; domain: rules can't express an arbitrary org hostname.
input=$(cat)
[ "$(echo "$input" | jq -r '.tool_name // empty')" = "WebFetch" ] || exit 0
url=$(echo "$input" | jq -r '.tool_input.url // empty')
if echo "$url" | grep -qiE 'phabricator\.'; then
  reason="Use the Conduit API per ~/.config/agentic/tools/phabricator.md, not WebFetch."
elif echo "$url" | grep -qiE 'grafana\.'; then
  reason="Use logcli per ~/.config/agentic/tools/grafana.md, not WebFetch."
else
  exit 0
fi
jq -n --arg reason "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
