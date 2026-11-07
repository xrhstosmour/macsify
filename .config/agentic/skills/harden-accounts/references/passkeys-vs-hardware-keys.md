# Passkeys versus hardware keys

Written 2026-11-08 from general knowledge, not yet verified against each service. Refresh each run, which services accept security keys, and the password manager's passkey and recovery features, change often.

## Tiers

- Root: an account whose loss leads to the loss of others, or of money, or is permanent. The primary email, the Apple, Google or Microsoft account, the password manager, the carrier, banks and brokers, crypto exchanges, the domain registrar and DNS provider, the code host with signing or package publishing rights.
- High: personal data or reputation at stake, hard to recover. Secondary email, cloud storage, messengers, social accounts in the user's real name, health and government portals, the router's cloud account.
- Normal: everything else.

## Risk assessment

Passkeys in a password manager (synced passkeys):
- Strong: phishing resistant, the same protection against relay phishing kits as a hardware key, no codes to steal.
- Weak point: the passkey is only as safe as the password manager account and every device it syncs to. Malware on an unlocked device, a takeover of the manager account, or a manager outage reaches every passkey at once. It is also the single point of failure for the passwords already.
- Recovery: easy, a new device syncs them back.

Hardware keys (FIDO2 security keys, device-bound passkeys):
- Strong: the private key never leaves the key, a remote attacker or malware cannot copy it, and it sits outside the password manager, so a manager compromise does not reach the root accounts. Physical touch is needed.
- Weak point: loss or damage, so two keys are needed, and a few services allow only one or fall back to weaker recovery that undoes the gain.
- Recovery: the backup key, then the service's own recovery codes, kept in the password manager or on paper.

Verdict for this threat model: root accounts get two hardware keys, a primary on the key ring and a backup stored apart, registered on every root account, with SMS and email recovery removed where the service allows. High accounts get a synced passkey or a hardware key, the user's choice per account. Normal accounts get a synced passkey or a unique generated password with an authenticator app. The password manager itself is protected by a hardware key and its own secret key or recovery kit, never by a passkey stored inside itself.

## Notes to check per run

- Apple Account security keys need Apple devices on supported versions and at least two keys. Advanced Data Protection is a separate setting, see `devices.md`.
- Google Advanced Protection Program accepts passkeys and security keys and tightens app access and downloads, worth it for this threat model, check its current requirements.
- 1Password: Secret Key plus account password, Emergency Kit printed and stored offline, security key as the second factor, check whether it offers unlocking with a passkey and what recovery then looks like.
- A service that offers a passkey but keeps SMS recovery on is only as strong as SMS, check the recovery settings, not only the sign-in.
- Authenticator apps: one with an encrypted backup the user controls. TOTP seeds in the password manager are convenient but put both factors in one place, avoid it for root accounts.
- Register both keys before removing any older factor, and test the backup key once.
