#!/bin/bash

# Checks that the permission rules in `claude/settings.json` keep the entries the
# rest of the setup relies on. It reads the file only, it does not run Claude
# Code's matcher, so it catches a rule being deleted or widened, not one that
# is written wrong.

set -e

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SETTINGS_FILE="$TESTS_SCRIPT_DIRECTORY/../claude/settings.json"

failures=0

# Usage:
#   expect_rule <deny|ask|allow> <rule> <present|absent>
expect_rule() {
  local list="$1" rule="$2" expected="$3" actual="absent"
  if jq -e --arg list "$list" --arg rule "$rule" '.permissions[$list] | index($rule) != null' "$SETTINGS_FILE" >/dev/null; then
    actual="present"
  fi
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: '$rule' in permissions.$list should be $expected"
    failures=$((failures + 1))
  fi
}

expect_rule deny 'Bash(sudo *)' present
expect_rule deny 'Bash(git push *--force* main)' present
expect_rule deny 'Bash(git push --mirror *)' present
expect_rule ask 'Bash(git branch -D *)' present
expect_rule ask 'Bash(git reset --hard *)' present
# The force-with-lease allow only holds while these ask rules cover the other spellings of the default branch.
expect_rule ask 'Bash(git push*+*main*)' present
expect_rule ask 'Bash(git push*refs/heads/main*)' present
# The slot agents of both watchers read their steps unprompted.
expect_rule allow 'Read(~/.config/agentic/skills/green-github-prs-watcher/references/slot-run.md)' present
expect_rule allow 'Read(~/.config/agentic/skills/review-github-prs-watcher/references/slot-run.md)' present
# Both dispatchers take and free their agent slots unprompted.
expect_rule allow 'Bash(~/.config/scripts/review/agent-slots.sh *)' present
# The review watcher reads its slot worktrees unprompted.
expect_rule allow 'Read(~/Developer/worktrees/*/reviews-2/**)' present
expect_rule allow 'Read(~/Developer/worktrees/*/reviews-*/**)' absent
# Only the three slots are editable unprompted, not a worktree of yours whose name starts the same.
expect_rule allow 'Edit(~/Developer/worktrees/*/resolves-3/**)' present
expect_rule allow 'Edit(~/Developer/worktrees/*/resolves-*/**)' absent
# The resolves slot worktrees are editable, their `.git` pointer must not be, `green-git.sh` checks it too.
expect_rule deny 'Edit(~/Developer/worktrees/*/resolves-*/.git)' present
# Nor a `.git` in a folder of one, which would turn that folder into a submodule with a configuration of the caller.
expect_rule deny 'Edit(~/Developer/worktrees/*/resolves-*/**/.git)' present
# The green watcher cuts a failed check log piped into `tail -n 200`, only that exact form is allowed, a file argument would read any file unprompted.
expect_rule allow 'Bash(tail -n 200)' present
expect_rule allow 'Bash(tail -n *)' absent
# Port scanning is not something to allow unprompted.
expect_rule allow 'Bash(nc -z *)' absent
# The green watcher searches past sessions through `green-search.sh`, scoped to the checkout of the pull request, never a `Read` of every transcript.
expect_rule allow 'Bash(~/.config/scripts/review/green-search.sh *)' present
expect_rule allow 'Read(~/.claude/projects/*-Developer-*/**)' absent
expect_rule allow 'Read(~/.claude/projects/**)' absent
# Only the read-only `qmd` commands, never a bare `qmd *` that would allow its writes too.
expect_rule allow 'Bash(qmd search *)' present
expect_rule allow 'Bash(qmd query *)' present
expect_rule allow 'Bash(qmd get *)' present
expect_rule allow 'Bash(qmd *)' absent
# Search endpoints are read-only, the ask rules on the write flags must keep winning over the `gh api` allows.
expect_rule allow 'Bash(gh api search/*)' present
expect_rule ask 'Bash(gh api *-X*)' present
expect_rule ask 'Bash(gh api *-f*)' present
# Trusting a workflow that mentions a deploy is your call, `green-trust.sh` is a script of its own on no allow list so every run asks, and the trust file is never written outside it.
# A Bash rule matches the command text, so the ask rule takes any spelling of the path, `~`, `$HOME` or absolute.
expect_rule ask 'Bash(*green-trust.sh*)' present
expect_rule allow 'Bash(~/.config/scripts/review/green-trust.sh *)' absent
expect_rule deny 'Edit(~/.config/green-github-prs-watcher/**)' present
expect_rule deny 'Bash(*trusted-workflows*)' present
# Nor writes the state that tells its own cycles from yours, a deleted line would resume a paused pull request, `seen` stays editable for a recheck.
expect_rule deny 'Edit(~/.cache/green-github-prs-watcher/claimed)' present
expect_rule deny 'Edit(~/.cache/green-github-prs-watcher/pushed)' present
expect_rule deny 'Bash(*green-github-prs-watcher/claimed*)' present
expect_rule deny 'Bash(*green-github-prs-watcher/pushed*)' present
# A command run with another cache would push without a record or detect from empty state. The rules match command text only, defense in depth next to the skill's rule.
expect_rule deny 'Bash(*XDG_CACHE_HOME=*)' present
# `rg --pre` runs any command, so `rg` stays prompted.
expect_rule allow 'Bash(rg *)' absent
READ_TOOLS_FILE="$TESTS_SCRIPT_DIRECTORY/../claude/mcp-read-tools.json"
# Raw SQL can return any row or write, and the other tools return customer data, rows, log lines or events, so they stay prompted on every MCP server setup allows the read tools under.
for tool in metabase-mcp_execute_sql metabase-mcp_construct_native_query metabase-mcp_execute_query metabase-mcp_query metabase-mcp_execute_question metabase-mcp_construct_query grafana-mcp_query_loki_logs grafana-mcp_query_loki_patterns get_sentry_resource get_issue_details get_event_stacktrace get_event_attachment get_issue_breadcrumbs get_issue_tag_values get_issue_user_reports search_errors search_issue_events search_logs search_replays get_replay_details search_agent_conversations get_agent_conversation_details; do
  if jq -e --arg tool "$tool" '[.trusted[], .hosts[][]] | index($tool) != null' "$READ_TOOLS_FILE" >/dev/null; then
    echo "FAIL: '$tool' in claude/mcp-read-tools.json should be absent"
    failures=$((failures + 1))
  fi
