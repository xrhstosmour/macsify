---
name: capture-knowledge
description: >
  Extract reusable knowledge from the conversation into an external second-brain notes
  repo, scrubbing sensitive data, then open a branch, commit, and PR, never pushing
  without approval. Use for "capture knowledge", "update second brain", "save this to
  my notes", with a target path.
---

# Capture Knowledge

## Purpose

Turn something learned or built in this conversation into a durable, generalized note in
an external, git-tracked knowledge-base repository ("second brain"), without leaking anything
proprietary or personal into it.

## When to use

- User says "capture knowledge", "update knowledge base", "update notes", "update second brain", "save this to my notes", "remember this for later", together with a target repository path.
- Never trigger this automatically at the end of a task. This is a deliberate, user-initiated action, not a silent background capture, judging what's "worth remembering" is exactly the step that needs a human in the loop.

## 1. Resolve the target repository

Use the path the user gave in their request. If no path was given, ask for one, don't guess or default to a repository mentioned earlier in the conversation for an unrelated reason.

```bash
test -d "<path>/.git" || echo "not a git repository"
```

If it's not a git repository, stop and ask.

## 2. Check for pre-existing uncommitted changes

```bash
git -C "<path>" status --short
```

If the working tree already has unstaged or untracked changes unrelated to this task, leave them alone entirely. Never `git add` a file you didn't write to, even partially, an existing modified file may contain the user's own in-progress work, or something sensitive that has nothing to do with this capture. Stage only the files this skill creates or intentionally edits.

## 3. Learn that repository's own conventions

Read, in order, whichever of these exist: `AGENTS.md`, `CLAUDE.md`, `.agents/**/*.md`,
`README.md`. Extract:

- Folder taxonomy, where does a new note belong
- File naming and metadata convention (frontmatter, tags, etc.)
- Cross-reference syntax between notes, if any
- Any explicit "how to add a note" or "sensitive data" rules already documented there

If none of these exist, default to: one topic per markdown file, descriptive filenames, group by subject in a sensibly named folder, don't invent more structure than the content needs.

## 4. Check for existing overlap

Before writing a new file, search the target repository for a near-duplicate on the same topic, `qmd search`/`qmd query` if that repository has it configured (see the `search-qmd-notes` skill), otherwise `grep -ri`. Extend or cross-link an existing note rather than duplicating it, matching that repository's own cross-reference syntax.

## 5. Extract what's actually worth keeping

From this conversation, pull out concrete, reusable, generalizable knowledge: a pattern, a gotcha, a workflow, a decision and its reasoning, a checklist. Leave out anything that only makes sense tied to this specific task, project, or repository. If nothing in the conversation clears that bar, say so and stop, don't force a low-value note into the repository.

## 6. Mandatory sensitive-data scrub

This applies regardless of whether the target repository's own rules mention it, and even if it has no rules file at all. Never write:

- Real credentials: passwords, API keys, tokens, private keys, license keys
- Real hostnames, IP addresses, internal domain names
- Employer, client, product, or project codenames
- Third-party personal data: real names, emails, phone numbers, usernames
- Internal tool/service names tied to a specific employer

Generalize the underlying technique and drop or placeholder identifying specifics. If something can't be safely generalized, leave it out entirely rather than partially redact it. Before committing, `grep -ril` the new/changed files for anything you're unsure about as a final check.

## 7. Write the notes

Create or extend files per the conventions learned in step 3. Keep each note atomic and matched to the granularity of its neighbors in that repository.

If the target repository has an append-only log/changelog convention (e.g. `LOG.md`), add one entry following its existing format. Skip this if no such file exists, don't invent one.

## 8. Branch, commit, PR

Follow `~/.config/agentic/instructions/versioning.md`:

1. Create a feature branch, never commit to `main`/`master` directly.
2. Stage only the files this skill created or intentionally edited, never a broad `git add -A`/`git add .` in a repository that may have unrelated pending changes.
3. Split commits by topic, matching that repository's own commit style if evident from `git log`, otherwise the standard convention.
4. Re-run the sensitive-data scrub across the full diff (`git diff <base>..HEAD`) as a last check before pushing.
5. Invoke the `manage-github-pr` skill to open the PR, don't run `gh pr create` directly.
6. Show the commit plan and PR body to the user before pushing anything. Never merge without the user explicitly asking.

## Guardrails

- Always propose before writing, show what will be captured before touching the target repository. Misjudging "generalizable enough" is the actual failure mode this skill exists to prevent.
- Never fabricate content to pad a thin capture, a short accurate note beats a longer invented one.
- If the target repository's conventions conflict with something in this skill, the target repository's own `AGENTS.md`/`CLAUDE.md` wins for style/taxonomy, the sensitive-data scrub in step 6 always wins regardless.
- Never stage or commit a file this skill didn't intentionally create or edit, even if `git status` shows it as modified, unrelated pending changes are not this skill's to touch.
