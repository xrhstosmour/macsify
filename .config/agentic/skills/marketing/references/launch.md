# Launch

## Readiness gate

Run it before planning anything. A launchable first version is simple, lovable, and complete:

- Simple: it does one clearly defined job.
- Lovable: a target user would choose it, not just put up with it.
- Complete: that one job works end to end, no obvious stubs.

Two ways to fail. Still polishing past that bar means ship now. Still adding scope means cut back to the one job and ship that. For code readiness, secrets, CVEs, missing tests, run the `launch-audit` skill.

## Channels

Everything ends in a channel the user owns.

- Owned: email list, the app itself, a site or blog, a community. Start with one, usually an email list or waitlist.
- Rented: social platforms, app stores, Reddit, YouTube. Pick one or two where the audience already is, use them to pull people into the owned channel.
- Borrowed: someone else's audience, a newsletter feature, a podcast, a creator review. Send the product to a creator the audience trusts, no paid sponsorship needed to try.

## Phases

1. Internal: a handful of friendly users one-on-one, fix what breaks.
2. Alpha: landing page with a waitlist, invite people one by one.
3. Beta: work through the waitlist, tease the problem it solves, ask early users to share.
4. Early access: screenshots and short demo clips in public, collect usage data and feedback, invite in batches.
5. Full launch: open signups, start charging, announce everywhere at once.

A small app can merge phases, never skip the waitlist, it is the launch day audience.

## Launch day touchpoints

Email to the list, a short post with a demo clip on the chosen platforms, in-app note for existing users, the site banner, Product Hunt or a relevant community if prepared, and the user online all day to answer every comment.

## Product Hunt

Worth it for tools aimed at early adopters, not for most consumer mobile apps. Prepare a clear tagline, polished visuals, and a short demo video, engage in the community before launch, reply to every comment on the day, and send the traffic to signup or the waitlist. The spike is short, what lasts is the email addresses captured.

## After launch

- Onboarding emails for new signups, see `onboarding.md`.
- The announcement repeated in the next roundup for those who missed it.
- A comparison page against the main alternative.
- Feedback collected and acted on, then the next launch moment planned.

## Ongoing announcements

| Update | Treatment |
| ------ | --------- |
| Major, new feature or redesign | Full launch, email, post, in-app, store "What's New" |
| Medium, integration or UI improvement | Email to the users it affects, in-app note |
| Minor, fixes and tweaks | Changelog and release notes only |

Space releases out instead of shipping everything at once. When the repository is available, draft the changelog and announcements from merged PRs.

## Questions to ask

What is launching, how big is the audience and the email list, which channels exist already, the timeline, and what worked or failed in past launches.
