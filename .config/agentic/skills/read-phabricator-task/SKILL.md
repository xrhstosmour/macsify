---
name: read-phabricator-task
description: Use when a `Phabricator` link like `https://phabricator.<sub>.<domain>/T<id>` appears, or when reading, searching, or analyzing Phabricator tasks via the official Phabricator MCP server. Not for creating or editing tasks, use the `manage-phabricator-task` skill for that.
---

# Read Phabricator Task

## When to use

- User shares a Phabricator task link like: `https://phabricator.<sub>.<domain>/T<id>`.
- Reading, searching, or analyzing Phabricator tasks via the official Phabricator MCP server.
- User says "Phabricator" or "phab", and isn't asking to create or edit a task, see `manage-phabricator-task` for that.

When you encounter a `https://phabricator.<sub>.<domain>/T<id>` link, use the official Phabricator MCP server to fetch task details and related data.

## Required behavior

- Always use the Phabricator MCP tools first.
- Do not scrape or fetch Phabricator task pages directly in a browser.
- SSO-protected pages usually return a Google sign-in HTML page, not task content.
- If MCP calls fail, troubleshoot the MCP connection/auth first, then retry.

## Authentication

Use the official Phabricator MCP server only. Phabricator holds files, shared passwords, and secrets far beyond task content, so a manually managed credential is real exposure.

- Discover the available tools with `ToolSearch` (query `"phabricator"` or `"maniphest"`), exact tool names depend on how the server was registered locally, do not hardcode a guess.
- One-time setup, if the tools aren't found, resolve the server URL in this order, it's org-specific and must never be hardcoded or guessed:
  1. `$PHABRICATOR_MCP_URL`, if already set in the session.
  2. Derive it from `~/.arcrc`, standard `arc`/Phabricator tooling config, works for any org that has `arc` set up:
     ```bash
     PHAB_HOST=$(jq -r '.hosts | to_entries[] | select(.key | test("phabricator")) | .key' ~/.arcrc 2>/dev/null | head -1)
     [ -n "$PHAB_HOST" ] && echo "${PHAB_HOST%/api/}/ai/mcp"
     ```
     `/ai/mcp` is the path convention this org's MCP is hosted at, try it first, but don't assume every org uses the identical path, if the resulting URL fails to connect, that's a sign to fall through to step 3 rather than retry blindly.
  3. Ask the user for their organization's official Phabricator MCP URL.
  Tell the user to run `claude mcp add --transport http phabricator <url> -s user` (Claude Desktop users can instead check the connectors marketplace for their org's Phabricator connector). This is a manual step the user runs themselves, not something to script.
- No token is required. The first call opens a browser tab for login/authorize. Tokens are ephemeral and periodically expire, a re-authorize prompt mid-session is expected behavior, not a failure.
- Never fall back to a stored Conduit token, a raw `curl` call to `$PHAB/api/...`, or a different Phabricator MCP server. If the official MCP misbehaves, loop in the platform team instead.

## Base URL

Derive the Phabricator base URL from the link you see:

`https://phabricator.example.com/T67890` → `PHAB="https://phabricator.example.com"`

## Fetch a task by ID, T\<id\>

Extract the numeric ID from the link, like `T242861` to `242861`, and pass it to the MCP task-search tool (with `projects`/`subscribers` attachments included if the tool supports it). This is the robust path that avoids SSO HTML pages, always prefer it over a raw fetch of the task URL.

Response fields of interest:

- `result.data[0].fields.name`, title
- `result.data[0].fields.description.raw`, description body
- `result.data[0].fields.ownerPHID`, assignee PHID, null means unassigned
- `result.data[0].fields.authorPHID`, author PHID
- `result.data[0].fields.status.{value,name,color}`, status
- `result.data[0].fields.priority.name`, priority
- `result.data[0].fields.dateCreated` / `dateModified`, epoch timestamps
- `result.data[0].fields.dateClosed`, epoch timestamp, null if open
- `result.data[0].fields.closerPHID`, who resolved it
- `result.data[0].attachments.projects.projectPHIDs`, associated project PHIDs

## Compact task summary

Call the MCP task-search tool by ID and summarize: title, status, priority, created/modified dates, and the first ~3000 characters of the description.

## Task transactions, history and comments

Call the MCP task-transactions/history tool by ID.

Transaction types: `status`, `reassign`, `description`, `title`, `priority`, `core:edge`, `core:create`, `core:subscribers`, `core:space`.

## Resolve PHIDs to names

Call the MCP PHID-resolution tool with one or more PHIDs to get back full name and type for each.

## Search users

Call the MCP user-search tool, by exact username or by fuzzy display-name query. On this org's server it returns "not authorized" for every query shape, only self-lookup (who am I) works directly. To resolve someone else's username to a PHID, search tasks assigned to that username instead and read the owner PHID off a result, see `manage-phabricator-task`'s "Resolve a username to a PHID".

## Search projects

Call the MCP project-search tool by name query.

## Search tasks

Call the MCP task-search tool with the relevant constraint: free-text query, author PHID, or status (`open`, `inprogress`, `resolved`, etc.).

For "tasks I created/updated this week" style queries, resolve self via "Who am I?" below, then filter by `author_phids=[<self-phid>]` plus `created_after`/`modified_after` (Unix timestamps, e.g. `date -v-7d +%s` on macOS or `date -d '7 days ago' +%s` on Linux, for "this week").

## Who am I?

Call the MCP "who am I" tool to get the current authenticated user's PHID and username.

## Workboard columns

Read-only counterparts to `manage-phabricator-task`'s "Workboard columns" section, ask the user which board/project and, if needed, which column, rather than assuming either:

- `pha_workboard_search_columns`: list a board's columns, pass `project_phids=[<board project PHID>]`.
- `pha_workboard_search_tasks_by_column`: list the tasks currently sitting in a given column, pass `column_phid=<column PHID>`.

## Due date / reference fields

This skill is independently invocable, don't assume `manage-phabricator-task`'s "Field discovery" already ran earlier in this session. If it did, reuse that result. If not, do the same live check yourself before relying on either field's absence: `ToolSearch` (query like `"phabricator task update"`) for a due-date-shaped parameter, and confirm the `reference` parameter still exists. A real field, once confirmed present, appears either as a top-level `fields.*` entry or under a custom-fields object on the `pha_task_get`/`pha_task_search_advanced` response, inspect the actual response shape rather than assuming a key path. When no real field was found, fall back to parsing the `**Due:**` line and the `## References` section out of the description body, same fallback contract as the write side.

## Task URL format

- Task links: `https://phabricator.<sub>.<domain>/T<id>`
- User links: `https://phabricator.<sub>.<domain>/p/<username>/`
- Project links: `https://phabricator.<sub>.<domain>/tag/<slug>/`
- The underlying API takes numeric IDs, such as `242861`, not `T242861`.

## Pagination

For large result sets, pass the MCP search tool's cursor/page parameter (if it exposes one) to fetch subsequent pages, rather than assuming a single call returns everything.

## Notes

- Timestamps are Unix epoch, seconds. Convert to ISO 8601 with `date -u -r <epoch> "+%Y-%m-%dT%H:%M:%SZ"`.
- PHIDs are opaque internal identifiers, use the MCP PHID-resolution tool to resolve them.
- If the MCP tools aren't available, tell the user to add the server rather than falling back to a token, see Authentication above.
- If you see Google sign-in HTML, something is trying to fetch the page directly instead of going through the MCP tools, switch to the MCP tools.