done
# The `trusted` tools carry their upstream prefix, so a trusted server that bundles several upstreams never matches a bare name meant for another one.
if jq -e '.trusted | any(contains("-mcp_") | not)' "$READ_TOOLS_FILE" >/dev/null; then
  echo "FAIL: a tool under 'trusted' in claude/mcp-read-tools.json has no upstream prefix"
  failures=$((failures + 1))
fi
# Only public hosts are committed, a private one belongs in the trusted hosts file on the machine. A new public host is added here on purpose.
if ! jq -e '(.hosts | keys) == ["mcp.sentry.dev"]' "$READ_TOOLS_FILE" >/dev/null; then
  echo "FAIL: claude/mcp-read-tools.json names a host other than mcp.sentry.dev"
  failures=$((failures + 1))
fi
# The trusted hosts file holds a private host and stays on the machine, never in the repository.
if git -C "$TESTS_SCRIPT_DIRECTORY/.." ls-files | grep -q 'mcp-trusted-hosts$'; then
  echo "FAIL: a mcp-trusted-hosts file is tracked, it must stay outside the repository"
  failures=$((failures + 1))
fi
# The machine settings file names work servers and skills and stays on the machine, never in the repository.
if git -C "$TESTS_SCRIPT_DIRECTORY/.." ls-files | grep -q 'machine-settings.json$'; then
  echo "FAIL: a machine-settings.json file is tracked, it must stay outside the repository"
  failures=$((failures + 1))
fi

# A skill hidden from the model in one tool must be hidden in all three, `Claude Code`, `OpenCode` and `Copilot CLI`, and `Codex`.
for skill_file in "$TESTS_SCRIPT_DIRECTORY"/../.config/agentic/skills/*/SKILL.md; do
  grep -q '^disable-model-invocation: true$' "$skill_file" || continue
  skill_directory=$(dirname "$skill_file")
  skill=$(basename "$skill_directory")
  if ! jq -e --arg skill "$skill" '.skillOverrides[$skill] == "user-invocable-only"' "$SETTINGS_FILE" >/dev/null; then
    echo "FAIL: '$skill' hides itself in its frontmatter but is not user-invocable-only in skillOverrides"
    failures=$((failures + 1))
  fi
  if ! grep -q 'allow_implicit_invocation: false' "$skill_directory/agents/openai.yaml" 2>/dev/null; then
    echo "FAIL: '$skill' hides itself in its frontmatter but its agents/openai.yaml allows implicit invocation"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "PASS: claude-settings"
