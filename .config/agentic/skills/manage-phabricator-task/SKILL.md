---
name: manage-phabricator-task
description: >
  Create and edit Phabricator tasks via the official Phabricator MCP server: new
  tasks, or updating an existing task's status, title, description, owner, priority,
  project tags, or subscribers, added indirectly via @-mention, resolved from a
  username where possible.
  Triggered when the user explicitly mentions Phabricator or "phab": "create phab
  task/ticket/issue", "create a parent/umbrella task", "update/edit phab task",
  "reassign/close/reopen task T<id>", "change priority on T<id>", "tag T<id>",
  or "/manage-phabricator-task".
---

# Manage Phabricator Task

## When to use

- User asks to create, file, open, or submit a Phabricator task or ticket, including a "parent task" with no existing TID given, see "Umbrella tasks" below for that disambiguation.
- User asks to update, edit, reassign, close, reopen, or change the status/priority/tags of an existing Phabricator task.
- Do NOT use for just reading existing tasks. Use the `read-phabricator-task` skill for that.

## Authentication

Use the official Phabricator MCP server only. Phabricator holds files, shared passwords, and secrets far beyond task content, so a manually managed credential is real exposure.

- Discover the available tools with `ToolSearch` (query `"phabricator"` or `"maniphest"`), exact tool names depend on how the server was registered locally, do not hardcode a guess.
- One-time setup, if the tools aren't found: resolve the server URL exactly as described in the `read-phabricator-task` skill's Authentication section, `$PHABRICATOR_MCP_URL`, then `~/.arcrc`-derived, then ask the user, don't re-derive it a different way here.
- No token is required. The first call opens a browser tab for login/authorize. Tokens are ephemeral and periodically expire, a re-authorize prompt mid-session is expected behavior, not a failure.
- Never fall back to a stored Conduit token, a raw `curl` call to `$PHAB/api/...`, or a different Phabricator MCP server. If the official MCP misbehaves, loop in the platform team instead.

## Known limitations

Verified live against this MCP server, don't try to work around these:

- No user directory search. `pha_user_search` returns "not authorized" for every query shape tried, on an account that otherwise has full task read/write access. Treat it as unavailable, `pha_user_whoami` (self) is the only user-lookup tool that works directly. See "Resolve a username to a PHID" below for a working alternative.
- No subscriber field on `pha_task_create`/`pha_task_update`, not a permissions issue, the field doesn't exist on those tools. `pha_task_update_relationships` only handles `subtask`/`parent` edges. The only way to subscribe someone is indirect: @-mentioning their `PHID-USER-...` in a description or comment auto-subscribes them.
- Due date field: don't assume it's present or absent, see "Field discovery" below, this instance may have gained or lost it since the last check. The description always carries a `**Due:** <date>` fallback line regardless (see step 6).
- Reference links do have a real field, `pha_task_update`'s `reference` parameter, but only on `pha_task_update`, `pha_task_create` doesn't accept it. A new task always needs the create-then-update two-call pattern to persist a reference (see step 6). Re-confirm this still holds via "Field discovery" below, schemas can drift.

## Field discovery

Run once per session, cache the result for the rest of the session, don't re-discover on every call:

- Call `ToolSearch` (query like `"phabricator task update"` or `"phabricator task create"`) and inspect the live schema of `pha_task_update`/`pha_task_create` for a due-date-shaped parameter, match by parameter name or description containing due/deadline/date semantics, don't hardcode one exact expected name, it may be a standard param or a custom-field key on this instance.
- Re-confirm the `reference` parameter still exists on `pha_task_update` the same way, schemas can drift in either direction, not just grow.
- If a real due-date parameter or custom field is found, pass the normalized `YYYY-MM-DD` value through it directly.
- Regardless of whether a real field was found, always also keep the `**Due:** <date>` description-line fallback (see step 6), a newly-appeared field could be write-restricted, non-persisting, or display-only on this instance, never rely on it alone.
- Read and write can be asymmetric: even with no writable due-date parameter on `pha_task_update`/`pha_task_create`, a real value may still show up when *reading* a task, under a custom-fields-style object on `pha_task_get`/`pha_task_search_advanced` responses (key names are instance-specific, inspect the actual response rather than assuming one). If a task already has a real due date set there, e.g. from the Phabricator web UI directly, treat that as the source of truth over the description's `**Due:**` line, don't overwrite or ignore it.

## Tag model

Some workflows use exactly four tracking categories on every task. Nothing about this is stored anywhere, ask about it fresh in every conversation:

