---
name: qa-audit
description: >
  Launch QA with five first-time-user personas driving the app in a real browser, one ranked friction list, a single fix pass, then a rerun as proof. Use for "/qa-audit", "QA the launch as new users", "first-time user test".
---

# QA Audit

Five different new users go from the landing page to their first success, the confusion they hit is merged into one list ranked by how many users hit it, fixed in one pass after approval, then the same five users run again to prove it.

## 1. Target

- Ask for the URL if none was given. Local or staging only, refuse production, the breaker submits junk and double-clicks real forms.
- A local app starts through the `run` skill.
- Fake data only, never a real account, customer, email, or payment detail.
- Browser work goes through the `claude-in-chrome` skill, invoke it first. Each persona gets its own tab, never a shared one. If no browser tool is available, stop and say so, never fall back to reading the code or fetching pages.

## 2. Brief

Write at most 15 lines, the same for every persona: what the app does, the entry URL, what first success means (signup done, first item created, first order placed), and the screenshot directory, a new folder in the scratchpad, never the repository.

## 3. Personas

Spawn the four desktop personas in one message, in parallel, each a fresh general-purpose subagent with the brief, its persona, the rules, and a budget of about 40 tool calls. Tell each persona not to call the advisor, each call bills its whole transcript at the advisor's rates, the main session weighs the findings. Run the mobile persona alone after they finish, tabs of one window share its size, so resizing it mid-run changes the viewport of every other persona. The lanes are exempt from the `leader` delegation cap. Without subagent support, run all five one after another with the same brief.

1. Impatient: skims, clicks the first button that looks right, quits at the first error.
2. Skeptic: reads pricing, terms, and privacy before signing up, leaves if any is missing, vague, or contradicts the page.
3. Mobile: a 375px wide screen on slow 3G. Resize the window and throttle the network when the browser tool allows it, otherwise say in the report which of the two was not possible.
4. Non-native English speaker: follows only what the interface literally says, no inference from icons, idioms, or context, flags jargon and unclear labels.
5. Breaker: pastes junk into every form (very long text, emoji, markup, empty, whitespace), goes back mid-flow, reloads mid-flow, double-clicks every button.

Rules for every persona:

- Go from the landing page to first success, or to the point the persona would give up, and say which.
- Screenshot every moment of confusion, being stuck, or annoyance, named `<persona>-<step>.png`.
- Return at most 8 findings, most painful first, one line each: `page, what happened, screenshot path, severity high|medium|low`. Then one line of what the persona did not reach.
- No finding without a concrete case, this action led to this result. No style taste.
- Describe what a page shows, never copy names, emails, or other personal data from it, a staging app can hold real data.

## 4. Merge

Merge all findings into one list, a finding two personas describe differently is one entry. Rank by how many personas hit it, then severity. Each entry keeps its persona list, the page, and the screenshot paths. Show the list and stop, the user approves it before any edit, as in `launch-audit`.

## 5. Fix

After approval, fix the whole list in one pass through the normal `/code` flow. Several entries sharing one root cause get one fix. Anything out of scope or needing a decision goes in a `FLAGGED:` block, per `standards.md`.

## 6. Rerun

Run the same five personas against the fixed app with the same brief and a new screenshot folder. Report each entry as fixed, still broken, or new, with the before and after screenshot paths. The work is done only with that rerun output. Anything still broken goes back to step 5, at most two more rounds, then ask the user.
