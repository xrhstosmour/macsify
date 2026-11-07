---
name: secure-me
description: >
  Recurring personal security and privacy audit of the user's own digital life, a fresh intake of devices, accounts, money, data and network, a sweep of new CVEs and breaches against that stack, the hardening, purge and network audits it calls for, and one ranked list of manual actions. Use for "/secure-me", "secure me", "audit my security", "lock down my digital life", "check me against new CVEs and breaches".
disable-model-invocation: true
---

# Secure Me

The entry point for the user's personal security. It asks, maps, checks and ranks, then hands each area to the skill that owns it. Personal profile only, never run on a work machine or against an employer's accounts.

## Threat model

Defend against all of these at once, and say which one a finding serves:

- Opportunistic criminals: phishing, credential stuffing, infostealers, SIM swaps, ransomware, mass breaches.
- A targeted person: someone who knows the user, their devices, their home, their accounts, or can reach their family or carrier.
- A public developer profile: account takeover aimed at repositories, packages, tokens and signing keys, supply chain attacks through the user's code.
- High-value finance and crypto: anything that makes the user worth a dedicated attack, and the physical risk that follows if holdings become known.
- Automated and AI-driven attacks: agents that scan, phish and exploit at scale, prompt injection through repositories, issues, web pages and documents read by the user's own AI tools, malicious MCP servers and packages, deepfaked voice or video against support desks and the user's contacts.

The model is high security where a loss is permanent (root accounts, money, keys, identity), high convenience everywhere else. Say so when a recommendation trades one for the other.

## Hard rules

- Stores nothing. No inventory file, no memory, no notes, no artifact. The report stays in chat. A scan output in the scratchpad lives only until close out. Every run asks again, the stack changes and an old map is a risk if it leaks. The only comparison is with a previous report the user pastes in.
- Never ask for, type, read aloud, or store passwords, recovery codes, TOTP seeds, passkeys, seed phrases, balances, wallet addresses, card or account numbers. A file found to hold one is reported by its path only.
- The user makes every account, device and router change, the agent gives the click path and the undo. A change on the machine the session runs on follows the change rules of `audit-home-network`.
- Identifiers to scrub, aliases, emails and phones, live in the session only, per `purge-personal-data`.
- No PII to an external service without the user's approval in this run. A search or lookup with the user's email, phone or name runs in Chrome only after that approval, otherwise the agent gives the URL and the user runs it.
- `~/.ssh`, `~/.aws`, `~/.kube`, `/etc/`, keychains, password manager data and security tooling: ask before any read, never print a secret. No `sudo`. Single-purpose commands only. Stop and name a blocker, never work around one.
- Sources go stale. Every reference file of these skills carries the date it was written or last verified. Refresh what a run relies on with WebSearch first, and when a run verifies a reference, offer the user an edit to its date line, and cite the page, never answer a version, CVE or vendor setting from memory.
- Plain words, no emoji, no bold, no decorative dividers. Severity as serious, minor, or nitpick.

## Run order

Wait for the user between phases, each phase ends with a short checklist and a question.

1. Previous run. Ask whether the user kept a previous report. If so, they paste it, the agent compares at the end. Otherwise say it is a first run.
2. Intake. Ask the questions in `references/intake.md`, one category at a time, a few short questions per message, with choices where they help. Never assume a device, app or account. Unknown answers are recorded as unknown, not guessed. End with a role-level map in chat, device classes, app names, account tiers, and the second factor for each, with no identifiers.
3. Threat sweep. With `references/threat-landscape.md`, check the mapped stack for actively exploited CVEs, overdue updates, end of life devices and software, vendor advisories, and new breaches of the services named. Report only what touches the user's stack, each with its source and date.
4. Single points of failure. From the map, name every place one loss breaks many things: one email recovering everything, a phone number as the recovery path, one password manager with no emergency kit, one cloud account holding every backup, one device holding the only 2FA. This feeds the order of everything after.
5. Delegate. These skills are hidden from the model to save tokens, so the Skill tool cannot load them, read each `SKILL.md` by its path under `~/.config/agentic/skills/` and follow it, using the map from this session instead of asking again. In this order, only those the intake calls for:
   - `harden-accounts/SKILL.md` for identity, 2FA, passkeys and hardware keys, SIM swap, devices, finance and crypto, backups, cloud storage, loose secrets, legacy accounts and the developer surface.
   - `audit-home-network/SKILL.md` for the computer baseline, router, LAN, Wi-Fi and IoT.
   - `audit-tailscale/SKILL.md` when the user runs a tailnet, its Recheck section when it is already locked down.
   - `purge-personal-data/SKILL.md` for self-OSINT, breaches and data brokers.
   The user may skip or reorder any of them.
6. Missed steps. If a previous report was pasted, list every action it left open and whether it is now done, ask the user, never assume. Otherwise list what this run left open.
7. Action list. One ranked list across every skill, serious first. Each line names the action, the threat it stops, who does it, the time it takes, and the undo where one exists. Group the user's manual actions so they can be done in one sitting.

## Report

- Good: what already holds.
- Serious, minor, nitpick: finding, evidence and source, smallest fix, who applies it.
- Compared with the last run: new, closed, and still open, or first run.
- The ranked action list from step 7.
- FLAGGED block for anything unchecked, owned by an employer or someone else, or needing a decision.

At the end, offer a sanitized summary for the user to keep themselves, finding titles, severity and status only, no device names, identifiers, providers tied to accounts, or addresses. The agent does not save it. Suggest rerunning after a new device, router, phone number, job, move, or a breach notice, and at least every three months.

## Close out

Close every tab the run opened, remind the user to log out of anything they logged in to for the run, and remove any temporary file in the scratchpad that holds a finding.
