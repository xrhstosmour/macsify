---
description: Multi-agent PR review. Fetches PR by URL or branch, spawns architect and reviewer agents in parallel, synthesizes findings, and can post inline comments.
---

# Review PR

Review a `PR` by URL or branch using the `review_pr` skill instructions. After the report, asks whether to post findings as inline comments on the `PR`.

## When to use

- `/review-pr <url_or_branch>`
- User says "review my PR", "review this PR", "review the PR", or "code review `<branch>`".
- A PR has been created and the user wants quality feedback before merging.
- The user asks "is this ready to merge?" or "is this PR good?".
- After `/create-pr` completes and the user wants a review pass.
