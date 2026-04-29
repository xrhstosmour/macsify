---
name: resolve-pr-comments
description: Review PR review comments, assess validity, make fixes, create fixup commits, push, reply with SHA links.
---

# Resolve PR Comments

Recommended model `github-copilot/gpt-5.4-mini`

## When to use

"resolve pr comments" / "fix pr comments" / "/resolve <pr_url>"

## 1. Prepare

1. Fetch `PR`:
   ```bash
   gh pr view --json number,headRepository,url,title
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
   - Review threads: isResolved=false AND no reply from you AND author is not bot (except Copilot)
   - Standalone: no reply from you AND author is not bot (except Copilot)
   ```bash
   # Check replies to review comment.
   gh api "repos/<owner>/<repo>/pulls/<pr_number>/comments" --jq '.[] | select(.id==<databaseId>) | ._links.self.href' | xargs -I {} gh api "{}/replies" --jq '.[] | select(.user.login=="<user>")'
   # Check replies to standalone comment.
   gh api "repos/<owner>/<repo>/issues/comments/<id>/replies" --jq '.[] | select(.user.login=="<user>")'
   ```

## 2. Assess

For each comment, show (author, date, file:line, content) and assess:

- [VALID] + fix approach + target `SHA` (must be in `<base>..HEAD`)
- [NOT VALID] + reason

Group results:

```
VALID (N):
#1: @author <file>:<line> -> fixup of `SHA`
#2: @author <file>:<line> -> fixup of `SHA`

NOT VALID (N):
#3: @author - <reason>
```

Get user confirmation before proceeding.

## 3. Batch Reactions

Add reactions to acknowledge:

```bash
# Review comments.
echo '{"content":"+1"}' | gh api "repos/<owner>/<repo>/pulls/comments/<id>/reactions" -X POST -H "Accept: application/vnd.github+json" --input -
# Review comments which are not valid.
echo '{"content":"eyes"}' | gh api "repos/<owner>/<repo>/pulls/comments/<id>/reactions" -X POST -H "Accept: application/vnd.github+json" --input -
# Standalone comments.
echo '{"content":"+1"}' | gh api "repos/<owner>/<repo>/issues/comments/<id>/reactions" -X POST -H "Accept: application/vnd.github+json" --input -
```

## 4. Make Changes

For each VALID comment:

1. Read relevant files, make changes for THIS comment only
2. Run lint/syntax check, ensure code still works as before, fix any logic or indentation errors immediately
3. Show changes: `file:line - preview`
4. Get user approval before next

After all approved, show final fixup plan:

```
#1: file1.ex -> fixup of abc123
#2: file2.ex -> fixup of def456
```

Group changes by target `SHA` and make sure each file goes to the correct fixup commit.
Get user confirmation to commit.

## 5. Batch Commit

Create commits locally first. Do NOT push until user explicitly approves.
Commit each fixup in comment order. One fixup per original commit.
If a comment touches files from different commits, split into multiple fixups.

```bash
# Comment #1.
git add <file1> && git commit --fixup <sha1>

# Comment #2.
git add <file2> && git commit --fixup <sha2>
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

## 7. Post Valid

Get all new `SHA`s and verify mapping before replying.
Commits are returned newest-first, reverse to match comment order (oldest fixup = comment #1).
Always cross-check each `SHA` against its fixup message (`git log --oneline`) before mapping to a comment.

```bash
git log --format="%H %s" -n <valid_count>
```

Reply with just the SHA URL(s), comma-separated for multiple. For standalone comments, quote the original comment above your reply:

```bash
# Review thread comment.
echo '{"body":"https://github.com/<owner>/<repo>/commit/<sha>"}' | gh api "repos/<owner>/<repo>/pulls/<pr_number>/comments/<id>/replies" -X POST -H "Accept: application/vnd.github+json" --input -
# Standalone comment, which will be answered with quote reply.
echo '{"body":"> <original_comment_text>\n\nhttps://github.com/<owner>/<repo>/commit/<sha>"}' | gh api "repos/<owner>/<repo>/issues/comments/<id>/replies" -X POST -H "Accept: application/vnd.github+json" --input -
```

Resolve review threads:

```bash
gh api graphql -f query='mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{isResolved}}}' -F threadId=<thread_id>
```

## 8. Post Not Valid

For each NOT VALID comment, reply with concise reason only. For standalone comments, quote the original comment above your reply:

```bash
# Review thread comment.
echo '{"body":"<reason>"}' | gh api "repos/<owner>/<repo>/pulls/<pr_number>/comments/<id>/replies" -X POST -H "Accept: application/vnd.github+json" --input -
gh api graphql -f query='mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{isResolved}}}' -F threadId=<thread_id>
# Standalone comment, which will be answered with quote reply.
echo '{"body":"> <original_comment_text>\n\n<reason>"}' | gh api "repos/<owner>/<repo>/issues/comments/<id>/replies" -X POST -H "Accept: application/vnd.github+json" --input -
```

## 9. Finish

1. Re-request reviews (skip reviewers who already approved):
   ```bash
   # Get approved reviewers.
   gh pr view <pr_number> --json reviews \
     --jq '.reviews[] | select(.state=="APPROVED") | .author.login' \
     | sort -u > /tmp/approved.txt

   # Get all reviewers who commented (excluding self and bots).
   gh api repos/<owner>/<repo>/pulls/<pr_number>/comments \
     --jq '.[].user.login' \
     | sort -u \
     | grep -v bot \
     | grep -v <user> > /tmp/reviewers.txt

   # Re-request only non-approved reviewers.
   comm -23 /tmp/reviewers.txt /tmp/approved.txt \
     | xargs -I {} gh pr edit <pr_number> --add-reviewer {}

   rm /tmp/approved.txt /tmp/reviewers.txt
   ```
2. Summary: `PR` link, resolved `SHA`s, not-valid reasons

## Rules

- No remote actions without user approval
- Create fixup commits locally, show them to user first and get approval before pushing
- Reply to review comments, not `PR` body
- On command failure: show error, stop, ask user
- Commit order must match comment order for correct `SHA` mapping
- Reply with just the SHA URL(s), no extra text for valid comments
- Reply with concise reason for not valid comments
