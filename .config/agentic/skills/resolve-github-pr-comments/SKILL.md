---
name: resolve-github-pr-comments
description: Review GitHub PR review comments, assess validity, propose or make fixes, create fixup commits, push, and reply with SHA links.
---

<!-- markdownlint-disable MD013 -->

# Resolve GitHub PR Comments

## When to use

- `/resolve-github-pr-comments <pr_url>`
- User says "resolve pr comments" or "fix pr comments".
- The user mentions there are review comments to address on an open PR.
- The user says "there's feedback on my PR", "reviewer left comments", or "I got a review".
- The user is on a PR branch and asks to "handle the review" or "address the comments".

## 0. Resolve the PR

If the user provides a GitHub PR URL, extract `owner`, `repo`, and `pr_number`:

```text
# From URL: https://github.com/<owner>/<repo>/pull/<number>
```

If the user provides a branch name, fetch it:

```bash
gh pr view <branch> --json number,title,body,headRepository,url
```

If no URL or branch given, check if the current branch is a PR branch (not master/main):

```bash
git branch --show-current
```

If on `master` or `main`, stop and ask the user for a PR URL or branch name.
Otherwise, proceed using the current branch:

```bash
gh pr view --json number,title,body,headRepository,url
```

Store `owner/repo/pr_number`.

## 1. Prepare

1. Fetch `PR` metadata:

   ```bash
   gh pr view <pr_number> --repo <owner>/<repo> --json number,headRepository,url,title
   ```

2. Extract `owner/repo/pr_number`
3. Fetch review threads:

   ```bash
   gh api graphql --method POST -f query='query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100){nodes{id,isResolved,comments(first:50){nodes{databaseId,author{login},body,createdAt,path,line,originalCommit{oid}}}}}}}}' -F owner=<owner> -F repo=<repo> -F number=<pr_number>
   ```

4. Fetch standalone PR comments:

   ```bash
   gh api repos/<owner>/<repo>/issues/<pr_number>/comments --jq '.[] | {id, user: .user.login, body, created_at, node_id}'
   ```

5. Filter comments:
   - Review threads: `isResolved == false` AND there is no reply from this agent (treat bot authors like any other author for review threads).
   - Standalone comments: no reply from this agent AND the author is not a bot. Bot standalone comments are skipped: do not reply, react, or resolve.

   ```bash
   # Check replies to review comment.
   gh api "repos/<owner>/<repo>/pulls/<pr_number>/comments" --jq '.[] | select(.id==<databaseId>) | ._links.self.href' | xargs -I {} gh api "{}/replies" --jq '.[] | select(.user.login=="<user>")'
   # Check replies to standalone comment.
   gh api "repos/<owner>/<repo>/issues/comments/<id>/replies" --jq '.[] | select(.user.login=="<user>")'
   ```

## 2. Assess

For each comment, present (author, date, `file:line`, content) and assess:

- VALID: Include a concise fix approach and the target `SHA` (the target commit must be within `<base>..HEAD`).
- NOT VALID: Include a concise reason why no code change is required.

Always map each VALID comment to a target `SHA` before making code changes. If mapping is unclear, pause and ask the user for clarification.

Group results as follows:

```text
VALID (N):
#1: @author <file>:<line> -> fixup of `SHA`
#2: @author <file>:<line> -> fixup of `SHA`

NOT VALID (N):
#3: @author - <reason>
```

Get explicit user confirmation before proceeding with code changes.

## 3. Batch Reactions

Add reactions to acknowledge comments:

```bash
# Review comments.
echo '{"content":"+1"}' | gh api "repos/<owner>/<repo>/pulls/comments/<id>/reactions" -X POST -H "Accept: application/vnd.github+json" --input -
# Review comments which are not valid.
echo '{"content":"eyes"}' | gh api "repos/<owner>/<repo>/pulls/comments/<id>/reactions" -X POST -H "Accept: application/vnd.github+json" --input -
# Standalone comments.
echo '{"content":"+1"}' | gh api "repos/<owner>/<repo>/issues/comments/<id>/reactions" -X POST -H "Accept: application/vnd.github+json" --input -
```

Reaction policy:

- VALID review comments: React with `+1`.
- NOT VALID review comments: React with `eyes`.
- VALID standalone non-bot comments: React with `+1`.
- NOT VALID standalone non-bot comments: React with `eyes`.
- Bot standalone comments: Do not react.

Verification (required before Step 7/8):

```bash
# Review comment reaction check.
gh api repos/<owner>/<repo>/pulls/comments/<id>/reactions --jq '.[] | select(.user.login=="<user>") | .content'

# Standalone comment reaction check.
gh api repos/<owner>/<repo>/issues/comments/<id>/reactions --jq '.[] | select(.user.login=="<user>") | .content'
```

## 4. Make Changes

Step 3 reactions must be applied and verified before making any code changes.
If reactions are not applied, stop and return to Step 3.

For each VALID comment:

1. Edit relevant files to address the single comment (one comment → one focused change where possible).
2. Run lint/syntax checks and quick tests; address any failures immediately.
3. Present the changes (`file:line - preview`) to the user for review.
4. Obtain user approval before proceeding to the next change.

After all approved, show final fixup plan:

```text
#1: file1.ext -> fixup of abc123
#2: file2.ext -> fixup of def456
```

