# Data at rest

Written 2026-11-08 from general knowledge, not yet verified against each service, refresh what a run relies on.

## Backups

- 3-2-1: three copies, two kinds of storage, one off site. One copy offline or immutable, so ransomware or a stolen account cannot reach it.
- Encryption: Time Machine encrypted (`tmutil destinationinfo`, read by `audit-home-network`), external drives encrypted, cloud backups end-to-end encrypted where the service offers it.
- The backup's own keys and passwords are in the password manager, and the manager's own recovery is not only inside that backup.
- Restore tested in the last year, a backup never restored is a guess.
- Phones: the platform backup on, and photos in at least one place besides the phone and its cloud.
- The password manager export, if ever made, deleted after use, never kept in a backup or cloud folder in plain form.

## Cloud storage

For each account the user named, iCloud, Google Drive, Dropbox, OneDrive, Proton Drive, others:

- Account tier from `passkeys-vs-hardware-keys.md`, usually high, root when it holds IDs or the only copy of something.
- End-to-end encryption: on where offered, Advanced Data Protection for iCloud.
- Shared links: list and remove the old ones, prefer links with an expiry and a password, "anyone with the link" on a sensitive file is a finding.
- Shared folders and who is in them.
- Connected apps with drive access: revoke unused ones.
- Signed-in devices: remove old ones.
- What syncs: Desktop and Documents sync puts every file into that account, the user decides if that is wanted.
- Sync tools between own devices: shares reviewed per device, untrusted or old devices removed, `audit-home-network` checks the network side.

## Sensitive documents

IDs, passports, tax and medical records, contracts:

- Stored in one known place, encrypted, a password manager document vault or an encrypted folder, not loose in Downloads, email attachments or chat history.
- Scans sent to services: ask which, and add them to the `purge-personal-data` list when no longer needed.

## Loose secrets

Passwords, recovery codes, seed phrases, API keys and ID scans kept outside the password manager.

1. Ask the user where they think they have some: notes apps, text files, spreadsheets, screenshots, email drafts, chats to self, the browser's password store, old password manager exports.
2. With the user's approval of the folders for this run, look by name and type only, for example files named like `password`, `passwords`, `recovery`, `codes`, `seed`, `wallet`, `backup`, `export`, `.csv` exports of a manager, `.kdbx`, `.pem` and `.key`, screenshots in Desktop and Downloads. Use `rg --files` with globs, `mdfind` on names, never read or print a file's contents. Report paths only.
3. For notes apps, email and chats, the user searches, the agent gives the search terms.
4. Per item, the user decides: move it into the password manager, then delete the original, emptying the trash, and the copies in cloud sync and backups age out. Keys belong in the manager's SSH agent or a hardware key, see `developer-surface.md`.
5. The browser's own password store: export into the manager, then turn saving off and clear it, the user does it.

## Old storage

Old phones, laptops, drives and SD cards: erased with the platform's own erase, or physically destroyed, before sale, gift, repair, or disposal.
