#!/bin/bash

# Checks that `webfetch-guard.sh` and the `opencode` guard plugin block and
# allow the same URLs, including userinfo and trailing-dot hosts that used to
# slip past the shell hook.

set -e

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOKS_DIRECTORY="$TESTS_SCRIPT_DIRECTORY/../.config/agentic/hooks"

temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT

# The plugin is an ES module, older `node` only parses `export` in a `.mjs` file.
cp "$HOOKS_DIRECTORY/opencode-guards.js" "$temporary_directory/opencode-guards.mjs"

failures=0

check() {
  local url="$1" expected="$2" shell_result node_result

  shell_result=$(jq -n --arg url "$url" '{tool_name: "WebFetch", tool_input: {url: $url}}' | bash "$HOOKS_DIRECTORY/webfetch-guard.sh" | jq -r '.hookSpecificOutput.permissionDecision')
  # The hook prints nothing when it lets a fetch through.
  shell_result=${shell_result:-allow}

  node_result=$(node --input-type=module -e "
    const { AgenticGuardsPlugin } = await import(process.argv[1]);
    const hooks = await AgenticGuardsPlugin();
    try {
      await hooks['tool.execute.before']({ tool: 'webfetch' }, { args: { url: process.argv[2] } });
      console.log('allow');
    } catch {
      console.log('deny');
    }
  " "$temporary_directory/opencode-guards.mjs" "$url")

  if [ "$shell_result" != "$expected" ] || [ "$node_result" != "$expected" ]; then
    echo "FAIL: '$url' expected $expected, shell hook gave $shell_result, opencode plugin gave $node_result"
    failures=$((failures + 1))
  fi
}

check "https://github.com/owner/repository" deny
check "https://api.github.com:443/repos" deny
check "https://user@github.com/owner/repository" deny
check "https://user:password@github.com/owner/repository" deny
check "https://github.com./owner/repository" deny
check 'https://github.com\@example.com/owner' deny
check "https://github%2ecom/owner/repository" deny
check "https://phabricator.example.com/T1" deny
check "https://grafana.example.com/explore" deny
check "https://sentry.io/issues/1" deny
check "https://blog.example.com/learn-grafana" allow
check "https://github.com.example.com/owner" allow
check "https://notgithub.com/owner" allow

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: webfetch-guard"
