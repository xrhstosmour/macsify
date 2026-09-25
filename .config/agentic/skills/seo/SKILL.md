---
name: seo
description: >
  Technical SEO, content quality/E-E-A-T, schema markup, sitemap, image SEO,
  and AI-search (GEO/AEO) analysis for any URL or page content. Use when the
  user says "SEO", "SEO audit", "technical SEO", "Core Web Vitals", "schema
  markup", "structured data", "JSON-LD", "sitemap", "robots.txt", "E-E-A-T",
  "content quality", "alt text", "image SEO", "AI Overviews", "GEO", "AEO",
  "llms.txt", "AI citations", or asks to audit/optimize a page or site for
  search engines.
---

# SEO Analysis

Search behavior changes faster than this file does, and nothing re-checks it. Treat
the thresholds, crawler tokens, schema type status, and platform claims below as
unverified: confirm anything load-bearing against the live source before reporting
it as current.

## When to use

- The user gives a URL and asks for an SEO audit, health check, or "what's
  wrong with this page for SEO".
- The user asks about a specific slice: technical SEO, schema/structured
  data, content quality/E-E-A-T, sitemap, image optimization, or AI-search
  visibility (GEO/AEO/AI Overviews).
- The user pastes HTML, a sitemap, or robots.txt and wants it checked.

Not for keyword research, paid ad campaigns, or backlink acquisition — this
skill covers on-site and technical factors only (see "Backlinks" for why
off-site link data is out of scope).

## Fetching & tooling

No dedicated runtime is installed for this skill — use what's already
available:

- **WebFetch** for a first read of a page: rendered-to-markdown content,
  general structure, obvious issues.
- **`curl`** (via Bash) when byte-exact data matters and WebFetch's
  model-summarized output would lose it: response headers (`curl -sI`),
  `robots.txt`, `sitemap.xml`, raw HTML for schema extraction.
