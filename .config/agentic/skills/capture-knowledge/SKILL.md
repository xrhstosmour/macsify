---
name: capture-knowledge
description: >
  Add knowledge to an external knowledge repository, scrubbing sensitive data, from the
  conversation or by mining the sources the repository declares. Two profiles, shareable,
  a generalized second brain with a branch and PR, and private, domain-specific with PII and
  credentials scrubbed only and no PR. Use for "capture knowledge", "update second brain",
  "save this to my notes", "refresh the knowledge base", "mine new knowledge", with a
  target path.
---

# Capture Knowledge

## Purpose

Turn something learned or built in this conversation, or found in the target repository's declared sources, into durable notes in an external, git-tracked knowledge-base repository, without leaking anything sensitive into it.

Never trigger this automatically at the end of a task. It is a deliberate, user-initiated action, judging what is worth remembering is the step that needs a human in the loop.

## Profile

Read the target repository's `README.md` or `AGENTS.md` for a line `Profile: private` or `Profile: shareable`, default shareable. Confirm the profile with the user before writing, a wrong profile leaks names.

- shareable: a generalized second brain that may be shared. Generalize every note, step 6 applies in full, step 8 opens a PR.
- private: an internal domain knowledge base where employer, product, and system names are the content. Keep them. Step 6 applies only the always-scrub list. Step 8 does not push or open a PR, commit only when the user asks.

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

From this conversation, pull out concrete, reusable knowledge: a pattern, a gotcha, a workflow, a decision and its reasoning, a checklist. Shareable profile: generalizable only, leave out anything that only makes sense tied to this specific task, project, or repository. Private profile: domain rules and decisions are wanted, each with a source pointer as the repository's conventions define. If nothing in the conversation clears the bar, say so and stop, don't force a low-value note into the repository.

## 6. Mandatory sensitive-data scrub

This applies regardless of whether the target repository's own rules mention it, and even if it has no rules file at all.

Always scrub, both profiles. Never write:

- Real credentials: passwords, API keys, tokens, private keys, license keys. If one is seen in a source, record only where, and tell the user to rotate it.
- Personal data of third parties, employees, and customers: real names, emails, phone numbers, addresses, usernames. Refer to people by role and to customers by ID only, per `~/.config/agentic/instructions/privacy.md`.

Shareable profile also never writes: real hostnames, IP addresses, internal domain names, employer, client, product, or project codenames, internal tool or service names tied to a specific employer. Generalize the underlying technique and drop or placeholder identifying specifics.

If something can't be safely generalized or redacted, leave it out entirely rather than partially redact it. Before committing, `grep -ril` the new or changed files for anything you're unsure about as a final check.

## 7. Write the notes

Create or extend files per the conventions learned in step 3. Keep each note atomic and matched to the granularity of its neighbors in that repository.

If the target repository has an append-only log/changelog convention (e.g. `LOG.md`), add one entry following its existing format. Skip this if no such file exists, don't invent one.

## 8. Branch, commit, PR

Private profile: stop after step 7 and step 9, leave the changes uncommitted, commit only when the user asks, never push or open a PR. Shareable profile follows `~/.config/agentic/instructions/versioning.md`:

1. Create a feature branch, never commit to `main`/`master` directly.
2. Stage only the files this skill created or intentionally edited, never a broad `git add -A`/`git add .` in a repository that may have unrelated pending changes.
3. Split commits by topic, matching that repository's own commit style if evident from `git log`, otherwise the standard convention.
4. Re-run the sensitive-data scrub across the full diff (`git diff <base>..HEAD`) as a last check before pushing.
5. Invoke the `manage-github-pr` skill to open the PR, don't run `gh pr create` directly.
6. Show the commit plan and PR body to the user before pushing anything. Never merge without the user explicitly asking.

## 9. Re-index

If the target repository is a qmd collection, as `qmd collection list` shows, run `qmd update` then `qmd embed` after writing, report any failure, and `qmd search` once for a fact you added. Run the repository's own verification sweeps if its README lists any.

## Mining mode

Use this when the user asks to refresh or mine the repository instead of capturing the conversation. The target repository's `README.md` must declare a `Sources` section, what to read and how, and a `Runs` log. If either is missing, stop and ask. Run steps 1 to 3 first, then:

1. Since date: the newest entry in the repository's `Runs` log, none means the range the README names.
2. Launch one read-only agent per declared source in parallel, each given the since date, the repository's conventions, and the step 6 scrub. Each writes redacted notes to the scratchpad as `rule or decision | why | source pointer` and replies in under 150 words with counts and gaps. Resume the same agent with `SendMessage` for follow-up rounds, stop when a round adds little.
3. Merge by steps 3, 4, 7: dedupe against existing notes first, fix lines that new evidence corrects, flag conflicts instead of picking a side, keep the repository's size and format limits.
4. Run step 6, append a `Runs` entry with the date, what was mined, counts, and remaining gaps, then run steps 8 and 9.
5. Report facts added, open conflicts, unmined sources, and any credential seen that needs rotating.

## Guardrails

- Always propose before writing in conversation mode, show what will be captured before touching the target repository. Misjudging "generalizable enough" is the actual failure mode this skill exists to prevent.
- Never fabricate content to pad a thin capture, a short accurate note beats a longer invented one.
- If the target repository's conventions conflict with something in this skill, the target repository's own `AGENTS.md`/`CLAUDE.md` wins for style/taxonomy, the always-scrub list in step 6 always wins regardless.
- Never stage or commit a file this skill didn't intentionally create or edit, even if `git status` shows it as modified, unrelated pending changes are not this skill's to touch.
