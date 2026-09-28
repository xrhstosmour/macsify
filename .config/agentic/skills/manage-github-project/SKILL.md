---
name: manage-github-project
description: Use for publishing an approved multi-step implementation plan to a GitHub Projects v2 board as one issue per step, assigned to the user, ordered to encode dependencies, plus ongoing status sync and PR linkage back to those issues. Triggered by phrases like "make an agents plan for this in GitHub projects", "break this plan into issues on the board", "put this plan on the project board", "create issues for each step and add them to the project", "track this plan on GitHub Projects", "sync the project board", "mark this in progress/done on the board", "link this PR to the project issue". Not for creating or editing a single standalone issue with no project board involved, see `manage-github-issue`. Not for reading or listing issues/project items without changing anything, see `read-github-issue`. Not for creating or editing the pull request itself, see `manage-github-pr`, this skill only covers the issue side and the board.
---

# Manage GitHub Project

## When to use

- `/manage-github-project`, or user says "make an agents plan for this in GitHub projects and issues", "break this into issues on the board", "put this plan on the project board", "publish this plan to the project", "create issues for each step and link them", "track this in GitHub Projects", "sync the project board", "mark this issue in progress/done on the board", "link this PR to the tracking issue".
- After a multi-step implementation plan has been discussed and approved, and the user wants it tracked as one GitHub issue per step on a Projects v2 board.
- User asks to update an issue's `Status` field on a board, or to record a merged PR against its tracking issue.
- Not for creating or editing a single issue with no project board involvement, see `manage-github-issue`.
- Not for just reading or listing issues/project items, see `read-github-issue`.
- Not for creating or editing the pull request itself, see `manage-github-pr`.
- Not for a full multi-agent code review, see `review-github-pr`.

## Publishing a plan as issues

### 1. Validate Intent

Confirm with the user:
- The plan is approved and its steps are stable, won't reshuffle mid-publish.
- Target repo (`OWNER/REPO`) for the issues.
- Target project: owner (user or org) and either project number or exact title string. If unstated, ask, never assume a specific board even if the user has referenced one before.

If the plan isn't already broken into discrete, orderable steps, stop and ask the user to clarify the steps first. Don't invent a decomposition on their behalf.

### 2. Auth Preflight

```bash
gh auth status
```

Check the scopes list for `project`. Read-only project commands (`item-list`, `field-list`, `view`) work with `read:project` alone, but every mutation this skill performs (`item-add`, `item-edit`, `issue create --project`, `pr edit --add-project`) needs the `project` scope.

If `project` scope is missing, tell the user and stop:

```
Your gh auth token is missing the `project` scope. Run:

  gh auth refresh -s project,read:project

Then re-run this skill.
```

Do not proceed, and do not fall back to a partial or read-only workflow instead.

### 3. Resolve Target and Fields

Look up the project's actual fields, never hardcode option names, they can differ across boards:

```bash
gh project field-list <PROJECT_NUMBER> --owner <owner>
```

