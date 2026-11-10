# Data brokers

Written 2026-11-08 as a seed list from general knowledge, not checked site by site. Every run, confirm each site still exists, find its current opt-out or privacy contact on its own privacy policy page, and add brokers found during self-OSINT. Never trust an opt-out URL from this file without checking it, broker sites move and fake opt-out sites exist.

Tier 1 first, they hold the data most useful to an attacker, phone, address, face, or recovery email.

## Tier 1, phone, face and contact data

- Caller ID and contact-sharing apps, Truecaller, Sync.me, Eyecon, GetContact, CallApp: they collect numbers from other people's address books and show the user's name to anyone who looks the number up. Unlisting forms on their own sites, a GDPR request where the form fails.
- Face search, PimEyes, Clearview AI, FaceCheck.ID: opt-out or erasure request, PimEyes and Clearview have both faced EU regulators.
- B2B contact databases that sell personal emails and mobile numbers, ZoomInfo, Lusha, RocketReach, Apollo.io, Kaspr, Hunter.io, ContactOut, Seamless.AI, Cognism: privacy center or GDPR request, ask for erasure and objection to processing so the record is suppressed.

## Tier 2, EU marketing and credit data

- Acxiom, Experian Marketing Services, Equifax, LiveRamp, Dun & Bradstreet (and its former Bisnode units), Infobel, CRIF, national credit bureaus of the user's country: access request first, to see what they hold, then erasure or objection for marketing use. Credit records used for lending often have a legal basis and cannot be erased, ask for correction instead.
- Ad tech with identity graphs, Criteo, The Trade Desk (UID2), Lotame, Oracle Advertising (closed, check that no successor holds the data): objection under Art. 21(2), which is absolute for direct marketing.
- Directory and phone book sites of the user's country, the national telecoms directory, and address directories: unlisting through the carrier or the site.

## Tier 3, US people-search with EU reach

They mostly hold US residents' data, but scrape global sources. Search for the user first, send a request only when a record exists.

- Spokeo, Whitepages, BeenVerified, Radaris, MyLife, PeopleFinders, Intelius, TruthFinder, Instant Checkmate, FastPeopleSearch, Nuwber, ThatsThem, USPhoneBook, PeekYou, Pipl, Social Catfish.
- Several share owners, an opt-out at one may not reach its siblings, check each.

## Also check

- Search engines' caches and people cards.
- Email permutation and breach aggregator sites that show leaked data publicly, report them to the host and the search engine.
- Old forums, guestbooks and archived pages with the user's details, removal request to the site, then to the Internet Archive.
- Marketplaces and classifieds with old listings carrying the phone number.
