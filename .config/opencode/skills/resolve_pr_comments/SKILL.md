---
name: resolve_pr_comments
description: Review `PR` review comments, assess validity, plan fixes with user, make fixup commits, push, reply with `SHA` links and re-request reviews.
---

# Resolve PR Comments

## When To Use This Skill

Invoke this skill when the user says things like:

- "resolve pr comments"
- "fix pr comments"
- "/resolve <pr_url>"
- "/resolve (current branch's `PR` if exists)"

## Workflow

Follow these steps in order.

### Step 1 — Fetch comments

First, try to get the `PR` details from the current branch:
```bash
gh pr view --json number,headRepository,url
```

If there is an open `PR` for the current branch, extract owner, repo, and `PR` number from the response.
If no `PR` is found or user provides a `PR` URL, parse it to extract owner, repo, and `PR` number.
Fetch all review comments using `gh`:
```bash
gh api repos/<owner>/<repo>/pulls/<pr_number>/comments
```

Identify comments to review:
- Unresolved comments: Skip resolved threads, include ALL unresolved threads (including bot comments), group by thread if nested.
- Replies to our `SHA`s: Check BOTH unresolved AND resolved threads, look for new replies to comments we posted containing `SHA` links.

Present the list to user:
- Show total count of comments to review.
- For each: show author, date, and first 255 chars of content.
- Indicate if it is a new reply to our `SHA` post.
- Ask user to confirm to proceed.

### Step 2 — Review each comment

Display the full comment (author, date, content, file/line reference, original commit `SHA`).

Assess validity:
- Is this a legitimate request?
- Is it actionable (can be fixed in code)?
- Is it out of scope?
- Is it a duplicate of another comment?
- Is it already addressed by existing commits?

State your assessment to user:

If VALID:
```text
[VALID] Comment by @author on <file>:<line>

Assessment: This is a valid suggestion.
Proposed approach: <brief idea>

Should I proceed with planning a fix? (yes/no)
```

If NOT VALID:
```text
[NOT VALID] Comment by @author

Reason: <explain why not actionable>
- e.g., "Out of scope for this PR"
- e.g., "Won't fix because..."
- e.g., "This was already addressed in commit X"

Should I post a reply explaining this? (yes/no/reply-with-text)
```
If user approves posting the reply, mark thread as resolved after posting.

User can override your assessment if they disagree.

### Step 3 — Plan fix (if valid)

User approved fixing this comment.

Understand the comment fully:
- Read the full context.
- Check the referenced file(s) and line(s).
- Look at related code.

Propose an approach:
- Explain what changes are needed.
- Show which files will be modified.
- Outline the fixup commit message.

Discuss with user:
- Show proposed changes (use `git diff` or show code).
- Back-and-forth until user is satisfied.
- User can request modifications.

Final plan:
- Show finalized fixup commit message.
- Confirm ready to implement.

### Step 4 — Post fix

User gave final approval to proceed ("yes"/"proceed"/"go").

Make the code changes:
- Edit files as planned.
- Test if applicable.

Create and push fixup commit(s) as per `~/.config/opencode/context/versioning.md`.

If multiple fixup commits are needed, create each one separately.

Get the new `SHA`(s):
```bash
git log --format="%H" -n <number_of_fixups>
```

Post reply to the comment:
- Single `SHA`: `https://github.com/<owner>/<repo>/commit/<sha>`
- Multiple `SHA`s: join with ` & ` separator
```bash
gh api repos/<owner>/<repo>/pulls/comments/<comment_id>/replies \
  --field body="Fixed in: <sha_link_1> & <sha_link_2> & ..."
```

Mark the comment thread as resolved:
```bash
gh api repos/<owner>/<repo>/pulls/comments/<comment_id>/threads \
  --method PATCH \
  --field resolved=true
```

Confirm to user:
- Show the `SHA` link(s).
- Show the reply was posted.
- Show the thread was marked as resolved.
- Ask to continue to next comment or finish.

### Step 5 — Finish

When all comments have been processed, re-request reviews from reviewers who commented:
```bash
# Get list of reviewers who left unresolved comments.
gh api repos/<owner>/<repo>/pulls/<pr_number>/comments --jq '.[].user.login' | sort -u

# Re-request review from each reviewer.
gh pr review <pr_number> --request-reviewers <reviewer1> <reviewer2>
```

Provide a summary with links:
- `PR` link: `https://github.com/<owner>/<repo>/pull/<pr_number>`.
- List of resolved comments and their `SHA` links.
- List of not-valid comments with reasons (if any).
- List of reviewers re-requested.

Ask user if they want to do anything else.

## Rules

- Never perform any action (push, reply, resolve, re-request review) without explicit user approval.
- Always wait for user confirmation before executing commands that modify remote state.
