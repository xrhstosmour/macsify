# App Store Optimization

## Inputs

The store URL, `apps.apple.com/<country>/app/<name>/id<digits>` or `play.google.com/store/apps/details?id=<package>`, or the metadata straight from the repository, `fastlane/metadata`, App Store Connect, or Play Console exports. Store pages render client-side, so a fetch often misses fields, ask the user to paste what matters or share a screenshot. Screenshots and captions can only be judged from an image.

Indie apps are challengers, no brand people search for, so score against textbook ASO, every character counts.

## Apple App Store

- Indexed: title, 30 characters, subtitle, 30 characters, the hidden keyword field, 100 bytes, in-app purchase names, in-app events, screenshot captions.
- Not indexed: the long description and the promotional text, 170 characters, write those for conversion only. Promotional text changes without a release.
- Keyword field: commas, no spaces, never repeat a word already in the title or subtitle, each word counts once. Bytes, not characters, non-Latin scripts take 2 to 3 bytes each.
- Up to 10 screenshots per device, the first three show in search results and carry most of the decision. Up to 3 preview videos, 15 to 30 seconds, autoplay muted.
- The system review prompt, `AppStore.requestReview(in:)` or the `in_app_review` package on Flutter, shows at most 3 times per year, ask after a success moment.
- Custom product pages and in-app events help discovery once there is traffic to split.

## Google Play

- Indexed: title, 30 characters, short description, 80 characters, full description, 4,000 characters. No hidden keyword field, keywords live in visible text, naturally, stuffing is penalized.
- Title must not carry emojis, all caps, "best", "#1", "free", or calls to action.
- 2 to 8 screenshots per device, feature graphic 1024x500 is required to publish the listing.
- Android vitals affect ranking, keep crash and ANR rates under the bad behavior thresholds in Play Console.
- Store listing experiments test up to 3 variants, run them at least 7 days.

## Audit

Score each 0 to 10, weighted:

| Dimension | Weight | Looks at |
| --------- | ------ | -------- |
| Title and subtitle or short description | 20% | Characters used, keywords, clarity |
| Description | 15% | First three lines, Google keyword use, structure |
| Visuals | 25% | Screenshot count, order, captions that sell an outcome, video, icon |
| Ratings and reviews | 20% | Average, volume, recency, developer replies |
| Freshness and metadata | 10% | Last update, category, localizations, data safety |
| Conversion signals | 10% | Price clarity, in-app purchase transparency |

Always flag: rating under 4.0, no update in 3 months, fewer than 5 screenshots, screenshots that are bare UI with no caption, a title spent on the name alone, subtitle repeating title words, unanswered negative reviews.

## Report

1. Score card with the six dimensions and the total out of 100.
2. Top 3 quick wins under an hour each.
3. Exact rewrites, "subtitle from X to Y", with character counts, never "improve the subtitle".
4. Keyword suggestions with why each matters, Apple and Google listed separately.
5. Screenshot plan, one outcome per screenshot, the first three carry the pitch.
6. What cannot be judged without paid tools, search volume, exact rankings.

Compare against 2 to 3 competitors only when the user asks or gives URLs, and list their keyword gaps.