1. **Umbrella/roadmap tag**: one tag marking a task big enough to belong on a roadmap view.
2. **Later/parked tag**: one tag for real-but-not-being-picked-up-yet work.
3. **Domain tag**: exactly one per task, chosen from whatever domain-shaped tags are actually in use. Never apply two, if the user tries, ask them to pick one.
4. **Due/launch date**: the real field from "Field discovery" above, not a tag. Only relevant within roughly the next three weeks, a stale or far-future date is effectively ignored by anything reading it downstream, mention this to the user rather than silently accepting a date outside that window.

Only apply this model when the user names one of these categories, umbrella, later, domain, or a workboard column, or when candidate tags turned up while resolving them look domain/umbrella/later-shaped. If it's unclear which applies, ask once near the start of task creation: "Does this task track by domain/umbrella/later tags?" A no, or no signal either way, falls back to the plain single-tag flow in step 1 below.

If the user already names the target tag or project directly in their request (e.g. "create it in <project>", "tag this <project>"), resolve and confirm that one via `pha_project_search` directly, skip the candidate-list discovery below entirely, that's only for when no tag was named.

This skill never decides or applies a tag on its own when the user hasn't named one, always ask and let the user pick, nothing here is cached or persisted between conversations. Building the candidate list, every time, from two sources, deduplicated:
1. Unique project tags currently in use on whichever board/project the user names, collected from that board's own tasks via `pha_task_search_advanced` with `projects=[<board project PHID>]`, `include_projects=true`. Ask which board/project if it isn't already clear from the conversation.
2. Unique tags found on the user's own tasks created in the last week, `pha_task_search_advanced` with `author_phids=[<self-phid>]`, `created_after=<unix timestamp for 7 days ago, e.g. \`date -v-7d +%s\` on macOS or \`date -d '7 days ago' +%s\` on Linux>`, `include_projects=true`.

Present the combined list alongside "or something else," ask which role each chosen tag plays, domain, umbrella, later, then apply exactly what the user confirms.

### Umbrella tasks

An umbrella is a normal task carrying the umbrella tag, not a separate task type or creation path.

