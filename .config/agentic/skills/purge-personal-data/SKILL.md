---
name: purge-personal-data
description: >
  Self-OSINT and removal of the user's own personal data from the internet, finds what search engines, people-search sites, data brokers, breaches and code hosts expose about the user's names, aliases, emails and phones, then sends GDPR access and erasure requests and tracks the replies. Use for "/purge-personal-data", "remove my data from the internet", "data brokers", "self osint", "gdpr deletion request", "what does the internet know about me".
disable-model-invocation: true
---

# Purge Personal Data

Find what is exposed, rank it by how much it helps an attacker, then remove it. Called by `secure-me` or alone. Personal profile only, and only for the user's own data. Data of another person, a partner, a child or a relative, is out of scope unless that person asks themselves, then the request is theirs to send.

## Hard rules

The hard rules of `secure-me` apply in full, run alone, read its Hard rules and Report sections in `~/.config/agentic/skills/secure-me/SKILL.md` first. On top of those:

- Identifiers live in the session only. Ask for the names, aliases, usernames, emails, phone numbers, past cities and the year of birth if the user wants it used, in chat. Never write them into a file, memory, a report kept anywhere, or a search URL saved anywhere. Refer to them in the report as "primary email", "alias 2", and so on.
- Chrome searches with the identifiers run only after the user approves them in this run, in a new tab group, with nothing saved, and the tabs closed at the end. Without approval, the agent gives the exact search and the user runs it and shares only what they choose.
- Never create an account on a broker or people-search site with the user's data, never upload an ID document for the user, and never submit a form for them. Where a site demands an ID, the user decides, and the advice is to black out everything but the name and photo, or to use the email request instead, Art. 12(6) GDPR only allows asking for what is needed to confirm identity.
- Never bypass a captcha or bot check. Stop and hand it to the user.
- A tracking list of requests is the user's to keep, with broker names and dates only, never the identifiers. The agent keeps nothing.

## 1. Identifiers and goals

Ask, in one message: which identifiers to search and which to remove, which are public on purpose (a professional profile, a public GitHub), and what worries the user most, the home address, the phone, the email, photos, the family's details. That sets the priority.

## 2. Self-OSINT

Work through these in order, one source at a time, and record each finding as source, what it shows (by category: address, phone, email, relatives, photo, employer, birth date), and how to remove it:

1. Search engines: each identifier in quotes on Google, Bing, DuckDuckGo, and with `site:` for the known people-search sites from `references/data-brokers.md`. Also the name with the city, the phone in its common formats, and the email with and without the domain. Images by name.
2. Reverse image: the profile photos the user uses, through Google Lens, Bing visual search, and others where available, to find accounts and sites reusing them.
3. People-search and broker sites: the EU and US lists in `references/data-brokers.md`, search each for the user.
4. Breaches: Have I Been Pwned for each email and phone, only with the user's approval in this run, or the user checks it. Each breach names what leaked, a leaked password means changing it everywhere it was used, `harden-accounts` handles that.
5. Social and code platforms: old profiles, public friend and follower lists, tagged photos, GitHub and GitLab commit emails (`https://api.github.com/users/<username>/events/public` shows them, or the `.patch` of a commit), package registry author fields, Gravatar for each email, Keybase, forum accounts under old usernames, username search across sites.
6. Records and registries: domain WHOIS history, business and company registries, professional registries, court and public notices, the user knows which apply in their country.
7. Archives: the Wayback Machine for pages already removed, a removal request to the Internet Archive where needed.
8. Leaked documents and pastes: search for the emails and phone on paste sites through the search engines.

## 3. Rank

Rank every finding by how much it helps an attack, serious first:

- Serious: home address, phone number tied to the name (SIM swap and harassment), date of birth with name, the email that recovers root accounts, relatives' names with the address, photos of the home, anything about financial holdings.
- Minor: employer and city, old usernames, old photos, secondary emails.
- Nitpick: public on purpose and harmless.

Also flag what cannot be removed, such as a public registry or a news article, and what to do instead, a correction, a delisting request to the search engine, or changing the exposed thing (a new phone number, a new email for finance).

## 4. Remove

1. Use the site's own opt-out or account deletion when it is quick and needs no ID.
2. Otherwise send the request in `references/deletion-request-template.md`, from an email the user chooses (not the one they want to protect, when that is the issue), filled in by the user in their own mail client. The agent fills the template in the chat only with placeholders the user replaces.
3. Search engines: Google's "Results about you" and the personal information removal form, Bing's content removal, and a GDPR delisting request (right to be forgotten) for results that stay after the source is gone.
4. Platforms: delete old accounts, set profiles to private, remove tags, change the commit email for new commits.
5. Brokers that get the data back: repeat on the next run.

## 5. Track and escalate

- The controller has one month from receipt to answer, Art. 12(3), extendable by two months with a reason given within the first month.
- Per request the user notes the broker, the date sent and the channel. The next `secure-me` run asks for that list.
- No answer, a refusal without reason, or the data back: send the follow-up in the template, then a complaint to the supervisory authority of the user's country of residence, Art. 77, the template has the outline. The EDPB site lists the authorities.
- A US broker that ignores a GDPR request: say that enforcement is weak when it has no EU presence, use its own opt-out form, and record it.

## Report

Same format as `secure-me`: findings by severity with source and removal path, requests sent and pending, what could not be removed and the alternative, FLAGGED for anything that needs the user's decision. When called by `secure-me`, hand the findings back for its ranked list.
