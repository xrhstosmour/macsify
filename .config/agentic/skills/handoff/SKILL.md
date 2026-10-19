---
name: handoff
description: >
  Compact the current conversation into a handoff document so another agent
  session can continue the work. Use when user wants to hand off work, save
  session state, or prepare context for a fresh agent session.
---

# Handoff

## When to use

- `/handoff`
- User says "handoff", "save context", or "prepare handoff".
- Context window is growing large and the user wants to continue in a fresh session.
- User is pausing work and wants to preserve state for a later session.
- User says "I need to switch context" or "summarize where we are".

Write a handoff document summarizing the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS, not the current workspace.

## Process

1. Summarize what has been accomplished so far.
2. Describe what remains to be done.
3. List any decisions made and their rationale.
4. Note any blockers or open questions.
5. Include relevant file paths, commands, and references.

## Rules

- Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.
- Redact any sensitive information, such as API keys, passwords, or personally identifiable information.
- Include a "suggested skills" section recommending which skills the next agent should invoke.
- If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
- Save to the OS temporary directory with a descriptive name: `<tmpdir>/handoff-<timestamp>.md`.
- Tell the user the absolute path of the saved file.
