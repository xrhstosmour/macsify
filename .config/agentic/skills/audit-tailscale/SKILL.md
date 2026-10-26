---
name: audit-tailscale
description: >
  Audit and lock down the user's own Tailscale network, replacing allow-all access with tags and per-port grants, rolled out one device at a time. Use for "/audit-tailscale", "audit my tailscale", "lock down my tailnet", "tailscale acl", "who can reach what on my tailnet".
---

# Audit Tailscale

A report and a reviewed policy first, changes second. Every read is read-only. The policy is applied only after the user approves the diff, devices are tagged by the user, one at a time. Based on the Tailscale lockdown prompt by alexknowshtml, adapted to this setup.

## Hard rules

- Own tailnet only. A tailnet the user does not administer is out of scope.
- Read-only until the user approves. Show every policy change as a diff before applying it, with a plain summary.
- Never ask for a secret in chat and never print one. API access is an OAuth client the user creates at `https://login.tailscale.com/admin/settings/oauth` with only two scopes, Policy File (read and write) and Devices Core (read). The user checks the scopes shown before generating the secret, and stores it in a password manager, an environment variable, or a file outside any repo. The agent reads it only through the shell, never echoes it, never writes it into a file or a command shown in the report. The token comes from `POST https://api.tailscale.com/api/v2/oauth/token` with `grant_type=client_credentials`, the credentials go in on standard input, never in arguments or logs.
- Keep the policy's own header comments. Fetch it with `Accept: application/hujson` so comments survive, and keep the `ETag` of that response.
- Privacy: no tailnet name, email, tailnet IP, device hostname, auth key, or OAuth value goes into a file, memory, PR, or shared message. Use roles and tags in anything saved. The saved policy file is the one exception, it needs the real `hosts` addresses to work, so it goes only where the user chooses, never into a repository, pull request, or shared note.
- Explain in plain terms, the user is not a network engineer.
- No `sudo`, no admin password. A check that needs root is reported as unchecked or the user runs it with the `! <command>` prefix.
- Single-purpose commands, no compound one-liners, no `nc`, `tcpdump`, or tunnels.
- The agent never runs `tailscale up`, `down`, `logout`, `set`, or `ssh` to a device, or change an exit node or route on the machine the session runs from, a wrong change cuts the user off from their own devices.

## Change safety

A bad policy can lock the user out of their own devices. These rules override speed:

- Save the current policy and its ETag before anything, so there is a way back. The user can restore it in the admin console under Access controls.
- Always include a `tests` block, and validate before applying.
- Apply with `If-Match` on the ETag that was reviewed, so a change made meanwhile is not overwritten.
- Applying the policy changes nothing for the user's own untagged devices, but it does change access for devices of other users, shared nodes, already tagged machines, exit nodes and subnet routes, so check the inventory for those before applying. New tags take effect device by device, so roll out one at a time, lowest risk first. The OAuth client cannot set tags, the user does it in the admin console.
- Keep a second way in to every device before tagging it, the machine console, a phone on mobile data, or the cloud provider's console.
- One approval covers one change, never a batch and never a later run.
- If a device stops working, the fastest way back is restoring the saved policy, which acts at once for every device. Removing the device's tag is the second way, and the device may need to sign in again to become a user-owned device. Confirm access is back before moving on.

## 1. Inventory

Without API access, use what the machine shows: `tailscale status`, `tailscale status --json`, `tailscale debug prefs` (check `RunSSH`, `AdvertiseRoutes`, `ExitNodeID`, `AdvertiseExitNode`, `ShieldsUp`, `CorpDNS`), `tailscale netcheck`, `tailscale serve status`, `tailscale funnel status`, and `tailscale version` against the latest release. With API access, fetch the policy (`GET /api/v2/tailnet/-/acl`) and devices (`GET /api/v2/tailnet/-/devices?fields=all`). Ask the user to download the policy from the admin console when there is no API client.

Report:

- Rules that allow everything, the default `*:*` policy or a wildcard grant.
- Stale devices, offline 60 days or more, and devices owned by someone else.
- Exit nodes, subnet routers, and routes that were advertised but are not approved.
- Whether Funnel is enabled, and whether anything uses it.
- Tailscale SSH on or off per device, and who may use it.
- Key expiry: devices with key expiry disabled, and old client versions.
- Tailnet settings to ask the user to read in the admin console: device approval, user approval, MagicDNS and the DNS servers, shared nodes, and who the admins are.

Ask the user for the local copy of the policy, if they kept one, and compare it with the live policy. They differ more often than expected, the live one wins, report every difference and never overwrite the live policy with the copy. Then audit the live policy against the ground rules: untagged servers, a tag that can reach a personal device, a grant wider than the mapped ports, `ssh` rules that allow root on tagged machines, missing tests, and tags nobody uses.

A small tailnet of only the user's own devices, with no shared or public machines, is fine on the default policy. Say so, and keep the lockdown for the first shared, server, or public-facing machine. A tailnet that is already locked down is audited for drift, not redone.

## 2. Sort devices into groups

- Personal devices, phones and laptops, stay untagged with full access. An untagged machine owned by the user counts as personal, so a server that joins without a tag gets full access and defeats the lockdown. Servers must carry exactly one role tag, applied when they join.
- Servers, grouped by role, each role gets one tag.
- Shared or public-facing machines that other people can touch, these are the biggest risk and go first.
- Devices that are only there for one job, a subnet router or exit node, get their own tag and the narrowest grant.

A role set that worked for a small tailnet, adapt the names and ports to the user's:

