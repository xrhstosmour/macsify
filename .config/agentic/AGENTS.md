# AGENTS.md

## Identity

You are an expert developer. If the active project has AI config files (`AGENTS.md`, `CLAUDE.md`, `CODEX.md`, `.agents/**/*.md`, `.github/copilot-instructions.md`, `.github/copilot/**/*.md`, etc.), load them immediately and treat them as higher priority than this global configuration while still applying the hard rules, instructions, and tools defined here. For complex or multi-step tasks, orchestration rules are defined in the active agent configuration.

## Hard Rules

The files in `~/.config/agentic/instructions/` are your source of truth. `Claude Code` and `OpenCode` load them automatically, follow them without re-opening, in any other tool open the matching file first. Do not work from memory when a file exists for the topic.
A request to review a PR starts with the `review-github-pr` skill, never `gh pr view` or `gh pr diff`, including re-review phrases when a PR is the subject.

## Search: qmd or rg

Pick the tool by what the question is about.

- Code, symbols, call sites, config, and file contents of the current project: use `rg`, Grep, and Glob, never `qmd`.
- Knowledge, business rules, domain facts, decisions and their why, documentation, notes, how a process works: use `qmd` first, `qmd collection list` shows the indexed knowledge bases. Do not `rg` or `find` the filesystem for what a collection covers, use `rg` as the fallback only when no collection covers it, such as a project's own docs.
- Both: take the rule from `qmd`, then confirm it in code with `rg`. Code wins on conflict, say so.

`qmd` usage, keep output small, never read whole files:

- IDs, codes, names: `qmd search "<terms>" -n 3 --line-numbers 2>/dev/null`
- A question in words: `qmd query "<question>" -n 4 --files 2>&1 | grep '^#' | cut -c1-110`, the `grep` is required, a spinner floods stdout otherwise.
- Narrow with `-c <collection>`, read a hit with `qmd get qmd://<collection>/<path>:<line> -l 20 2>/dev/null`.
- Not found means say so, never guess.

## Compact instructions

When compacting, keep modified files, failing tests with their output, open decisions, and the user's latest explicit instructions.
