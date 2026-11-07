# Threat landscape

Written 2026-11-08 from general knowledge, not yet verified against each source. Every source and pattern here is a starting point, refresh it with WebSearch each run and cite what the run used.

## Where to check the mapped stack

- Actively exploited: CISA Known Exploited Vulnerabilities catalog on `cisa.gov`, the first filter, a CVE there is serious when the user runs the product.
- Apple: the Apple security releases page on `support.apple.com`, Background Security Improvements or Rapid Security Responses, and which devices still get updates.
- Google: Android Security Bulletin and Pixel Update Bulletin on `source.android.com`, the device's guaranteed update end date.
- Microsoft: Security Update Guide, when Windows or Microsoft accounts are in the stack.
- Router and IoT vendors: the vendor's own security advisory page for the exact model, and whether it is end of life. `audit-home-network` checks the router itself.
- Browsers and apps: release notes of Chrome, Firefox, Safari, the password manager, messengers, VPN and sync clients the user named.
- Developer tooling: GitHub Advisory Database, OSV (`osv.dev`), the package registry's own security notices, advisories for the CLIs and AI agents the user runs.
- General: NVD on `nvd.nist.gov`, and ENISA's EU Vulnerability Database for the EU view.
- Breaches: the Have I Been Pwned breach list on `haveibeenpwned.com` for the services named, without the user's email unless they approve the lookup, and the services' own breach notices.

Report a CVE only with the product and version the user runs, the fixed version, whether it is exploited, and the source.

## Patterns to check for, current as of the date above

- Infostealers: malware that takes browser cookies and session tokens, so a stolen session skips passwords and 2FA. Defence is no cracked software, no unknown extensions, short sessions on root accounts, phishing-resistant keys, and revoking sessions after any suspicion.
- Adversary-in-the-middle phishing kits that relay a login and capture the session, defeated by passkeys and hardware keys, not by codes.
- SIM swap and port-out fraud, increasingly with deepfaked voice at carrier support, defended by a port-out PIN or number lock, no SMS recovery on root accounts, and a carrier account with its own strong second factor.
- Help desk social engineering against banks, carriers, email providers and exchanges, with personal data bought from brokers, which is why `purge-personal-data` matters for security, not only privacy.
- Prompt injection: instructions hidden in repositories, issues, pull requests, web pages, emails and documents that the user's AI agents read, aimed at running commands, leaking tokens, or pushing code. Defence is least-privilege agent permissions, no unattended agent with secrets in reach, reviewed MCP servers, and deny rules on credential stores.
- Malicious and typosquatted packages, compromised maintainer accounts, poisoned CI actions, and malicious VS Code or browser extensions.
- Malicious MCP servers and agent plugins that read files or tokens beyond their stated job.
- Address poisoning, fake support, fake airdrops and wallet drainer sites against crypto holders, and physical coercion when holdings are known.
- QR code phishing, fake parcel and toll texts, and fake job offers to developers that ship malware in a take-home test repository.
- Automated scanning of every exposed service minutes after a CVE, so an exposed admin page or old service on the home connection is found faster than a patch arrives.
- Stalkerware and shared-account abuse in the targeted-person case: unknown device trackers, location sharing still on, a partner or family member with admin on an account, and unknown devices in account device lists.