- `tag:server`: SSH on 22 from personal devices, reaches only the internet.
- `tag:web`: SSH on 22 plus HTTP 80 and HTTPS 443 from personal devices, reaches only the internet.
- `tag:shared`: SSH on 22 from personal devices, reaches other shared machines and the internet, never a personal device.
- `tag:internal`: SSH on 22 from personal devices, reaches nothing until a grant names the exact port a service needs.
- No tag reaches a personal device on any port. Only admins can put a tag on a device (`tagOwners` is `autogroup:admin`).

Ask the user to confirm each group, never infer it from a hostname.

## 3. Map before denying

For each server, find what it listens on and what connects to it, before any deny:

- `ss -tlnp` on Linux or `lsof -iTCP -sTCP:LISTEN -nP` on macOS, run by the user on that server if the agent has no access.
- Live connections filtered to `100.` addresses.
- A search of the user's configs and scripts for tailnet addresses and hostnames, with the project search tools, not `grep` over the filesystem.
- Outbound connections from the server to other tailnet devices.
- Tailscale SSH off means port 22 is governed by the grants, on means the SSH policy rules.

Show the port map, each server with its listening ports and who uses them, and ask the user to confirm it.

## 4. Draft the policy

The skill ships no policy file on purpose, Tailscale's policy fields and syntax change. No earlier policy or local copy is needed either. Build the policy from the live tailnet and the current documentation:

- Fetch the live policy and the device list through the OAuth client, and read the current policy syntax from Tailscale's own documentation (`tailscale.com/kb`, the access control and grants pages) before writing a line. Use the field names the live policy and the docs use today, never from memory, and never keep a deprecated one such as the legacy `acls` list where `grants` are available.
- Let the validate endpoint be the judge. A field it rejects is fixed from the docs, not guessed around. A `tests` block that fails stops the run.
- Address names come from the device list, confirmed by the user. The non-root login name for SSH is asked, never guessed.
- Roles and ports come from steps 2 and 3, not from a template. Write the design below in the current syntax.
- Keep the saved copy private, it holds tailnet addresses.

The design to express, adjust only with the user's approval:

- `hosts` aliases for each personal device's address so tests do not depend on tag order, and one tag per role in `tagOwners`. A replaced device needs its alias address updated.
- Grants that allow only the mapped ports. SSH into tagged machines is `tcp:22` only.
- Servers that only answer requests get internet access only.
- Shared machines reach each other and the internet, never the user's devices.
- Personal devices keep access to everything they own.
- An `ssh` rule into tagged machines with action `check`, browser re-authentication every 12 hours by default, a custom period needs a higher plan, for `autogroup:nonroot` only. Root is refused on tagged machines. Between personal devices root may stay allowed behind the same check.
- With Tailscale SSH on a machine, port 22 in the policy is served by Tailscale whatever port `sshd` uses. A plain `sshd` on another port needs that port in the grant for the tag, and skips the `check` re-authentication, so prefer Tailscale SSH on tagged machines.
- A `tests` block with one accept test for every allowed port and deny tests proving each tag cannot reach the user's devices or another role, and an `sshTests` block with `check` for the allowed user and `deny` for root.
- A comment header on the policy saying what it does, how an agent changes it, and that the live copy in the admin console wins over any local copy. Keep emails and secrets out of it.

Validate with `POST /api/v2/tailnet/-/acl/validate`, or in the admin console's access controls editor when there is no API client. Show the diff against the saved policy and a plain summary, and wait for the approval.

## 5. Roll out safely

1. Apply the approved policy with `If-Match` on the `ETag` from the fetch. Nothing changes yet, because no device has the new tags.
2. The user tags one device at a time in the admin console, lowest risk first. For a new server, the user creates a one-time tagged auth key in the admin console and the server joins with `--advertise-tags`, the browser login flow only works when the user is an admin who owns the tag. A server must never join untagged.
3. After each one, verify five things: the tag shows up, the allowed ports still work, SSH works after the browser re-authentication and root is refused, the device can no longer reach what it should not (tested from the device itself, including the user's laptop), and its public service, if any, still answers. Tests cannot prove these without a real machine behind the tag, say so.
4. If something breaks, stop, undo as described in Change safety, then diagnose before the next device.

## 6. Clean up and record

- The user removes stale devices in the console. The agent lists them, never removes them.
- Turn off Funnel if nothing uses it, shared nodes the user no longer needs, and unused subnet routes and exit nodes.
- Save the final policy to a file the user chooses, as a local copy with a comment saying the live policy wins. Old versions can be restored from the policy history in the admin console.
- Machine names appear in public Certificate Transparency logs when HTTPS is enabled on the DNS page, so check that no hostname carries anything private.
- A tagged server that must reach a personal device, such as a backup to a laptop, is blocked by the policy. A narrow grant on port 22 from that tag to that laptop is a decision for the user, never added by default.
- A script or automation that logs in over the tailnet must expect the re-authentication prompt, a browser URL on the first login, and must not misread it as a failure or hang inside a rollback window.
- Write a short note listing each tag and its ports, so later debugging checks the policy before blaming the server.

## Router and home network

Tailscale reaches devices without any router port forward. A UPnP or NAT-PMP mapping that Tailscale created on the router, a UDP port mapped to its local port, is optional, direct connections work faster with it, and a relay works without it. If the user runs `audit-home-network`, a Tailscale mapping on the router is reported there, the user decides whether the faster direct path is worth the open port.

## Report

Plain words, no emoji, no bold, no decorative dividers. Severity as serious, minor, or nitpick.

- Good: what already holds.
- Serious, minor, nitpick: finding, evidence, smallest fix, who applies it (agent through the approved diff, or the user in the console).
- Compared with the last run, when the user has a previous report, otherwise say first run.
- FLAGGED block for anything unchecked, owned by someone else, or needing a decision.

Close out: remind the user to revoke the OAuth client and delete its password manager item when the work is done, and to keep the saved policy file out of any public repo, it holds private tailnet addresses in `hosts`.
