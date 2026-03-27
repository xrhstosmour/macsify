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
Fetch review threads with resolved state using `gh` via `GraphQL`:
```bash
gh api graphql -f query='\
query($owner:String!, $repo:String!, $number:Int!){\
  repository(owner:$owner,name:$repo){\
    pullRequest(number:$number){\
      reviewThreads(first:100){\
        nodes{\
          id\
          isResolved\
          comments(first:100){\
            nodes{\
              databaseId\
              author{login}\
              body\
              createdAt\
              path\
              line\
              originalCommit{oid}\
            }\
          }\
        }\
      }\
    }\
  }\
}' -F owner=<owner> -F repo=<repo> -F number=<pr_number>
```

Identify comments to review:
- Unresolved threads: include by default (including bot comments).
- Already addressed comments: skip when user/assistant already replied with `SHA` link(s) and no newer follow-up exists.
- Resolved bot threads: always skip (do not interfere).
- Resolved threads with follow-up: include only if there is a newer human follow-up after our `SHA` reply that requests further changes.

Present the list to user:
- Show total count of comments to review.
- For each: show author, date, and first 255 chars of content.
- Indicate if it is a new reply to our `SHA` post.
- Ask user to confirm to start review.
- Do not ask user to pick a batch of comments.

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

React to the review comment with thumbs up (not a new comment):
```bash
gh api "repos/<owner>/<repo>/pulls/comments/<comment_id>/reactions" -X POST -H "Accept: application/vnd.github+json" -F content='+1'
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

React to the review comment with eyes (not a new comment) until the not-valid reason is posted:
```bash
gh api "repos/<owner>/<repo>/pulls/comments/<comment_id>/reactions" -X POST -H "Accept: application/vnd.github+json" -F content='eyes'
```

If user approves posting the reply, post a reply and mark the thread as resolved after posting.

User can override your assessment if they disagree.

Iteration rule for Step 2:
- Process comments one by one, never as a batch.
- For each comment, always provide an explicit verdict: `[VALID]` or `[NOT VALID]`.
- Wait for user decision on that comment before moving to the next one.
- Do not skip validity assessment and jump directly to implementation.

### Step 3 — Plan fix (if valid)

User approved fixing this comment.

Iterate on the fix with the user:
- Understand the comment fully: read context, check referenced files/lines, look at related code.
- Make code changes locally.
- Show proposed changes to the user.
- Back-and-forth until user is satisfied with the changes.
- User can request modifications, and repeat until approved.

Once user approves the changes:
- Wait for explicit approval to proceed ("yes"/"proceed"/"go").

### Step 4 — Post fix

User gave explicit final approval to proceed.

Create fixup commit(s) with strict commit mapping:
- Build a mapping of each changed hunk to its introducing commit `SHA`.
- Use the comment `original_commit_id` when applicable.
- If needed, use `git blame` on changed lines to find the correct original commit.
- Group changes by original commit `SHA`.
- Create exactly one fixup commit per target original commit `SHA`.
- Never combine changes from different original commits into one fixup commit.
- Do not assume a single target commit. Verify every changed hunk first.
- Target only commits from the current feature branch/PR commit set.
- If a mapped commit is outside the current branch, remap it to the corresponding commit in this feature branch that introduced the PR change.
- If a valid review comment requests a genuinely new change that does not belong to any existing commit in this feature branch, create a new regular commit instead of a fixup commit.

Suggested flow:
```bash
# Inspect changed files/hunks and map each hunk to original commit `SHA`.
git diff

# Verify introducing commit per changed line/hunk.
git blame -L <start>,<end> <file>

# Restrict target commits to current `PR` branch commits.
git log --format="%H" <base_branch>..HEAD

# Stage only hunks for commit A.
git add -p <file_or_files>
git commit --fixup <original_commit_sha_A>

# Stage only hunks for commit B.
git add -p <file_or_files>
git commit --fixup <original_commit_sha_B>
```

Before pushing, report the fixup plan to user and wait for explicit approval:
- `original_commit_sha_A` -> `fixup_sha_A` -> files/hunks included
- `original_commit_sha_B` -> `fixup_sha_B` -> files/hunks included
- Proceed to push only after user confirms.

Mandatory pre-push check:
- Show a hunk-to-commit mapping table for all changed hunks.
- If two hunks map to different original commits, create separate fixup commits.
- If mapping is uncertain for any hunk, stop and ask user before committing.
- Confirm every target `SHA` is in `<base_branch>..HEAD` before creating fixup commits.
- If any hunk has no valid fixup target in `<base_branch>..HEAD`, classify it as new work and use a new regular commit (after user approval).

Push the fixup(s):
```bash
git push origin <current_branch> --force-with-lease
```

Get the new `SHA`(s):
```bash
git log --format="%H" -n <number_of_fixups>
```

Post a REPLY to the original comment (not a new comment):
- Single `SHA`: `https://github.com/<owner>/<repo>/commit/<sha>`
- Multiple `SHA`s: join with ` & ` separator
```bash
gh api "repos/<owner>/<repo>/pulls/<pr_number>/comments/<comment_id>/replies" -X POST -F body="<sha_link_1> & <sha_link_2> & ..."
```

For each resolved review comment, post the corresponding fixup `SHA` link(s) as a reply to that specific comment.

Mark the comment thread as resolved:
```bash
# 1) Find the review thread node ID that contains this comment ID
gh api graphql -f query='\
query($owner:String!, $repo:String!, $number:Int!){\
  repository(owner:$owner,name:$repo){\
    pullRequest(number:$number){\
      reviewThreads(first:100){\
        nodes{\
          id\
          comments(first:100){nodes{databaseId}}\
        }\
      }\
    }\
  }\
}' -F owner=<owner> -F repo=<repo> -F number=<pr_number>

# 2) Resolve the matching thread by node ID
gh api graphql -f query='\
mutation($threadId:ID!){\
  resolveReviewThread(input:{threadId:$threadId}){\
    thread{isResolved}\
  }\
}' -F threadId=<thread_node_id>
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
gh pr edit <pr_number> --add-reviewer <reviewer1> --add-reviewer <reviewer2>
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
- Post replies to existing comments, not new comments.
- Never create a mixed fixup commit that targets multiple original commits.
- Never claim a single-target fixup without showing verified hunk-to-commit mapping.
- Use fixup commits for changes tied to existing commits; use a new regular commit only for truly new work.
