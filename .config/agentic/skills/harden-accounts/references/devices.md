# Devices

Written 2026-11-08 from general knowledge, not yet verified against current OS versions. Menu paths move between OS versions, refresh them each run and say when a path could not be confirmed. Apply only the sections for devices the user has.

## macOS

`audit-home-network` step 2 checks FileVault, firewall, SIP, Gatekeeper, updates, sharing, listeners and launch agents, run it instead of repeating them here. On top:

- Lock screen: password required immediately after sleep, short auto-lock, no automatic login, guest user off.
- Apple Account: Advanced Data Protection on once recovery contacts or a recovery key are set, security keys, review signed-in devices.
- Lockdown Mode: only for the targeted case, it breaks some features, say which.
- Privacy and Security: review Full Disk Access, Accessibility, Screen Recording, Input Monitoring, and Automation grants, flag apps no longer used.
- Browser: extensions reviewed, each one can read pages and sessions, keep few. Password saving in the browser off when a manager is used.
- Antivirus: the ClamAV scan, quarantine and startup baseline set up by `setup/security.sh`, reviewed by `audit-home-network`.
- Firmware password is not available on Apple silicon, the protection is FileVault plus a strong login password.
- Find My on, Activation Lock, and the remote erase path known.

## Android Pixel

- Updates: the device's guaranteed update end date, current security patch level, Google Play system update.
- Lock: strong PIN or password, no pattern, short screen timeout, lock after restart, lockdown option in the power menu.
- Theft protection: Theft Detection Lock, Offline Device Lock, Remote Lock, Identity Check for sensitive settings outside trusted places.
- Google account: Advanced Protection Program for this threat model, and the device-level Advanced Protection setting on Android versions that have it, check current requirements.
- SIM: SIM PIN on, so a stolen SIM cannot receive codes in another phone.
- Apps: Play Protect on, sideloading off, app permissions reviewed for location, microphone, camera, contacts, notifications, accessibility services (a common malware path), device admin apps.
- Network: Private DNS set to a trusted resolver, 2G off, auto-connect to open Wi-Fi off.
- Backup: Google One backup on, end-to-end encrypted by the screen lock.
- Work profile for work apps when the employer uses one, kept apart from personal.
- GrapheneOS: an option for the targeted case on supported Pixels, a big change, explain the trade-offs (app compatibility, Google Play sandboxed, no Google account device tools), never recommend it lightly.

## iPhone and iPad

- Updates automatic, current version, device still supported.
- Passcode: six digits or alphanumeric, Face ID or Touch ID, erase after failed attempts considered.
- Stolen Device Protection on.
- Advanced Data Protection for iCloud, after recovery contacts or a recovery key.
- Security keys for the Apple Account.
- Lockdown Mode for the targeted case.
- Privacy: location services per app, tracking requests off, Safety Check reviewed for sharing and access.
- SIM PIN on.
- USB accessories locked when the device is locked.

## Other devices

- Wearables and cars: the paired account and phone, location history, and who else is paired.
- Consoles and smart TVs: account second factor, purchase PIN, and `audit-home-network` step 6 for the network side.
- Old devices: signed out, removed from device lists, erased before sale or disposal.