Find the `Status` single-select field and its exact option strings (commonly `Todo`, `In Progress`, `Done`, but confirm per board, don't assume). Note any other custom fields the board has, but only ever set fields that actually exist, never invent one.

If `field-list` fails or the project can't be resolved, show the exact command and error, stop, and ask the user for the correct owner/number.

### 4. Preview

Before creating anything, show the user every step as a planned issue:

```
Repo: OWNER/REPO
Project: <owner>/<number> "<title>"

1. <Issue title>
   Body:
     <summary of the step>
     Dependency notes: <e.g. "Blocks #<next-issue-placeholder>" / "Hard dependency on <thing>">
   Assignee: @me
   Status: Todo

2. <Issue title>
   ...
```

Derive dependency notes from the plan's own step ordering, as informal prose (`Blocks #N`, `Depends on step N`) written into the issue body. Do not use GitHub's native sub-issues / Parent-issue feature for this unless the user explicitly opts in, see "Optional: native sub-issues" below, the reference board leaves that field empty on every item and encodes sequence via prose plus manual row order instead.

Ask: "Ready to create these <N> issues and add them to the project board?" Do NOT create anything without explicit confirmation. If the user wants changes, revise and re-preview.

### 5. Create Issues, Add to Project, Set Status

Create each issue, in plan order, assigned to the user. Never interpolate step title or body text directly into a double-quoted shell argument, double quotes don't stop bash from evaluating backticks or `$(...)`, and step text pulled from a plan will often contain backticks per this repo's own conventions. Write the title and body to temp files first via quoted heredocs, `gh issue create` has no `--title-file` flag, so pass the title back in through command substitution on the file (safe, it captures the file's text as one argument without re-evaluating it) and the body through `--body-file`:

```bash
title_file=$(mktemp)
body_file=$(mktemp)
cat > "$title_file" <<'STEP_TITLE'
<step title>
STEP_TITLE
cat > "$body_file" <<'STEP_BODY'
<step body + dependency notes>
STEP_BODY

issue_url=$(gh issue create --repo OWNER/REPO \
  --title "$(cat "$title_file")" \
  --body-file "$body_file" \
  --assignee @me \
  --project "<Board Title>")
issue_number=$(echo "$issue_url" | grep -oE '/issues/[0-9]+$' | grep -oE '[0-9]+')
```

The quoted heredoc (`<<'STEP_TITLE'`, `<<'STEP_BODY'`) is critical, it disables all shell expansion inside the block so backticks, `$(...)`, and `$VAR` in the plan text pass through literally instead of being evaluated.

`--project "<Board Title>"` adds the issue to the board in the same call when the title string resolves unambiguously. If it doesn't (ambiguous or duplicate title, or you only have the project number), add it explicitly:

```bash
gh project item-add <PROJECT_NUMBER> --owner <owner> --url "$issue_url"
```

Set `Status` to the board's "not started" option. Verify the exact required flags against `gh project item-edit --help` at run time before running it, the flag set (`--field`/`--value` vs `--field-id`/`--single-select-option-id`, plus whether it needs the project item's internal `--id`) has varied across `gh` versions, don't assume the shape below is exactly right without checking first:

```bash
gh project item-edit --id <ITEM_ID> --project-id <PROJECT_ID> \
  --field-id <STATUS_FIELD_ID> --single-select-option-id <TODO_OPTION_ID>
```

Resolve `<ITEM_ID>`, `<PROJECT_ID>`, `<STATUS_FIELD_ID>`, `<TODO_OPTION_ID>` from `gh project item-list ... --format json` and `gh project field-list ... --format json` output, never guess these IDs.

If any single issue creation or field-set fails midway, stop immediately. Report exactly which issues were already created (with URLs) and which weren't, then ask the user how to proceed. Never silently retry or silently skip a failed step.

### 6. Report

```
Created N issues on OWNER/REPO, added to "<Board Title>":

1. <title> — <issue_url>
2. <title> — <issue_url>
...

All assigned to @me, Status: Todo.
```

## Ongoing status sync

Run these as separate follow-up invocations of this skill while the plan is executed, not part of the initial publish.

### 7. Mark In Progress

When the user says they're starting a step's work, set that item's `Status` to the board's "in progress" option using the same `item-edit` pattern as Phase 5. If it's ambiguous which issue/step they mean, ask first.

### 8. Link the closing PR

- **Same-repo PR**: this is automatic, no extra action needed here. A PR body containing a closing keyword (`Closes #N`, `Fixes #N`, `Resolves #N`) auto-populates the issue's `Linked pull requests` field and auto-closes the issue on merge. This is exactly the `Why: Resolves [...]` line `manage-github-pr`'s PR body template already writes, no separate command required.
- **Cross-repo PR** (issue in one repo, PR in another): GitHub does not auto-link these. Append a `**Pull requests**` section to the issue body, matching the reference board's format exactly, one line per PR: URL, short description, status. This fetch/splice/overwrite is done inline here rather than delegated to `manage-github-issue`, because it needs the specific "append a `**Pull requests**` section without disturbing existing content" behavior, which isn't a generic `manage-github-issue` operation, this is a project-specific variant of issue-body editing, not an accidental duplication:

  ```
  **Pull requests**

  https://github.com/OWNER/REPO/pull/N, <short description>, <merged|open|draft>
  ```

  Fetch the current body first, never overwrite existing content:

  ```bash
  gh issue view <issue-number> --repo OWNER/REPO --json body --jq .body
  ```

  Append the new line (adding the `**Pull requests**` heading if it doesn't exist yet, or a new line under it if it does), then write the full body back:

  ```bash
  gh issue edit <issue-number> --repo OWNER/REPO --body-file <tempfile-with-full-new-body>
  ```

  Show the complete new body to the user before running `issue edit` and get approval, `gh issue edit --body-file` is a full-body overwrite at the API level even though it reads as an append to the user.
- **Optional, not default**: `gh pr edit <PR#> --add-project "<Board Title>"` adds the PR itself as a board item. The reference board never does this (all items are issues, zero are PRs). Only do this if the user explicitly asks.

### 9. Mark Done

Never infer `Done` just because a PR exists or is open. Confirm it actually merged:

```bash
gh pr view <PR#> --repo OWNER/REPO --json state,mergedAt
```

Only after `state == MERGED` (or the user explicitly confirms completion some other way), set `Status` to `Done` via `item-edit`. If the closing PR already auto-closed the issue, check first:

```bash
gh issue view <issue-number> --repo OWNER/REPO --json state,closed
```

### 10. Verify linkage (optional)

To confirm an issue and its PR(s) are actually connected before reporting a step complete, use a GraphQL query against `timelineItems(itemTypes:[CROSS_REFERENCED_EVENT])` on the issue, this is the only reliable way to see linked PRs regardless of how the link was created:

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $number: Int!) {
    repository(owner: $owner, name: $repo) {
      issue(number: $number) {
        timelineItems(itemTypes: [CROSS_REFERENCED_EVENT], first: 50) {
          nodes {
            ... on CrossReferencedEvent {
              source {
                ... on PullRequest {
                  url
                  state
                }
              }
            }
          }
        }
      }
    }
  }' -f owner=OWNER -f repo=REPO -F number=<issue-number>
```

`gh issue develop --list <issue-number> --repo OWNER/REPO` only lists linked *branches*, not PRs, don't use it to verify PR linkage, it's a narrower, different check.

## Optional: native sub-issues

`gh` supports GitHub's native parent/sub-issue relationship:

```bash
gh issue create --title "<child title>" --parent <parent-number-or-url>
gh issue edit <parent> --add-sub-issue <child>
```

The reference board doesn't use this, every item is a flat issue with prose dependency notes and manual row ordering instead, so that's the default. Only use native sub-issues if the user explicitly opts in for a given plan.

## Rules

- Run the Auth Preflight (Phase 2) first, every time. If the `project` scope is missing, tell the user to run `gh auth refresh -s project,read:project` and stop. Never proceed with a partial or read-only workaround instead.
- Always preview the full set of issues (title, body, dependency notes, assignee, status) and get explicit user approval before creating anything.
- Never hardcode `Status` option names or field/option IDs. Look them up per-board with `field-list`/`item-list` every time, they can differ across projects.
- Verify `gh project item-edit`'s exact required flags against `gh project item-edit --help` at run time before using it, the flag set has changed across `gh` versions and a wrong guess here fails silently in unhelpful ways.
- Default to flat issues with prose dependency notes and manual row order, matching observed board practice, not GitHub's native sub-issues feature. Only use sub-issues if the user explicitly opts in.
- Same-repo PR-to-issue linkage is automatic via closing keywords, don't add extra steps for it. Cross-repo linkage is manual and append-only, never overwrite existing issue body content when adding the `**Pull requests**` section.
- Never mark an item `Done` without confirming the PR actually merged, or the user explicitly confirming completion another way.
- PRs are not added to the project board as items by default. Only do it if the user explicitly asks.
- On any command failure: show the exact command and exact error, stop, and ask the user. Never silently retry, skip, or fall back.
- No remote mutation (issue create, item-add, item-edit, issue edit) without explicit user approval of the preview shown in Phase 4 or Phase 8.
- Follow `~/.config/agentic/instructions/communication.md` for tone in issue bodies and summaries, `~/.config/agentic/instructions/versioning.md` for git-adjacent conventions, and `~/.config/agentic/instructions/standards.md` for the "Stop the Line" and error-handling behavior this skill applies throughout.