Group changes by target `SHA` and make sure each file goes to the correct fixup commit.
Get user confirmation to commit.

## 5. Batch Commit

Create fixup commits locally first. Do NOT push until the user explicitly approves.
Resolve target `SHA`s from the current branch history, and group changes by target `SHA`.
Never mix different target `SHA`s in a single fixup commit.
For further details, re-read `~/.config/agentic/instructions/versioning.md` in full before committing.

```bash
# Example: create fixup commits grouped by target SHA
git add <files_for_sha1> && git commit --fixup <sha1>
git add <files_for_sha2> && git commit --fixup <sha2>
```

Before each fixup commit, verify staged files belong only to that SHA group:

```bash
git diff --cached --name-only
```

Verify:

```bash
git status --short && git log --oneline <base>..HEAD
```

Get user confirmation to push.

## 6. Push

```bash
git push origin <branch> --force-with-lease
```

After push, verify the remote branch contains the fixup commits before posting any PR replies:

```bash
# Local latest commits, newest first.
git log --format="%H %s" -n <valid_count>

# Remote head includes latest local commits.
git fetch origin <branch>
git rev-parse HEAD
git rev-parse origin/<branch>

# Optional strict check: each fixup SHA exists on remote branch.
git branch -r --contains <fixup_sha> | grep "origin/<branch>"
```

## 7. Post Valid

Before posting any valid-comment reply, ensure Step 3 reactions were applied and verified, and Step 6 push was completed and verified. If the push has not occurred, stop and ask for push approval.

Collect all new fixup `SHA`s and verify mapping before replying. Do not assume one comment equals one fixup commit.

```bash
git log --format="%H %s" -n <fixup_commit_count>
```

Reply and resolve review thread comments (for both human and bot authors) by posting the fixup commit URL(s) and then resolving the thread. For standalone comments from non-bot authors, post a quoted reply including fixup SHA(s). Skip bot standalone comments (no reply, no resolve).

```bash
echo '{"body":"https://github.com/<owner>/<repo>/commit/<sha>"}' | gh api "repos/<owner>/<repo>/pulls/<pr_number>/comments/<id>/replies" -X POST -H "Accept: application/vnd.github+json" --input -
echo '{"body":"> <original_comment_text>\n\nhttps://github.com/<owner>/<repo>/commit/<sha>"}' | gh api "repos/<owner>/<repo>/issues/comments/<id>/replies" -X POST -H "Accept: application/vnd.github+json" --input -
```

Resolve review threads, after replying:

```bash
gh api graphql -f query='mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{isResolved}}}' -F threadId=<thread_id>
```

## 8. Post Not Valid

Before posting or resolving any not-valid thread, ensure Step 3 reactions were applied and verified, and Step 6 push was completed and verified. If the push has not happened yet, stop and ask for push approval.

For review thread comments from any author: Reply with concise reason + resolve.
For standalone comments from non-bot authors only: Quote reply with reason. Bot standalones are skipped, no reply, no resolve.

```bash
# Review thread comment, reply with reason + resolve, for both human and bot review comments.
echo '{"body":"<reason>"}' | gh api "repos/<owner>/<repo>/pulls/<pr_number>/comments/<id>/replies" -X POST -H "Accept: application/vnd.github+json" --input -
gh api graphql -f query='mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{isResolved}}}' -F threadId=<thread_id>
# Standalone comment, non-bot only, quote reply with reason, no resolve.
echo '{"body":"> <original_comment_text>\n\n<reason>"}' | gh api "repos/<owner>/<repo>/issues/comments/<id>/replies" -X POST -H "Accept: application/vnd.github+json" --input -
```

## 9. Finish

1. Re-request reviews (skip reviewers who already approved, and skip bots):

   ```bash
   # Get approved reviewers.
   gh pr view <pr_number> --json reviews \
     --jq '.reviews[] | select(.state=="APPROVED") | .author.login' \
     | sort -u > /tmp/approved.txt

   # Get all non-bot reviewers who commented (excluding self).
   gh api repos/<owner>/<repo>/pulls/<pr_number>/comments \
     --jq '.[].user.login' \
     | sort -u \
     | grep -v <user> \
     | while read login; do
         type=$(gh api "users/$login" --jq '.type' 2>/dev/null)
         if [ "$type" != "Bot" ]; then echo "$login"; fi
       done > /tmp/reviewers.txt

   # Re-request only non-approved reviewers.
   comm -23 /tmp/reviewers.txt /tmp/approved.txt \
     | xargs -I {} gh pr edit <pr_number> --add-reviewer {}

   rm /tmp/approved.txt /tmp/reviewers.txt
   ```

2. Summary: `PR` link, resolved `SHA`s, not-valid reasons

## Rules

- No remote actions without user approval.
- Create fixup commits locally, show them to the user first, and get approval before pushing.
- Never reply/resolve PR comments before fixup commits are pushed and verified on the remote branch.
- Reactions are mandatory: `+1` for valid, `eyes` for not valid, except for bot standalone comments.
- Verify reactions exist before posting any reply or resolve actions.
- Reply to review comments (not the PR body) when applicable.
- On command failure: show the error, stop, and ask the user.
- For valid comments: reply with just the SHA URL(s), no extra text.
- For not-valid comments: reply with a concise reason.