- "Create a parent task" (with no existing TID given to attach under) means create a new umbrella, not the "Parent task: TID" field below, that field links a task under an *existing* task and is a different meaning of "parent". If the user gives an existing TID to attach under, that's the TID field, not this section.
- **Owner is a hard requirement, not just a default**, when the umbrella tag is being applied. At the preview/confirm step (step 5), if owner would be unset, stop and say why, an unowned umbrella disappears from every downstream view, not just this one.
- Title format: `☂️ Name`, or `☂️ <flag emoji> Name` when a specific market/region is the point of the task. Default suggestion, not mandatory, show the drafted title and confirm rather than applying it silently, the user can ask for a different format.
- Real work gets filed as subtasks: from the child task, call `pha_task_update_relationships(task_id=<child PHID>, relationship_type="parent", target_ids="<umbrella PHID>")`, the existing mechanism already documented under "Parent task" in the field table below, nothing new to call. The tool's own description doesn't state which side ends up as parent, only the enum name, so this direction is inferred, not confirmed. Immediately after the call, re-fetch the child task (`pha_task_get(task_id=<child numeric ID>)`, this tool's schema documents a numeric ID, not a PHID, unlike `pha_task_update_relationships` above) and inspect the actual response for the parent relationship, field names aren't confirmed here, read whatever the live response actually contains rather than assuming a key, before telling the user it's done. If the response doesn't surface it clearly enough to confirm the direction, say so plainly and ask the user to check the task in Phabricator rather than reporting success unverified.
- Umbrella plus several children in one request, e.g. splitting a discussion into an umbrella with child tasks under it: gather fields shared across every child once (domain tag, assignee, due date if uniform), then show one combined preview covering the umbrella and all children together, one confirmation for the whole set rather than one per task. Titles and descriptions still get asked per child, don't force a shared one. Execute in order: create the umbrella first, then each child, linking each to the umbrella as it's created.

### Resolve a username to a PHID

`pha_user_search` can't look up other people, but `pha_task_search_advanced` accepts plain usernames in its `assigned` filter and resolves them server-side. Call `pha_task_search_advanced(assigned=["<username>"], limit=1)` and read `ownerPHID` off the first result, that's the person's PHID. Use this for a subscriber, or an assignee other than self. If it comes back empty, that person has never owned a task and can't be resolved this way, ask for their `PHID-USER-...` directly or tell the user to add them manually after creation.

## Task creation workflow

### 1. Gather required fields

- Tag(s), required: if the user already named the tag/project, resolve and confirm it directly, see "Tag model" above, skip the rest of this bullet. Otherwise, if "Tag model" above applies (the user is explicitly tracking domain/umbrella/later tags, or names a workboard to track status by column), gather domain (required, exactly one), umbrella (optional, y/n), and later (optional, y/n) together as one structured prompt, resolving literal names per "Tag model"'s live candidate-list flow, never pick one automatically. Otherwise, plain single Phabricator project tag: ask "Which tag?" Before asking, check the user's own tasks created in the last week (`pha_task_search_advanced` with `author_phids=[<self-phid>]`, `created_after=<unix timestamp for 7 days ago>`, `include_projects=true`) and offer any tags found there as quick options alongside "or something else". Resolve a chosen or typed name to a PHID with `pha_project_search` (`name_like=<text>`), show candidates and ask when there's no exact match.
- Title, required: Short imperative phrase, max ~60 characters, states the outcome not the activity, e.g. "Support dark mode" not "Investigate dark mode support". No priority prefix, priority is a separate field. Do not wrap words in backticks, unlike commit messages, Phabricator titles are plain text. Example: Add dark mode toggle.

### 2. Gather optional fields

Ask all at once in a single message. Status and due date are always asked, never silently defaulted:

- Description: auto-generate from git? y/n
- Priority: P0–P4
- Assignee: default self-assign
- Subscribers: usernames, resolved to PHIDs, see "Resolve a username to a PHID" above
- Status: open, in progress, or resolved, default open, see the status keyword table in step 6
- Due date: optional, any date the user gives, normalize to `YYYY-MM-DD` before using it, see "Field discovery" above, always lands in the description as a fallback, and in the real field too when one exists
- Parent task: TID
- Reference links: goes in the description's `## References` section and, when present, in the real `reference` field too, see step 6

Resolve the current user's PHID for self-assignment via `pha_user_whoami`. Use this PHID as the default assignee unless the user names someone else, in which case resolve their username the same way as subscribers.

### 3. Description generation

If generating, gather git context:

```bash
BRANCH=$(git branch --show-current)
BASE_BRANCH="master"
git fetch origin "$BASE_BRANCH" 2>/dev/null || true
COMMITS=$(git log --oneline "${BASE_BRANCH}"..HEAD 2>/dev/null || git log --oneline HEAD~5..HEAD 2>/dev/null || echo "")
FILES=$(git diff --stat "${BASE_BRANCH}"..HEAD 2>/dev/null || git diff --stat HEAD~5 2>/dev/null || echo "")
CHANGES=$(git diff "${BASE_BRANCH}"..HEAD -- '*.swift' '*.md' 2>/dev/null | head -200 || echo "")
PR_JSON=$(gh pr view --json number,url 2>/dev/null || echo "")
PR_NUMBER=$(echo "$PR_JSON" | jq -r '.number // empty')
PR_URL=$(echo "$PR_JSON" | jq -r '.url // empty')
```

Tone rules:
- Conversational, direct. Rewrite if it sounds stiff when read aloud.
- No jargon or acronyms. Explain technical terms in one sentence if unavoidable.
- Short sentences. One idea each.
- Describe user-facing problem and impact, not code changes.

Remarkup formatting rule, Phabricator's markup dialect, not GitHub-flavored Markdown: always leave a
blank line after a `##` header before its content, and a blank line after any line ending in `:` before
a following list. Remarkup does not reliably render headers or lists without that spacing, headers can
merge into the paragraph below them, and lists can render as plain text. Apply this to every description
you generate, not just the examples below.

Feature example:
```
## Why

Users could not find the settings they needed because options were scattered across multiple screens.

## What

Settings now live on a single page accessible from the sidebar with a search bar.

## References

- [[https://github.com/org/repo/pull/123 | PR #123]]
```

Bug example:
```
## How to reproduce

1. Open the app and go to the dashboard.
2. Click Export. Nothing happens.

## What we found

The export endpoint failed when the server session expired. Refreshing the session before export fixed it.

## References

- [[https://github.com/org/repo/pull/456 | PR #456]]
```

If no code context exists, ask: "What should the description say? I can help draft it."

Always end with a `## References` section, followed by a blank line and then the list. Format every URL
as a Remarkup hyperlink: `[[https://example.com | Label]]`. Never use bare URLs. Include:

- If a PR exists: `[[<pr_url> | PR #<number>]]`, omit the branch since the PR implies it
- If no PR exists: Branch `` `<branch-name>` ``
- Any extra links the user provided

Show the generated description and ask for approval before proceeding.

### 4. Resolve PHIDs

Resolve project and parent-task PHIDs via `pha_project_search`/`pha_task_search_advanced` before creating, and any subscriber or non-self assignee usernames per "Resolve a username to a PHID" above, launch independent lookups concurrently when multiple are needed.

Show candidates and ask when there's no exact match.

### 5. Preview and confirm

```
Tag:         <project-name>, or Domain/Umbrella/Later when "Tag model" applies
Title:       <title>
Priority:    <priority>
Assignee:    <username>, default: self, required when the umbrella tag is set
Subscribers: <usernames>, or none
Status:      <status>
Due date:    <date>, or none
Parent:      T<id>

<description>
```

Ask: "Ready to create?" Do NOT execute without explicit confirmation.

### 6. Execute creation

`pha_task_create` only accepts `title`, `description`, and `owner_phid`, nothing else, so this is always two calls, not one:

1. If any subscribers were resolved, append one `@<phid>` mention per person to the end of the description, that's what auto-subscribes them, there's no separate field for it.
2. If a due date was given, prepend a `**Due:** <YYYY-MM-DD>` line to the top of the description, followed by a blank line, this always happens regardless of whether a real field is also available. See "Field discovery" above, if a real field was found, plan to set it too in step 5.
3. If a reference link was given, make sure it's in the description's `## References` section, then plan to also set it via the real `reference` parameter in step 5.
4. `pha_task_create(title=..., description=..., owner_phid=<assignee-phid>)`. On success it returns the created task's `id`/`phid`, report the task back as `$PHAB/T<id>`. New tasks default to priority "Needs Triage" and status "open", not Normal, and to no project tag at all.
5. A tag, non-default priority, non-open status, a reference link, or a due-date parameter found in step 2, needs a follow-up `pha_task_update(task_id=<phid from step 4>, ...)` to set it, a task created without this call is missing its tag, reference, and due date. A parent task is the one exception, that goes through `pha_task_update_relationships` instead, never `pha_task_update`, see the field table below and "Umbrella tasks" above for the exact call shape and the verification step after it.

| Field | `pha_task_update` param |
|-------|-------------------------|
| Tag | `projects_add` (array of project PHIDs), or `projects_set` to overwrite |
| Priority | `priority`, keyword, see table below |
| Assignee | `owner_phid` |
| Status | `status`: `open`, `inprogress`, `resolved` |
| Reference link | `reference` |
| Due date | see "Field discovery" above, use the real field if one was found this session, falls back to the description's `**Due:** <date>` line regardless |
| Parent task | use `pha_task_update_relationships` instead, `relationship_type="parent"`, `target_ids` is a comma-separated string of PHIDs, not an array |

### 7. Error handling

The MCP tool surfaces Conduit errors in its response. Common cases:

| Cause | Fix |
|-------|-----|
| Invalid PHID | Re-resolve the PHID |
| Insufficient permissions | Tell the user, don't retry with a different auth path |
| Malformed payload | Check the field values passed to the tool |
| Priority rejected as invalid | You likely passed a display name (`"Normal"`) instead of the lowercase keyword (`normal`), see the priority table below |
| Not authenticated / session expired | Re-run the tool, it should trigger the browser re-authorize flow |
| Other | Show the full tool output, ask the user how to proceed |

## Update existing task

Fetch the task first via `pha_task_get`, by numeric ID, to confirm you have the right one and to show the user a before/after preview.

Then apply the change via `pha_task_update`, passing the task PHID and the field(s) to update: `status`, `title`, `description`, `owner_phid`, `priority`, `projects_add`/`projects_remove`/`projects_set`.

- Reference link: set the real `reference` parameter directly, and also make sure the link is in the description's `## References` section, add it there if it's missing.
- Due date: fetch the current description with `pha_task_get`, add or replace the `**Due:** <date>` line yourself, and write the whole description back, this always happens regardless of whether a real field is also available. See "Field discovery" above, if a real field was found this session, set it directly too.

Use `pha_task_add_comment` to add a comment instead of a field edit, or to add subscribers, resolve their PHIDs per "Resolve a username to a PHID" above and mention each one, `@<phid>`, in the comment.

Show the user what will change and ask for confirmation before executing, same as task creation.

## Priority keyword mapping

Keywords are strict and case-sensitive lowercase, the API rejects `"Normal"` and tells you the valid set on error: `unbreak`, `triage`, `high`, `normal`, `low`, `wish`.

| Code | Name | Keyword |
|------|------|---------|
| P0 | Unbreak Now! | `unbreak` |
| — | Needs Triage | `triage`, this is the default for new tasks |
| P1 | High | `high` |
| P2 | Normal | `normal` |
| P3 | Low | `low` |
| P4 | Wishlist | `wish` |
