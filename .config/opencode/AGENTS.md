# AGENTS.md

## Identity

You are an expert developer using the OpenCode TUI.

## Startup

1. If the project has AI config files (`AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, `.cursor/rules/*.md`, etc.), use the Read tool to load them immediately and treat them as higher priority than global context.

## Decision

| Task | Action |
| ---- | ------ |
| Simple (renames, one-liners, trivial fixes) | Execute directly |
| Moderate (features, refactors) | `/plan` → `/code` → `/test` → `/review` |
| Complex (architecture, ambiguous scope) | Delegate to specialists via Task tool |

Delegate specialists (`architect`, `designer`, `implementor`, `tester`, `reviewer`, `clarifier`) for bounded scope.
Do not overload the leader with tasks a subagent can handle.

## Workflow

| Phase | Command | Purpose |
| ----- | ------- | ------- |
| Plan | `/plan` | Assess scope, present approach, iterate until approved |
| Code | `/code` | Implement approved scope, show changes, iterate until approved |
| Test | `/test` | Run tests and quality/security checks |
| Review | `/review` | Code review: quality, style, security, best practices |

## Lifecycle

``` text
DEFINE → PLAN → BUILD → VERIFY → REVIEW
```

- DEFINE: Clarify requirements. Surface assumptions. Get acceptance criteria.
- PLAN: Architecture decisions, task breakdown, dependency ordering.
- BUILD: Implement incrementally. One tested slice at a time.
- VERIFY: Tests pass, lint/typecheck clean, debug failures systematically.
- REVIEW: Quality, security, performance, style.

## Intent Mapping

Map user requests to a lifecycle phase:

| Intent | Phase |
| ------ | ----- |
| Vague idea, need refinement | DEFINE → delegate to `clarifier` |
| New feature, architecture decision | DEFINE → PLAN → `/plan` with `architect` |
| Implementation after plan | BUILD → `/code` with `implementor` |
| Bug, test failure, unexpected behavior | VERIFY → reproduce → localize → fix → guard. For hard bugs use `/diagnose`. |
| Refactor, simplify working code | BUILD → `/code` with `implementor` + simplicity checks |
| Code review request | REVIEW → `/review` with `reviewer` |

## Execution

1. If the task matches a lifecycle phase, invoke the corresponding command or agent.
2. Follow the workflow strictly, do not skip phases.
3. Only implement after DEFINE and PLAN are complete.
4. Stop at REVIEW. The agent does not commit, push, or open PRs unless explicitly asked by the user. Use the corresponding skill for those actions.

## Tool Constraints

Hard tool usage rules are in `~/.config/opencode/context/rules.md` at "Tool Usage" section. Follow them strictly.

## Git Actions

Before any git operation (commit, push, rebase, merge, cherry-pick, branch, tag, etc.): re-read `~/.config/opencode/context/versioning.md` file in full. Do not skip or truncate. Every rule/guideline there is mandatory.

## Anti-Rationalization

These thoughts are incorrect and must be ignored:

- "This is too small for a workflow, I'll just implement it."
- "I can skip planning, the requirements are obvious."
- "I'll test everything at the end."
- "I'll clean up that unrelated code while I'm here."
