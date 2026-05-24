---
description: Create a handoff document for another agent session to continue the work
---

# Handoff

Compact the current conversation into a handoff document so a fresh agent can continue the work.

## Entry Criteria

- User wants to preserve session state for another agent.
- User says "handoff", "save context", or "prepare handoff".

## Process

Follow the handoff skill:

1. Summarize accomplishments.
2. Describe remaining work.
3. List decisions and rationale.
4. Note blockers and open questions.
5. Include file paths, commands, and references.
6. Suggest skills for the next agent.
7. Save to OS temp directory, tell user the path.
