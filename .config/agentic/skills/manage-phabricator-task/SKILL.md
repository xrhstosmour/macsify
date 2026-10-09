---
name: manage-phabricator-task
description: >
  Create and edit Phabricator tasks via the Phabricator MCP server: new tasks, or
  updating status, title, description, owner, priority, tags, workboard column, or
  subscribers. Also posts stakeholder status updates. Use when the user mentions
  Phabricator or "phab" with create, update, reassign, close, tag, move, or status
  update on a task.
---

# Manage Phabricator Task

Not for just reading tasks, use the `read-phabricator-task` skill for that. A "parent task" with no existing TID given means a new umbrella, see "Umbrella tasks".

## Authentication

Official Phabricator MCP server only. Phabricator holds files, shared passwords, and secrets far beyond task content, so a manually managed credential is real exposure.

- Discover the tools with `ToolSearch` (query `"phabricator"` or `"maniphest"`), names depend on local registration, never hardcode a guess.
- If the tools are missing, resolve the server URL as in the `read-phabricator-task` skill's Authentication section, don't re-derive it here.
- No token is needed. The first call opens a browser tab to authorize, and a re-authorize prompt mid-session is expected, not a failure.
- Never fall back to a stored Conduit token, raw `curl` to `$PHAB/api/...`, or another Phabricator MCP server. If the official one misbehaves, loop in the platform team.

## Known limitations

Verified live against this server, don't work around them:

- No user directory search. `pha_user_search` returns "not authorized" for every query, only `pha_user_whoami` (self) works. See "Resolve a username to a PHID".
- No subscriber field on `pha_task_create` or `pha_task_update`, and `pha_task_update_relationships` only handles `subtask`/`parent`. The only way to subscribe someone is @-mentioning their `PHID-USER-...` in a description or comment.
- `pha_task_create` accepts only `title`, `description`, and `owner_phid`. Everything else needs a follow-up `pha_task_update`, so creation is always two calls.
- The `reference` parameter exists only on `pha_task_update`, not on create.
- Schemas drift, so due date and `reference` are checked by "Field discovery", not assumed.

## Field discovery

Once per session, cache the result:

- Call `ToolSearch` (`"phabricator task update"` or `"phabricator task create"`) and inspect the live schemas of `pha_task_update` and `pha_task_create` for a due-date-shaped parameter (match by name or description, it may be a standard param or a custom-field key on this instance) and confirm `reference` still exists on `pha_task_update`.
- A real due-date field: pass `YYYY-MM-DD` through it and never write a `**Due:**` line. None found: the description carries a `**Due:** <date>` line.
- A real `reference` field: the PR/branch value goes only there, plus any extra links beyond it in the description. None found: everything goes in the description's `## References` section.
- Read and write can be asymmetric. A due date may show on `pha_task_get` or `pha_task_search_advanced` under an instance-specific custom-fields object even with no writable parameter. A date already set there, for example from the web UI, is the source of truth, don't overwrite or ignore it.

## Tag model

Some workflows use four tracking categories per task. Nothing is stored, ask fresh each conversation:

1. Umbrella/roadmap tag: marks a task big enough for a roadmap view.
2. Later/parked tag: real work not being picked up yet.
3. Domain tag: exactly one per task, chosen from domain-shaped tags in use. Never two, if asked, make the user pick one.
4. Due/launch date: the real field, not a tag. Only relevant within about three weeks, tell the user about a date outside that window instead of silently accepting it.

Apply this model only when the user names one of these categories or a workboard column, or when candidate tags look domain, umbrella, or later shaped. If unclear, ask once at the start of creation: "Does this task track by domain/umbrella/later tags?" A no, or no signal, means the plain single-tag flow in step 1.

If the user already named the target tag or project, resolve and confirm it with `pha_project_search` and skip candidate discovery. Never choose a tag the user didn't name, build a candidate list every time from two deduplicated sources and let them pick:

1. Tags in use on the board the user names, from `pha_task_search_advanced` with `projects=[<board PHID>]`, `include_projects=true`. Ask which board if unclear.
2. Tags on the user's own tasks from the last week, `author_phids=[<self PHID>]`, `created_after=<unix timestamp for 7 days ago>`, `include_projects=true`.

Present the list with "or something else", ask which role each plays (domain, umbrella, later), and apply exactly what they confirm.

### Umbrella tasks

An umbrella is a normal task carrying the umbrella tag. "Parent task" with no TID given means create one. With an existing TID, that is the "Parent task: TID" field, a different meaning.

