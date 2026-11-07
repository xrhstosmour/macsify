# Intake

Asked fresh every run, one category per message. The answers stay in the session. Ask about roles and types, never for an identifier: "a personal Gmail used for banking" is the answer, the address itself is never needed. Skip a category the user says does not apply, and say what skipping it leaves unchecked.

## 1. Devices

- Laptops and desktops: OS and version, owner (personal, work, shared with family), disk encryption, who else has an account on it.
- Phones and tablets: platform and model class (Pixel, other Android, iPhone, iPad), OS version, whether it still gets security updates, lock method, work profile or employer MDM.
- Wearables, e-readers, consoles, cars with an app, anything else signed in to an account.
- Old devices still signed in, in a drawer, sold, given away, or broken.
- Removable drives and backup disks.

## 2. Identity and recovery

- Primary identity providers: Apple Account, Google Account, Microsoft Account, others used for "Sign in with".
- Email accounts by role: primary, finance, developer, throwaway, legacy, and which one recovers which.
- Phone numbers by role, the carrier, prepaid or contract, eSIM or physical SIM, whether a port-out PIN or number lock is set.
- Recovery chains: for each root account, what recovers it (email, phone, recovery key, trusted contact, hardware key).

## 3. Passwords and second factors

- Password manager and plan, family or shared vaults, the emergency kit or recovery key and where it lives physically.
- Where else passwords, recovery codes and seed phrases live today: paper, notes apps, text files, screenshots, spreadsheets, email drafts, chats to self, the browser's own password store.
- Second factors in use: SMS, email codes, an authenticator app (which, and whether it syncs), passkeys (where stored), hardware keys (how many, which ones registered where).
- Accounts still on SMS or with no second factor.

## 4. Money

- Banks, cards, payment apps, brokers, pension and insurance portals, tax portal.
- Crypto: custody type only, exchange, hardware wallet, software wallet, self-custody multisig. Never amounts, addresses, or which coins.
- Who knows the user holds crypto or significant assets, online or offline.
- Alerts already set: login, transaction, new payee, withdrawal.

## 5. Data at rest

- Backups: what is backed up, where, encrypted or not, offline copy or not, last restore test.
- Cloud storage accounts and what each syncs (photos, documents, desktop, messages), shared links and shared folders.
- Sync tools between own devices.
- Sensitive documents and scans: IDs, passports, contracts, medical, where they live.

## 6. Accounts

- Social, messaging, shopping, travel, health, government, utilities, ISP.
- Legacy and dormant accounts the user remembers, old usernames, old forums, old shops.
- Shared accounts with a partner or family, and who has admin over them.

## 7. Developer surface

- Code hosts and package registries (GitHub, GitLab, npm, PyPI, crates, Docker Hub), organizations administered.
- Signing and SSH keys: where they live, passphrase or hardware-backed, and whether commit signing is used.
- Tokens: personal access tokens, CLI logins, cloud provider accounts, CI secrets on personal repositories.
- Domains and the registrar, DNS provider, email on own domain.
- AI tools and agents in use, their permission modes, MCP servers, browser extensions with page access.
- Self-hosted services and servers, exposed or behind a VPN.

## 8. Network and home

- Router, ISP-supplied or own, mesh, extenders.
- Wi-Fi networks, guest network, VPN or tailnet.
- IoT: cameras, doorbells, locks, speakers, TVs, plugs, hubs, printers, vacuums, appliances.
- Who else uses the network, and whether work devices join it.

## 9. People and places

- Who could plausibly target the user: someone they know, a former partner, a dispute, a public role, a known holding.
- Household members whose accounts or devices touch the user's.
- Public exposure the user knows of: talks, posts, open source, press, registries, address listed anywhere.

## 10. Work separation

- Which devices, accounts and browsers are work, and whether any personal account is signed in on a work device or the reverse. Work systems themselves are out of scope, only the separation is checked.
