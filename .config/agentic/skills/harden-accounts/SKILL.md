---
name: harden-accounts
description: >
  Hardening of the user's own accounts, devices, money and data, single points of failure, 2FA tiers, passkeys versus hardware keys, SIM-swap defence, phone and laptop settings, banks and crypto, backups, cloud storage, loose secrets in notes and files, legacy accounts, and the developer surface. Use for "/harden-accounts", "harden my accounts", "sim swap protection", "passkeys or yubikey", "secure my crypto", "secure my backups".
disable-model-invocation: true
---

# Harden Accounts

A checklist driven by what the user actually has. Called by `secure-me` with the intake map from the session, or alone, then ask the intake questions of `secure-me` (`~/.config/agentic/skills/secure-me/references/intake.md`) that the chosen area needs. Personal profile only.

## Hard rules

The hard rules of `secure-me` apply in full, run alone, read its Hard rules and Report sections in `~/.config/agentic/skills/secure-me/SKILL.md` first. In short: nothing stored, no secret asked for or printed, the user makes every change, no PII to an external service without approval in this run, ask before reading credential stores, no `sudo`, single-purpose commands, refresh dated guidance with WebSearch and cite it. On top of those:

- The agent opens no account and logs in nowhere. It gives the click path, which the user follows, and confirms by asking, or by a screenshot the user chooses to share.
- Before a change that can lock the user out, a new second factor, removing SMS, a recovery key, a carrier lock, confirm the way back exists and works: a backup key registered, recovery codes saved in the password manager, a second signed-in device. One change at a time, verified before the next.
- A file search for loose secrets matches names, types and locations only, never prints or reads contents into the chat, and runs only after the user approves the folders in this run.

## 1. Single points of failure

From the map, list each one with what it breaks and the fix:

- The email that recovers most accounts: it gets the strongest protection of all, hardware keys, no SMS recovery, and a separate email for finance where practical.
- The phone number as a recovery path: remove it from root accounts once a stronger factor is registered.
- The password manager: emergency kit or recovery key stored physically, offline, apart from the devices. Account recovery set, a trusted contact if the plan has one.
- The one device holding all 2FA: a second factor that is not on that device.
- One cloud account holding every backup and the photos and the password export: an independent copy.
- One person who could lose or abuse access: shared vaults and family admins reviewed.

## 2. Account tiers and second factors

Read `references/passkeys-vs-hardware-keys.md`. Sort the user's accounts into root, high and normal, show the tier list, and agree it before any change. Then per tier, the target factor, what to remove, and the order, root first.

## 3. SIM swap and phone number

- Carrier: port-out PIN or number lock, SIM PIN, carrier account with its own strong password and the strongest second factor it offers, no recovery by the same phone number.
- Ask whether the carrier allows an eSIM transfer from the app alone, which is a takeover path when the carrier account is weak.
- Every root and high account: SMS removed as a second factor and as a recovery method, once a stronger one is in place.
- Signs of a swap to know: sudden no-service, unexpected SIM or eSIM messages. The response is calling the carrier from another phone, then changing the email password and revoking sessions.

## 4. Devices

Read `references/devices.md` and apply only the sections for devices in the map. Report the setting, its current value as the user reads it, and the target.

## 5. Money

Read `references/finance-and-crypto.md`. Apply the bank and card part to every financial account in the map, the crypto part only when the user holds any.

## 6. Data at rest

Read `references/data-at-rest.md`. Backups, cloud storage, sensitive documents, and the loose secrets search.

## 7. Legacy accounts

- Build the list with the user: old usernames and emails searched in the password manager, the browser's password store, the email inbox for "welcome" and "verify" messages (the user searches, the agent gives the search terms).
- Per account: close it, or keep it with a unique password and a second factor. A closed account's data is deleted through its own process or with the request in `purge-personal-data`.
- Old devices still signed in: remove them from the device lists of the identity providers and messengers.

## 8. Sessions, apps and sharing

- Signed-in sessions and devices on root accounts: revoke what the user does not recognise.
- Third-party apps with access to the Google, Apple, Microsoft and GitHub accounts: revoke unused ones.
- Location sharing, Find My and Find My Device sharing, shared calendars and albums: who can see what, important in the targeted-person case.
- Unknown device trackers: the phone's built-in tracker alerts on, and a scan if the user suspects one.
- Messaging: Signal or another end-to-end messenger with a registration lock or PIN, safety numbers checked for close contacts, disappearing messages where wanted.

## 9. Developer surface

Read `references/developer-surface.md` when the user has developer accounts.

## Report

Same format as `secure-me`: good, serious, minor, nitpick with evidence, fix, who applies it and the undo, FLAGGED for unchecked or someone else's. When called by `secure-me`, hand the findings back for its ranked list instead of a separate one.