- Owner is a hard requirement when the umbrella tag is applied. At the step 5 preview, if owner would be unset, stop and say why, an unowned umbrella vanishes from every downstream view.
- Title format `☂️ Name`, or `☂️ <flag emoji> Name` for a specific market or region. A default suggestion, show the drafted title and confirm.
- File real work as subtasks: `pha_task_update_relationships(task_id=<child PHID>, relationship_type="parent", target_ids="<umbrella PHID>")`. The tool doesn't say which side becomes parent, so the direction is inferred. Right after, re-fetch the child with `pha_task_get(task_id=<numeric ID>)` and check the live response for the parent relationship before reporting success. If it isn't clear, say so and ask the user to check in Phabricator.
- An umbrella plus several children in one request: gather shared fields once (domain tag, assignee, uniform due date), show one combined preview, take one confirmation for the set, still ask titles and descriptions per child. Create the umbrella first, then each child, linking it as you go.

## Workboard columns

Some workflows track planning status only by workboard column. This is separate from the `status` field (`open`/`inprogress`/`resolved`), don't conflate them.

- The board is itself a Phabricator project, ask which if unclear and resolve it with `pha_project_search`. A task usually needs the board's project tag before it can sit in a column.
- Column names are whatever the user's board uses, never assume "In Progress".
- To move a task: get the board PHID, call `pha_workboard_search_columns` with `project_phids=[<PHID>]` for the live names and PHIDs (cache for the conversation), match the user's wording (ask if ambiguous), show "Moving T1234 to column '<name>'", get confirmation, then `pha_workboard_move_task(task_id=<ID or PHID>, column_phid=<PHID>)`.
- Offer the column as an optional field in creation (step 2) and in updates.

## Status update comment

A distinct, opt-in action, not a generic comment. Some workflows rely on the literal prefix `Update:` to tell public stakeholder status from internal discussion.

- Draft or post only when the user explicitly asks ("post a status update on T1234", "write an update for stakeholders"), never proactively.
- Post on the task's umbrella if it has one, otherwise on the task itself. `has_parents` on `pha_task_search_advanced` is only a search filter and can't tell you which parent a task has. Inspect the task's own response for a parent link and check the parent carries the umbrella tag. Tell the user which task you're posting to before asking for approval.
- Text starts with the exact string `Update:` followed by one short sentence on what is being worked on, current status, and a rough timeline only if there is a real one. The reader is non-technical leadership skimming a roadmap, so no jargon or implementation detail. Style: "Update: Working on free trial functionality for specific users, on track, underlying logic will probably be live in the next few days."
- Timelines are conservative, hedge with "probably", "should be", "next few days", and never say "done" or imply near-completion before the state is confirmed. Before describing a PR's status, invoke the `read-github-pr` skill to check its requested reviewers and review decisions, "in review" means a reviewer was actually requested, not that comments exist.
- Technical detail goes in a separate plain comment without the prefix, on the task where the work happened (the subtask), never in the `Update:` line and never on the umbrella. Never prefix an internal comment with `Update:`.
- Show the draft and get explicit approval before `pha_task_add_comment`.

### Resolve a username to a PHID

`pha_task_search_advanced(assigned=["<username>"], limit=1)` resolves usernames server-side, read `ownerPHID` off the first result. Use it for subscribers and non-self assignees. If empty, that person never owned a task, ask for their `PHID-USER-...` or have the user add them after creation.

## Task creation workflow

### 1. Gather required fields

- Tag, required. If the user named it, resolve and confirm it. If "Tag model" applies, gather domain (required, one), umbrella (y/n), and later (y/n) together in one prompt from the live candidate list. Otherwise ask "Which tag?", offering tags from the user's own tasks of the last week plus "or something else". Resolve a name to a PHID with `pha_project_search` (`name_like=<text>`), showing candidates when there is no exact match.
- Title, required: a short imperative phrase, at most about 60 characters, stating the outcome ("Support dark mode", not "Investigate dark mode support"). No priority prefix, no backticks, Phabricator titles are plain text.

### 2. Gather optional fields

Ask all at once in a single message. Status and due date are always asked, never silently defaulted.

- Description: generate from git? y/n.
- Priority: P0 to P4.
- Assignee: default self, resolved with `pha_user_whoami`, or another username per "Resolve a username to a PHID".
- Subscribers: usernames.
- Status: open, in progress, or resolved, default open.
- Due date: any format, normalize to `YYYY-MM-DD`.
- Parent task: TID.
- Reference links.
- Committed-board column: only when "Workboard columns" applies.

### 3. Description generation

If generating, gather context with `git log` and `git diff --stat` against the repo's default branch, and `gh pr view --json number,url` for a PR. If there is no code context, ask what the description should say.