- **`scripts/check_schema.py`** and **`scripts/check_sitemap.py`** (this
  skill's directory) for structured validation that plain-text inspection
  gets wrong in practice (JSON-LD parsing, sitemap XML caps). Both read
  already-fetched content from a file or stdin and make no network calls of
  their own:

  ```bash
  curl -s "$URL" -o /tmp/page.html
  python3 "$SKILL_DIR/scripts/check_schema.py" /tmp/page.html

  curl -s "$URL/sitemap.xml" -o /tmp/sitemap.xml
  python3 "$SKILL_DIR/scripts/check_sitemap.py" /tmp/sitemap.xml
  ```

  (Replace `$SKILL_DIR` with this skill's actual directory path.)

- **Core Web Vitals**: call the public PageSpeed Insights API directly —
  works without a key at low volume, or with a key via the `GOOGLE_API_KEY`
  env var if the user has one:

  ```bash
  curl -s "https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=$URL&category=performance${GOOGLE_API_KEY:+&key=$GOOGLE_API_KEY}"
  ```

  If this fails or is rate-limited, say so plainly rather than guessing at
  scores — see the error-handling table.

**No headless browser is available.** For JavaScript-heavy/SPA pages, fetched
HTML may not reflect what a user actually sees. Heuristic: if `<body>` is
mostly empty apart from a root `<div>` and heavy `<script>` bundles, flag the
page as likely client-side rendered and note that findings on visible content
are unreliable until the user provides rendered HTML or a screenshot.

## Technical SEO

Check in this order — an upstream defect here invalidates content/schema work
downstream:

1. **Crawlability**: `robots.txt` exists and isn't blocking important paths;
   XML sitemap declared and reachable; no accidental `noindex`; important
   pages reachable within ~3 clicks of the homepage.
2. **Indexability**: canonical tags are self-referencing and don't conflict
   with `noindex`; watch for near-duplicate/parameter-URL content and
   `www` vs non-`www` inconsistency.
3. **Security**: HTTPS enforced with a valid cert, no mixed content; security
   headers present (`Content-Security-Policy`, `Strict-Transport-Security`,
   `X-Content-Type-Options`, `Referrer-Policy`). Treat these as good hygiene,
   not high-impact ranking signals — HTTPS itself affects well under 1% of
   queries as a direct signal.
4. **URL structure**: descriptive, hyphenated, no unnecessary query params;
   redirect chains no more than one hop; flag URLs over ~100 characters.
5. **Mobile / page experience**: viewport meta tag, responsive layout, touch
   targets ≥48px, no horizontal scroll. Mobile-first indexing is the default
   — check that mobile content, meta tags, and structured data match desktop
   (parity gaps are the real risk, not simple exclusion from the index).
6. **Core Web Vitals** — current thresholds:

   | Metric | Good | Needs Improvement | Poor |
   |---|---|---|---|
   | LCP (Largest Contentful Paint) | ≤2.5s | 2.5–4.0s | >4.0s |
   | INP (Interaction to Next Paint) | ≤200ms | 200–500ms | >500ms |
   | CLS (Cumulative Layout Shift) | ≤0.1 | 0.1–0.25 | >0.25 |

   INP replaced FID in 2024 — never reference FID. Evaluation uses the 75th
   percentile of real-user (CrUX field) data; lab tools like Lighthouse are
   useful for debugging *why*, not for the score Google actually uses.
7. **Structured data**: see the Schema section below.
8. **JavaScript rendering**: check whether critical content, canonical tags,
   `noindex`, and structured data are present in the *raw* server-rendered
   HTML, not only injected by JS. Google may use either version if they
   conflict, and does not render JS at all on non-200 responses — so
   time-sensitive markup (Product/Offer especially) belongs in the initial
   HTML.
9. **IndexNow**: note whether the site pings IndexNow (Bing/Yandex support
   it; Google doesn't) — a cheap win for faster non-Google indexing.

**AI crawlers vs. search crawlers in `robots.txt`** — these are separate
concerns and get conflated constantly:

| Token | Owner | Purpose | Obeys robots.txt |
|---|---|---|---|
| `Googlebot` | Google | Search indexing | yes |
| `Google-Extended` | Google | Gemini/AI training (not search) | yes |
| `GPTBot` | OpenAI | Model training | yes |
| `ChatGPT-User` | OpenAI | Live browsing on a user's behalf | no (user-triggered) |
| `ClaudeBot` | Anthropic | Model training / Claude web features | yes |
| `PerplexityBot` | Perplexity | Search index + training | yes |
| `CCBot` | Common Crawl | Open dataset | yes |

Blocking `Google-Extended` stops Gemini training use but has **no effect** on
Search indexing or AI Overviews (those run on `Googlebot`). User-triggered
fetchers (`ChatGPT-User`, and similarly Google's agentic-browsing fetchers)
ignore `robots.txt` by design — they can only be gated server-side.

## Content quality & E-E-A-T

Before scoring, run Google's own **Who / How / Why** test from its
helpful-content guidance:

| Question | Look for |
|---|---|
| **Who** created it? | Visible byline, author bio, credentials — non-negotiable for YMYL (health, finance, legal, civic) topics. |
| **How** was it made? | Original research, first-hand evidence, disclosed process — especially where AI assistance is plausible. |
| **Why** does it exist? | To help the reader, not to farm search clicks or hit a word-count target. |

If all three come back weak, flag the page as at risk under Google's
helpfulness/core-ranking signals regardless of any other score.

**E-E-A-T** (Experience, Expertise, Authoritativeness, Trustworthiness).
Google states only that Trust is "the most important member of the family"
and publishes no numeric weights — use this internal scoring split rather
than an even 25/25/25/25, since an even split contradicts that stated
hierarchy:

| Pillar | Weight | Signals |
|---|---|---|
| Experience | 20 | First-hand detail, original photos/data, specific anecdotes that couldn't be fabricated. |
| Expertise | 25 | Author credentials, technical accuracy, sourced claims. |
| Authoritativeness | 25 | External citations, industry recognition, consistent publication history. |
| Trustworthiness | 30 | Contact info, HTTPS, privacy policy, transparent authorship, no deceptive patterns. |

AI-generated content is not penalized for being AI-generated — it's
penalized for being generic, unsourced, or repetitive across pages. Judge on
those markers, not on authorship method.

**Quality gates** (treat word counts as topical-coverage floors, not ranking
targets — Google has confirmed word count itself isn't a ranking factor):

| Element | Guidance |
|---|---|
| Title tag | 30–60 characters, primary keyword near the front, unique per page |
| Meta description | 120–160 characters, includes a reason to click |
| Homepage | ~500+ words covering the value proposition |
| Service/feature page | ~800+ words |
| Blog post | ~1,500+ words for genuinely in-depth topics |
| Image alt text | 10–125 characters, describes the image, never "image.jpg" or keyword-stuffed |
| Internal links | 3–10 per page depending on length, descriptive anchor text, no orphan pages |
| Freshness | Publish date visible; flag fast-moving topics untouched for 12+ months |

## Schema / structured data

1. Detect existing markup: JSON-LD (`<script type="application/ld+json">`)
   preferred, then Microdata, then RDFa. Always recommend migrating to
   JSON-LD if another format is found.
2. Validate: `@context` is `https://schema.org`, `@type` is a real
   non-deprecated type, required properties present, URLs absolute, dates
   ISO-8601, no placeholder text left in. Use `scripts/check_schema.py` on
   the raw HTML for this rather than eyeballing it.
3. Check against current type status:

   | Status | Types |
   |---|---|
   | Active — recommend freely | Organization, LocalBusiness, Product, Offer, Service, Article/BlogPosting/NewsArticle, Review, AggregateRating, BreadcrumbList, WebSite, WebPage, Person, VideoObject, ImageObject, Event, JobPosting, Course, QAPage |
   | No Google rich result, not harmful | FAQPage — Google restricted FAQ rich results to a small set of authoritative sites in August 2023; keep existing markup as info-level, don't add new FAQPage expecting a SERP benefit. For genuine user Q&A, use QAPage instead. |
   | Deprecated — never recommend | HowTo, SpecialAnnouncement, ClaimReview, VehicleListing |

4. Generate JSON-LD only with truthful data; mark anything the user must fill
   in with an obvious placeholder like `"[Company Name]"`.

Minimal templates to adapt:

```json
{
  "@context": "https://schema.org",
  "@type": "Organization",
  "name": "[Company Name]",
  "url": "[Website URL]",
  "logo": "[Logo URL]",
  "sameAs": ["[Social profile URLs]"]
}
```

```json
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "[Title]",
  "author": { "@type": "Person", "name": "[Author Name]" },
  "datePublished": "[YYYY-MM-DD]",
  "dateModified": "[YYYY-MM-DD]",
  "image": "[Image URL]"
}
```

## Sitemap

1. Discover: check `robots.txt` for a `Sitemap:` line first, then fall back
   to common paths (`/sitemap.xml`, `/sitemap_index.xml`) if the declared one
   is missing or stale. Don't report "no sitemap" until both have failed.
2. Fetch it and run `scripts/check_sitemap.py` against the saved file to
   validate structure rather than eyeballing raw XML.
3. Rules the script and your review should both apply:
   - Hard cap: 50,000 URLs **or** 50MB uncompressed per file, whichever hits
     first — split with a sitemap index above that.
   - News sitemaps: 1,000 entries max, articles from the last 2 days only.
   - `<lastmod>` must be valid ISO-8601 and reflect a real content change —
     Google ignores it if values look uniform or newer than the actual
     content.
   - `<priority>` and `<changefreq>` are both ignored by Google — flag as
     informational only, not worth fixing urgently.
   - Every URL should be canonical, indexable, HTTPS, and return 200 — no
     redirected or noindexed URLs belong in the sitemap.

## Images

| Check | Guidance |
|---|---|
| Alt text | Present on every non-decorative `<img>`, 10–125 chars, describes the image |
| File size | Thumbnails <50KB, content images <100KB, hero/banner <200KB (targets; flag at 2-3x these as critical) |
| Format | WebP/AVIF preferred, JPEG fallback via `<picture>`, SVG for icons/logos |
| Responsive | `srcset`/`sizes` present for images shown at varying widths |
| Lazy loading | `loading="lazy"` on below-fold images only — never on the LCP/hero image, it delays paint |

## GEO / AI-search optimization (AI Overviews, AI Mode, ChatGPT, Perplexity)

Google's own position: optimizing for generative AI search **is still SEO**,
not a separate discipline — AEO/GEO are rebranded labels for the same
fundamentals (quotability, structure, freshness, entity clarity) applied to
AI-search surfaces. Frame findings that way rather than as a new toolkit.

- **Citability**: aim for self-contained 100–170 word answer blocks that
  state a fact or definition up front ("X is...") rather than burying the
  answer at the end of a paragraph. Front-load the most citable content —
  a large share of AI citations come from early in the page.
- **Structure**: clean H1→H2→H3 hierarchy, question-phrased headings, short
  paragraphs, tables for comparative data. Structure is a bigger lever here
  than for classic SEO because extraction (not just ranking) depends on it.
- **Authority/brand**: byline with credentials, visible publish/update
  dates, citations to primary sources. Recency matters more here than in
  classic search — content untouched for 6+ months loses citation
  eligibility faster than it loses rankings.
- **AI crawler access**: see the robots.txt table in Technical SEO. Decide
  deliberately whether to allow training crawlers (`GPTBot`, `Google-
  Extended`) vs. search/citation crawlers (`ChatGPT-User`, `PerplexityBot`)
  — blocking one doesn't block the other.
- **`llms.txt`**: be honest about this. Google has stated explicitly that
  Google Search, including its AI features, ignores `llms.txt` entirely — it
  neither helps nor hurts Google visibility. It's harmless to add for other
  AI crawlers that do read it, but never sell it as a Google ranking or
  citation lever.
- **Server-side rendering**: AI crawlers generally don't execute JavaScript.
  Critical content and schema need to be in the raw HTML, same requirement
  as classic technical SEO above.

## Local SEO basics

For local/location-based businesses, without any Maps/GBP API access:

- **Google Business Profile** signals dominate local-pack ranking — primary
  category accuracy, keyword-appropriate business title, verified status,
  and NAP (Name/Address/Phone) consistency across the web are the highest-
  leverage items an audit can flag from the outside.
- **Reviews**: recency and velocity matter more than raw volume — a listing
  with no new reviews in three weeks tends to lose local-pack visibility
  even with a strong historical review count.
- **On-page**: dedicated, unique location pages (not city-name-swapped
  templates) with genuine local information — see the doorway-page risk
  note under Content quality.

This is deliberately shallow — real local SEO work (GBP audits, citation
building, review management) needs GBP dashboard or paid-API access this
skill doesn't have.

## Backlinks

Be upfront about this limitation rather than faking an analysis: there is no
reliable, free, no-signup source of backlink data. Public options either
need a paid API key (Ahrefs, SEMrush, DataForSEO — all out of scope here) or
a free-tier signup (Moz, Bing Webmaster Tools) that this skill doesn't
integrate with. If the user has exported backlink data from a tool they
already use (Search Console, Ahrefs, Moz), analyze that directly instead —
don't attempt to reconstruct a backlink profile from scratch.

## Audit synthesis

For a full audit (multiple sections above), don't just concatenate findings —
walk through four phases before writing the action plan:

1. **Observe**: collect findings per section above without prioritizing yet.
2. **Analyze**: find the highest-leverage constraint — often one technical
   defect (non-indexable, broken canonical, missing HTTPS) that gates
   everything downstream. That goes first regardless of how "interesting"
   other findings are. Connect findings across sections that reinforce each
   other (e.g. a missing Product schema plus thin product-page content are
   one recommendation, not two).
3. **Validate**: pressure-test each recommendation against user experience,
   the site's existing voice, and whether the team can realistically ship it
   — a recommendation with no realistic execution path isn't done yet.
4. **Act**: produce the artifact (report, generated schema, action plan) —
   don't stop at analysis. Note what a follow-up check should look for.

## Output format

```
### SEO Health: <pass | warn | fail>

The overall verdict is the worst category status below, nothing more. Don't compute
a numeric score, there is no defined formula for one and an invented number reads as
measured when it isn't.

| Category | Status | Notes |
|---|---|---|
| Technical | pass/warn/fail | ... |
| Content / E-E-A-T | pass/warn/fail | ... |
| Schema | pass/warn/fail | ... |
| Sitemap | pass/warn/fail | ... |
| Images | pass/warn/fail | ... |
| AI-search (GEO) | pass/warn/fail | ... |

### Critical (fix immediately)
### High (fix within a week)
### Medium (fix within a month)
### Low / backlog
```

For a narrow question (just schema, just sitemap, etc.), skip the table and answer
directly — don't force an overall verdict onto a single-category ask.

## Error handling

| Scenario | Action |
|---|---|
| URL unreachable | Report the exact error/status code. Don't guess at content. |
| `robots.txt`/sitemap missing | Try common fallback paths before reporting "not found". |
| Paywalled/gated content (401/402/403, login wall) | Analyze only what's publicly visible (meta tags, headers); say what's out of reach. |
| CWV/PageSpeed data unavailable | Say so plainly (common for low-traffic sites); Lighthouse lab data is a fallback proxy, not a substitute, for the field-data score. |
| Likely JS-rendered/SPA content | Flag the rendering limitation per the heuristic above rather than reporting on content that may not reflect what users see. |
| No backlink data source available | Say so directly; offer to analyze data the user provides instead. |
