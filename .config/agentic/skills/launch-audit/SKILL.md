---
name: launch-audit
description: >
  Read-only pre-launch audit of a whole repo, ranked into a one-week fix plan. Use for "/launch-audit", "are we ready to launch", "ready to deploy this big update".
---

# Launch Audit

A report, not a fix. No file is edited, no dependency is bumped, until the user approves the plan, then fixes go through the normal `/code` flow.

## 1. Map

Read only enough to brief the lanes, about 10 tool calls:

- The README, the build and deploy config, the dependency manifests and lockfiles, the entry points, routes, handlers, jobs, CLI commands, and where tests live.
- The expected load, one user running a script or many users at once, the lanes judge scale against it.
- The audit tool each ecosystem already supports, run nothing yet: `npm audit --omit=dev`, `pnpm audit`, `yarn audit` on Yarn 1 or `yarn npm audit --all --recursive --environment production` on Yarn 2 and later, `pip-audit -r requirements.txt` or `pip-audit .` for a `pyproject.toml` project, never bare `pip-audit`, it scans its own environment, `bundle audit`, `cargo audit`, `govulncheck ./...`, and `osv-scanner scan -r .` for `pub` and anything else, it reads `pubspec.lock`.
- The outdated check per ecosystem, run nothing yet: `npm outdated`, `pnpm outdated`, `yarn outdated`, `pip list --outdated`, `bundle outdated`, `cargo outdated`, `go list -u -m all`, `flutter pub outdated`. These show version drift only, never report one as a CVE check.

Write a brief of at most 15 lines: what the repo does, stack, load, entry points, test command, audit and outdated commands, and which `security-audit` references match the stack, per the table in its `references/README.md`. Every lane gets the same brief, no lane re-maps the repo.

## 2. Lanes

The lanes are exempt from the `leader` delegation cap, per its Phase Transition section. Without subagent support, run the lanes one after another in the main session with the same brief and rules.

Spawn all five in one message, in parallel, each a fresh read-only Explore subagent where the tool has one, otherwise the `reviewer`. Each gets the brief, its focus, the rules, and a budget of about 25 tool calls.

1. Security: apply the Security section of `~/.config/agentic/agents/reviewer.md` to the whole repo, plus the `~/.config/agentic/skills/security-audit/references/` files the brief names. Read them once and paste their text into the lane prompt, so the lane spends its budget on the repo. Include secrets in git history, debug or admin routes reachable in production, seed credentials, and the strangest half-finished feature, read until it is safe or not. Cite a secret by `file:line` or commit SHA and its type, never its value. Run the audit commands from the brief and report each known CVE with package, installed version, fixed version, and whether the vulnerable path is reachable. A lead that hinges on a deployment fact outside the repo gets impact `unverified` and names that fact.
2. Performance: slow queries, a query per item, work repeated per request or per process, memory that only grows, heavy bundles and assets.
3. Dead weight and upgrades: unused code, files, options, flags, and dependencies, duplicate helpers, abandoned files. Run the outdated commands, then read the release notes only for the frameworks and direct dependencies behind by a minor or major version. Report an upgrade only when a release fixes a security or performance bug this repository can hit, or ships a feature that replaces our own code, naming that code. Note the breaking changes it brings.
4. Tests: critical paths, money, auth, data writes, parsers, with no test that fails when they break. One good test per gap, not coverage.
5. New developer: what is confusing, undocumented, or misleading, setup steps that fail, comments that lie, names that mean two things.

Rules for every lane:

- Read only. Run only the audit commands and read-only commands, never install, upgrade, migrate, or write.
- Every finding needs a concrete case, this input or situation leads to this wrong result. No case, no finding, no "consider", no style taste.
- Before calling code unused, grep the whole tree for it, including tests, fixtures, config, and string or dynamic references.
- Return at most 5 findings, most important first, one line each: `file:line, claim, evidence, smallest fix, impact high|medium|low|unverified, effort hours|day|days`. Then one line of what the lane did not read.

## 3. Verify

Merge the lanes, dedup by root cause or the same `file:line` region, keep the higher impact, list every lane that found it. Never merge a security finding into a general one.

Skip verification when no finding is high impact. Otherwise spawn one fresh read-only verifier with the numbered findings and only the code around each cited line. It answers keep, drop, or unverified per number, drop only when the cited code contradicts the claim, never drop a security or CVE finding, answer unverified instead.

## 4. Report

Very plain English, a reader who never saw this code follows it.

```text
What this repo does: <two sentences>, assumed load: <load>.

Findings, ranked by impact then effort:
1. <title> (`file:line`), <lane>, impact <x>, effort <y>
   Problem: <the concrete case>
   Fix: <smallest fix>

Known CVEs: <package installed to fixed, reachable or not>, or none found by <tool>.

Upgrades worth taking: <package current to latest, the fix or the feature, the own code it replaces, breaking changes>, or none.

One-week plan:
Day 1: <findings by number>
...
Day 5: <findings by number>
Later: <low impact items left out of the week>

Verdict: ready, or fix <numbers> before launch.
Not checked: <parts no lane read, audit tools that were missing>. The security lane is a quick pass, `/security-audit` is the deep one.
```

Plan the week as high impact low effort first, then high impact high effort, then the rest. CVE fixes with a reachable path go on day 1. At most 25 findings in the report, say how many smaller ones were left out.

Stop after the report. Ask which findings to fix, the user's pick is the scope sign-off, then hand them to `/code`.