Tone: conversational and direct, no jargon or acronyms, short sentences with one idea each, describe the user-facing problem and impact, not code changes.

Remarkup is Phabricator's dialect, not GitHub Markdown: leave a blank line after every `##` header and after any line ending in `:` before a list, or headers merge into the paragraph and lists render as plain text. Format every URL as `[[https://example.com | Label]]`, never bare.

```
## Why

Users could not find the settings they needed because options were scattered across screens.

## What

Settings now live on one page in the sidebar, with a search bar.

## References

- [[https://github.com/org/repo/pull/123 | PR #123]]
```

A bug task uses `## How to reproduce` (numbered steps) and `## What we found` instead of Why and What. The due date and the reference are placed in step 6, not here. Show the description and get approval.

### 4. Resolve PHIDs

Resolve project, parent-task, subscriber, and non-self assignee PHIDs before creating, running independent lookups concurrently. Show candidates and ask when there is no exact match.

### 5. Preview and confirm

```
Tag:         <project>, or Domain/Umbrella/Later when the tag model applies
Title:       <title>
Priority:    <priority>
Assignee:    <username>, default self, required when the umbrella tag is set
Subscribers: <usernames>, or none
Status:      <status>
Due date:    <date>, or none
Column:      <board column>, or none
Parent:      T<id>

<description>
```

Ask "Ready to create?" and do not execute without explicit confirmation.

### 6. Execute creation

1. Append one `@<phid>` per subscriber to the end of the description, that auto-subscribes them.
2. Due date: with a real field, set it in step 5 below. Without one, append `**Due:** <YYYY-MM-DD>` after a blank line at the bottom.
3. Reference value: `[[<pr_url> | PR #<number>]]` if a PR exists, otherwise Branch `` `<branch-name>` ``. With a real `reference` field it goes there in step 5, with any extra links still in the description. Without one, it goes in the description with any extra links. Whatever lands in the description goes in a `## References` section at the very bottom, below the `**Due:**` line.
4. `pha_task_create(title=..., description=..., owner_phid=<assignee PHID>)`. It returns `id` and `phid`, report the task as `$PHAB/T<id>`. New tasks default to "Needs Triage", status open, and no project tag.
5. Follow up with `pha_task_update(task_id=<phid>, ...)` for tag, non-default priority, non-open status, reference, and a real due-date field, a task without this call is missing them. Two cases use other tools: a parent via `pha_task_update_relationships` (see "Umbrella tasks" for the call and verification) and a board column via `pha_workboard_move_task`, without it the task is left off the board.

| Field | `pha_task_update` param |
|-------|-------------------------|
| Tag | `projects_add` (array of PHIDs), or `projects_set` to overwrite |
| Priority | `priority`, keyword |
| Assignee | `owner_phid` |
| Status | `status`: `open`, `inprogress`, `resolved` |
| Reference link | `reference` |
| Due date | the real field from "Field discovery", else the `**Due:**` line |
| Parent task | `pha_task_update_relationships`, `relationship_type="parent"`, `target_ids` a comma-separated string of PHIDs |
| Board column | `pha_workboard_move_task` |

### 7. Errors

Show the tool's Conduit error. Re-resolve an invalid PHID. For insufficient permissions, tell the user and don't try another auth path. A rejected priority means a display name was passed instead of the lowercase keyword. A session-expired error means re-run the tool to trigger the browser authorize flow. Otherwise show the full output and ask.

## Update existing task

Fetch with `pha_task_get` by numeric ID to confirm the task and show a before and after preview. Apply with `pha_task_update` using the PHID and any of `status`, `title`, `description`, `owner_phid`, `priority`, `projects_add`/`projects_remove`/`projects_set`. Show the change and get confirmation first.

- Due date: a real field is set directly. Without one, fetch the description with `pha_task_get`, add or replace the `**Due:**` line at the bottom, and write the whole description back.
- Reference: a real `reference` parameter is set directly, extra links go in `## References`. Without one, make sure the PR/branch value is in `## References`. That section always sits below the `**Due:**` line.
- Board column: see "Workboard columns". Stakeholder status update: see "Status update comment", not a plain comment.
- To comment or add subscribers, use `pha_task_add_comment` and mention each person as `@<phid>`.

## Priority keywords

Strict, case-sensitive lowercase, the API rejects `"Normal"`: `unbreak` (P0 Unbreak Now!), `triage` (Needs Triage, the default for new tasks), `high` (P1), `normal` (P2), `low` (P3), `wish` (P4 Wishlist).
