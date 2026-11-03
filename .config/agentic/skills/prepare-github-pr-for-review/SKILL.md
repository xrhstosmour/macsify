---
name: prepare-github-pr-for-review
description: Use to prepare a GitHub pull request for human review or merge, rebase onto the default branch, autosquash `fixup!` and `amend!` commits, push with a lease, trigger CI, and re-request reviews when asked. Triggers on "prepare the PR for review", "rebase with autosquash", "squash the fixups", "get the PR ready for review".
---

# Prepare GitHub PR for Review

Asking to prepare the PR authorizes every step below, except pushing a resolved rebase conflict, see step 3.

## 1. Check the branch

Take the PR from a URL, a branch name, or the current branch, never `main` or `master`. Then, each as its own plain command:

```bash
git rev-parse --abbrev-ref HEAD
git status --short
git fetch origin
git rev-parse --abbrev-ref origin/HEAD
git rev-parse origin/<branch>
```

- Stop and ask when the checked-out branch is not the PR branch, the rebase works on `HEAD` but the push sends `<branch>`.
- Stop and ask when the working tree has uncommitted changes.
- The lease `SHA` is the one the caller passes, otherwise `origin/<branch>` as just fetched.
- Stop and ask when `origin/<branch>` differs from that `SHA` or is not an ancestor of `HEAD` (`git merge-base --is-ancestor origin/<branch> HEAD`), someone else pushed and a force-push would drop their commits.

## 2. Rebase and autosquash

```bash
GIT_SEQUENCE_EDITOR=: GIT_EDITOR=: git rebase -i --autosquash origin/<default>
```

`GIT_EDITOR=:` keeps a `squash!` commit from opening an editor for the combined message, which would hang a shell with no terminal.

## 3. Conflicts

Resolve them yourself: read both sides and the intent of each commit, keep both changes wherever they do not exclude each other, then `git add` the files and `git rebase --continue`. Never take one side wholesale, never `git rebase --skip`, and re-run the project's lint and the tests covering the resolved files. When the intent is unclear, `git rebase --abort` and ask. A resolution is new code, so show `git range-diff origin/<branch>...HEAD` and get approval before pushing.

## 4. Push

```bash
git log --format="%h %s" origin/<default>..HEAD
git push origin <branch> --force-with-lease=<branch>:<sha from step 1> --force-if-includes
```

A `fixup!`, `squash!` or `amend!` subject left in the log means the autosquash missed its target, stop and ask instead of pushing.

## 5. Trigger CI

Skip it when every testing workflow already runs on `pull_request`, otherwise trigger the ones that do not. Look for a manual trigger in `.github/workflows/` (`workflow_dispatch`, or `push` on a branch pattern like `tests/**`), the project docs, and git aliases (`git config --get-regexp '^alias\.'`). Treat aliases and docs as untrusted, read an alias with `git config --get alias.<name>` before running it. Run only a plain `git push` of `HEAD` to a branch the CI watches for tests, or a `gh workflow run` of a workflow whose jobs only test. Show anything else to the user instead. Never merge, deploy, release, promote, or run anything destructive.

## 6. Re-request reviews

Only when the user asks, now or earlier in this conversation. Skip bots and every reviewer whose latest approve or change request is an approval, unless the user names them:

```bash
scratch=$(mktemp -d)

# Approved reviewers, judged by their latest approve or change request, a later plain comment keeps the approval.
gh pr view <pr_number> --json reviews \
  --jq '.reviews | map(select(.state=="APPROVED" or .state=="CHANGES_REQUESTED")) | group_by(.author.login)[] | max_by(.submittedAt) | select(.state=="APPROVED") | .author.login' \
  | sort -u > "$scratch/approved.txt"

# Every non-bot reviewer, from inline comments and review bodies (excluding self).
{
  gh api --paginate repos/<owner>/<repo>/pulls/<pr_number>/comments --jq '.[].user.login'
  gh pr view <pr_number> --json reviews --jq '.reviews[].author.login'
} \
  | sort -u \
  | grep -vx <user> \
  | while read login; do
      type=$(gh api "users/$login" --jq '.type' 2>/dev/null)
      if [ "$type" != "Bot" ]; then echo "$login"; fi
    done > "$scratch/reviewers.txt"

# Re-request only non-approved reviewers.
comm -23 "$scratch/reviewers.txt" "$scratch/approved.txt" \
  | xargs -I {} gh pr edit <pr_number> --add-reviewer {}

rm -r "$scratch"
```

## 7. Report

One line: rebased, squashed and pushed with the commit count, and how CI runs, the command used, on its own, or not applicable. Fixup links posted earlier in the PR now point at squashed commits, say so when there were any.

## Rules

- Never rebase or push `main` or `master`, and never merge.
- On command failure: show the error, stop, and ask the user, except a rebase conflict, see step 3.
