---
name: resolve-pr-comments
description: Review PR review comments, assess validity, make fixes, create fixup commits, push, reply with SHA links.
---

# Resolve PR Comments

## When to use

"resolve pr comments" / "fix pr comments" / "/resolve <pr_url>"

## 1. Prepare

1. Fetch `PR`:
   ```bash
   gh pr view --json number,headRepository,url,title
   ```
2. Extract `owner/repo/pr_number`
3. Fetch comments:
   ```bash
   gh api graphql -f query='query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100){nodes{id,isResolved,comments(first:50){nodes{databaseId,author{login},body,createdAt,path,line,originalCommit{oid}}}}}}}}' -F owner=<owner> -F repo=<repo> -F number=<pr_number>
   ```
4. Filter: include unresolved, skip resolved bots + already addressed (`SHA` reply, no follow-up)

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

1. VALID: add `:+1` reaction to each
2. NOT VALID: add `:eyes` reaction to each

```bash
echo '{"content":"+1"}' | gh api "repos/<owner>/<repo>/pulls/comments/<id>/reactions" -X POST -H "Accept: application/vnd.github+json" --input -
echo '{"content":"eyes"}' | gh api "repos/<owner>/<repo>/pulls/comments/<id>/reactions" -X POST -H "Accept: application/vnd.github+json" --input -
```

## 4. Make Changes

For each VALID comment:

1. Read relevant files, make changes for THIS comment only
2. Show changes: `file:line - preview`
3. Get user approval before next

After all approved, show final fixup plan:

```
#1: file1.ex -> fixup of abc123
#2: file2.ex -> fixup of def456
```

Get user confirmation to commit.

## 5. Batch Commit

Commit each fixup in comment order:

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

Get all new `SHA`s (newest first, so reverse for oldest first = comment order):

```bash
git log --format="%H" -n <valid_count>
```

Reply to each VALID comment in order (SHA[n] = comment #n):

```bash
gh api "repos/<owner>/<repo>/pulls/<pr_number>/comments/<id1>/replies" -X POST -F body="https://github.com/<owner>/<repo>/commit/<sha1>"
gh api "repos/<owner>/<repo>/pulls/<pr_number>/comments/<id2>/replies" -X POST -F body="https://github.com/<owner>/<repo>/commit/<sha2>"
```

Resolve threads:

```bash
gh api graphql -f query='mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{isResolved}}}' -F threadId=<thread_id>
```

## 8. Post Not Valid

For each NOT VALID comment:

```bash
gh api "repos/<owner>/<repo>/pulls/<pr_number>/comments/<id>/replies" -X POST -F body="<reason>"
gh api graphql -f query='mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{isResolved}}}' -F threadId=<thread_id>
```

## 9. Finish

1. Re-request reviews:
   ```bash
   gh api repos/<owner>/<repo>/pulls/<pr_number>/comments --jq '.[].user.login' | sort -u | grep -v bot | grep -v <user>
   gh pr edit <pr_number> --add-reviewer <reviewer1> --add-reviewer ...
   ```
2. Summary: `PR` link, resolved `SHA`s, not-valid reasons

## Rules

- No remote actions without user approval
- Reply to review comments, not `PR` body
- On command failure: show error, stop, ask user
- Commit order must match comment order for correct `SHA` mapping
