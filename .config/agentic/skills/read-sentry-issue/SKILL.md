---
name: read-sentry-issue
description: Use when a Sentry issue/event link appears, or when working with Sentry error tracking via the official Sentry MCP server, listing organizations/projects/issues, or fetching event/stacktrace details for an issue.
---

# Read Sentry Issue

## When to use

- User shares a Sentry issue/event link `https://sentry.io/organizations/<org>/issues/<id>/` or `<org>.sentry.io/issues/<id>/`.
- User mentions Sentry or error tracking by name.
- Investigating an exception, stack trace, or production error that might be tracked in Sentry.

## Authentication

Use Sentry's official hosted MCP server. It needs no manually-issued token: the first call opens a browser to sign in, and Sentry's OAuth session is reused for later calls.

- Discover the available tools with `ToolSearch` (query `"sentry"` or a specific tool name like `"get_issue_details"`), exact registered names depend on how the server was added locally, do not hardcode a guess.
- One-time setup, if the tools aren't found: tell the user to run `claude mcp add --transport http sentry "https://mcp.sentry.dev/mcp?skills=inspect" -s user`, then `claude mcp login sentry` (same URL works for OpenCode or any other MCP-capable client, this is Sentry's own public endpoint, not org-specific).
- The `?skills=inspect` URL param alone is NOT enough, verified live: Sentry's MCP always exposes a small fixed "core" tool set (`find_organizations`, `find_projects`, `search_issues`, `search_events`, `get_sentry_resource`, `search_sentry_tools`, `execute_sentry_tool`, plus `update_issue` and `analyze_issue_with_seer`) regardless of that param, it only narrows the secondary catalog reached through `search_sentry_tools`. The real read/write boundary is decided on the OAuth consent screen `claude mcp login sentry` opens in the browser. That screen shows four checkboxes, all checked by default:

  | Category | Tools | Read or write |
  |----------|-------|----------------|
  | Inspect Issues & Events | 37 | Read-only, keep checked |
  | Seer | 11 | Runs Sentry's AI analysis, not a data mutation, but not needed for this skill, uncheck |
  | Triage Issues | 17 | Resolve/assign/update issues, write, uncheck |
  | Manage Projects & Teams | 15 | Create/modify projects/teams/DSNs, write, uncheck |

  Tell the user to uncheck everything except "Inspect Issues & Events" before clicking Approve. Confirmed after doing this correctly: `update_issue` and `analyze_issue_with_seer` disappear from the tool list entirely, and searching `search_sentry_tools` for write-shaped queries (`"update issue"`, `"create project"`, `"resolve assign"`) returns none, every result comes back tagged `readOnlyHint: true`. If a fresh login only shows one box, or the boxes differ from this, re-check before assuming it's still read-only, Sentry could change this screen.
- Never fall back to a stored Sentry token (`sentry-cli`, `~/.sentryclirc`, or otherwise) or a raw `curl` call to the REST API. If the MCP misbehaves, tell the user rather than falling back.

## Required behavior

- Always use the Sentry MCP tools first.
- SSO-protected pages usually return a Google sign-in HTML page, not issue content, that's a sign something is bypassing the MCP tools.

## Tool reference

The `sentry-mcp` server exposes a small set of tools directly and reaches the rest through a discovery layer, confirmed live against this server:

Directly available:

| Task | Tool |
|------|------|
| List organizations | `find_organizations` |
| List projects for an org | `find_projects` |
| Search/list issues, by query or status | `search_issues` |
| Cross-issue event search/stats, natural language or Sentry query syntax | `search_events` |
| Fetch an issue/event/trace/replay by URL or ID, auto-detects the type | `get_sentry_resource` |
| Find any other operation, e.g. `"issue activity"`, `"stacktrace"`, `"breadcrumbs"` | `search_sentry_tools` |
| Execute a tool found via `search_sentry_tools` | `execute_sentry_tool` |

`get_sentry_resource` given a plain issue/event/trace/replay URL is usually the fastest path, it returned full issue details, the exception, and stacktrace in one call when tested against a real issue link. For anything not covered above, e.g. issue activity/history, breadcrumbs, tag value breakdown, user reports, docs search, call `search_sentry_tools` first to find the right tool and its schema, then `execute_sentry_tool` to run it. Don't assume a tool name and call it directly if it isn't in the list above, it likely isn't a top-level tool.

`search_events` is AI-powered and needs an LLM provider configured server-side, it may be unavailable depending on how the MCP server was deployed.

This skill is read-only. With only "Inspect Issues & Events" granted at login (see Authentication above), mutating tools like `add_issue_note`, `update_issue`, `create_project` aren't reachable at all. If a differently-scoped login ever makes one visible, don't call it, that's a sign the login needs to be redone with the write categories unchecked, not a green light to use it.

## Interpreting issue/event data

- Stacktrace frames in the API payload run outermost to innermost, the last in-app frame is the one that raised. The Sentry web UI reverses this by default (most-recent-first), so don't cross-reference payload order against a screenshot without accounting for that.
- Chained/nested exceptions appear as separate entries in the exception values list, in root-cause-first order, the last entry is what actually surfaced to the user.
- An issue's lifetime count (from a full issue/resource fetch) is not the same as a time-windowed count (from a search scoped to a period like the last 24 hours), don't conflate the two.
- Full raw issue/event payloads can be large, when a fetch returns a big blob, pull out only the fields needed (culprit, stacktrace frames, tags) rather than passing the whole thing through.

## Notes

- Task/issue links: `https://sentry.io/organizations/<org>/issues/<id>/` or `<org>.sentry.io/issues/<id>/`.
- If the MCP tools aren't available, tell the user to add the server rather than falling back to a token, see Authentication above.
