---
name: technical-analysis
description: Produce a structured technical analysis, method-level change list, notes, and conservative time estimates.
---

# Technical Analysis Skill

Analyze the user's feature request and produce a structured technical analysis document with method-level details, notes, and estimation.

## When to use

When the user describes a feature or change, or provides a link to a task, and asks for a "technical analysis", "analysis", "estimation", or "breakdown", use this skill.

## Format

Produce output in this exact structure:

```
### Technical Analysis:

1. <Subtask title and changes grouped by logical change>:
 - `<method_name>` at `<relative_file_path>`
 - `<method_name>` at `<relative_file_path>`

2. <Subtask title and changes grouped by logical change>:
 - `<method_name>` at `<relative_file_path>`

...

### Notes:

1. <Note>
2. <Note>

### Estimation:

  [ ] <Subtask title matching numbered item>: <workdays> day(s)
  [ ] <Subtask title matching numbered item>: <workdays> day(s)
  ...
  [ ] Full integration testing: <workdays> days
  [ ] Buffer for unknowns: <workdays> days

Implementation: <sum> workdays -> ~<weeks> weeks
Testing & buffer: <sum> workdays -> ~<weeks> weeks

Total: <sum> workdays -> ~<weeks> weeks -> ~<sprints> sprints
```

## Rules

1. Technical Analysis section: One numbered item per logical change group. Each item has sub-bullets with the exact method name in backticks and the relative file path.
2. Notes section: capture constraints, dependencies, side effects, and decisions that affect implementation.
3. Estimation section: Use `[ ]` (unchecked) so they can be marked done later. One bullet per numbered item above. Add test coverage into each item's estimate. Be conservative, better to finish early than late. Add separate bullets for "Full integration testing" and "Buffer for unknowns". Then split total into "Implementation" and "Testing & buffer" lines, then a "Total" line with workdays, weeks, and sprints.
4. Estimations must be safe: A single software engineer working without AI assistance should be able to complete the work within the estimated time. Do not assume AI tooling will speed anything up.

## Process

1. If given a link, fetch the resource first to extract requirements.
2. Ask clarifying questions to understand scope, boundaries, and any hard constraints.
3. Search the codebase for related methods, patterns, and files, trace the full flow end-to-end.
4. For each identified change point, note the exact method name and file path.
5. Group changes into logical numbered items.
6. Estimate each item in workdays (be conservative), adding test coverage time.
7. Present the result and iterate with the user until approved.
