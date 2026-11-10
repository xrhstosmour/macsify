# Developer surface

Written 2026-11-08 from general knowledge, not yet verified against each source, refresh what a run relies on. Read configuration only, never print a token, key or secret value, report names, scopes, ages and paths.

## Code hosts and registries

- Account tier root when the user can push to repositories others use, publish packages, or administer an organization. Hardware keys, no SMS.
- GitHub: `gh auth status` shows the logged-in account and token scopes, flag scopes wider than used, such as `delete_repo`, `admin:org`, `workflow` when not needed. The user reviews fine-grained and classic tokens, OAuth apps, GitHub Apps, SSH and signing keys, and sessions in the settings, the agent gives the paths. Old classic tokens with no expiry are serious.
- Commit email: the noreply address, and "block command line pushes that expose my email" on, so commits do not leak a personal email to scrapers. Old commits with a real email go on the `purge-personal-data` list, they cannot be removed without rewriting history.
- Package registries: second factor required for publishing, trusted publishing from CI instead of long-lived tokens where offered, old tokens revoked.
- Repository settings on the user's own public repositories: branch protection on the default branch, secret scanning and push protection on, Dependabot alerts on, Actions limited to verified or pinned actions.

## Keys

- SSH and signing keys in the password manager's SSH agent or on a hardware key, not as files under `~/.ssh`. Ask before reading `~/.ssh`, the `claude/settings.json` deny rules block it on purpose, the user can list it with `! ls -la ~/.ssh` and paste the names only.
- A key file on disk is a finding unless it has a passphrase and a reason.
- Old keys registered on GitHub, servers and cloud accounts are removed.

## Tokens and cloud accounts

- Cloud provider accounts: root user with a hardware key and no access keys, day-to-day access through short-lived credentials, billing alerts on, unused accounts closed.
- CLI logins: list which CLIs are logged in (`gh`, cloud CLIs, `npm whoami`), log out of unused ones. Ask before reading `~/.aws` and `~/.kube`.
- Environment files and shell history: secrets typed into a shell or kept in `.env` files outside a manager. Search history and project folders by name and pattern for the presence of a secret, never print the value, and only after the user approves the paths.

## AI agents and tools

- Permission modes: no agent with bypassed permissions on a machine that holds secrets, unattended agents limited to what their job needs.
- `~/.claude/settings.json` and `~/.config/opencode/opencode.json`: deny rules on credential stores still present (when the `macsify` checkout is present, its `tests/claude-settings.sh` checks the main ones), the ask rules for outbound and destructive actions, the web fetch guard hooks.
- MCP servers: each one named, its source and what it can reach, remove unused ones, prefer official servers, read a third-party server's code before trusting it with files or tokens.
- Prompt injection: repositories, issues, pull requests, web pages and documents an agent reads can carry instructions. Agents that read untrusted content should not also hold write access to secrets or push rights without review.
- Browser extensions with access to every page: few, from known publishers, reviewed every run.

## Domains

- Registrar account root tier, registrar lock on, auto-renew on with a card that does not expire soon, WHOIS privacy on.
- DNS provider account root tier, DNSSEC where the registrar supports it.
- Own domain email: SPF, DKIM, DMARC with a policy of quarantine or reject, so nobody can send mail as the user.
- Domains no longer used: let them expire only after checking nothing still sends mail or resets passwords through them, an expired domain can be bought and used to take over every account registered with its email.

## Self-hosted services

- Nothing exposed by a router port forward, reach it through the tailnet, `audit-tailscale` checks access.
- Admin pages behind authentication with a second factor, updates automatic or scheduled.
