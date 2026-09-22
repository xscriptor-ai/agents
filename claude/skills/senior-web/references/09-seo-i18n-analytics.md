# SEO, i18n, and Analytics

Technical SEO, structured data, internationalization architecture, analytics instrumentation, and
consent requirements for public web surfaces.

## Technical SEO Foundations

Search engines need to crawl, render, and index your content. Everything here is a prerequisite for
content quality to matter.

- **Crawlability**: `robots.txt` allows what matters; do not block CSS/JS needed for rendering.
  `noindex` on pages that should not appear; use `X-Robots-Tag` for non-HTML resources.
- **Canonical URLs**: one canonical per piece of content. Self-referencing canonicals on indexable
  pages; cross-domain canonicals only when content is truly duplicated. Never canonicalize to a URL
  that redirects or is blocked.
- **Sitemaps**: XML sitemap with last-modified dates; index sitemaps above ~50k URLs; reference from
  `robots.txt`. Update on content change, not per deploy.
- **Redirects**: permanent (301/308) for moved content; chain-free; keep redirect maps in the repo.
- **Status codes**: 404 for truly gone, 410 for permanently removed, no soft-404s (a 200 "not found"
  page is an indexing bug). Never redirect everything to home.
- **Pagination**: use real `<a href>` links; `rel="next/prev"` is no longer a ranking signal but
  crawl paths must exist. Infinite scroll needs crawlable paginated URLs underneath.
- **JavaScript rendering**: serve primary content in server-rendered HTML. Client-only rendering
  risks delayed or partial indexing. Content hidden behind interaction must have a crawlable URL.
- **Performance**: Core Web Vitals are a ranking and UX signal; see
  [04-performance.md](./04-performance.md).
- **HTTPS everywhere**, one hostname, no redirect chains, mobile parity (same content and metadata
  on mobile and desktop).

### Metadata

```html
<title>Primary keyword phrase — Brand</title>
<meta name="description" content="Unique, 120-160 char summary with the value proposition." />
<link rel="canonical" href="https://example.com/products/widget" />
<meta property="og:title" content="..." />
<meta property="og:description" content="..." />
<meta property="og:image" content="https://example.com/og/widget.png" />
<meta property="og:type" content="product" />
<meta name="twitter:card" content="summary_large_image" />
```

- Titles unique per page, front-load the topic; avoid boilerplate prefixes.
- Descriptions are snippets, not ranking factors; write them for click-through.
- OG images: 1200x630, absolute URLs, served over HTTPS. Generate per-entity where feasible.
- In SPAs, update title and meta on route change; use SSR/SSG so crawlers see them immediately.

## Structured Data

Use JSON-LD; it is decoupled from markup and easiest to validate. Model only what is visible on the
page — markup describing hidden content is a violation.

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Product",
  "name": "Widget",
  "image": ["https://example.com/widget.jpg"],
  "offers": {
    "@type": "Offer",
    "price": "29.99",
    "priceCurrency": "USD",
    "availability": "https://schema.org/InStock"
  },
  "aggregateRating": { "@type": "AggregateRating", "ratingValue": "4.6", "reviewCount": "128" }
}
</script>
```

- Common types: `Organization` (site-wide), `WebSite` + `SearchAction`, `BreadcrumbList`, `Product`,
  `Article`, `FAQPage`, `Event`, `Recipe`, `VideoObject`.
- Validate with the Rich Results Test and Schema Markup Validator; monitor Search Console
  enhancement reports.
- Keep fields synchronized with the page; stale prices/ratings cause manual actions.
- Do not mark up every page with every type; irrelevant structured data is noise.

## Internationalization Architecture

Decide locale strategy before writing copy. Retrofitting is expensive and usually botched.

### URL strategy

| Strategy | Example | Pros | Cons |
|---|---|---|---|
| Subdirectory | `example.com/fr/` | Simple, inherits domain authority | One server/edge config |
| Subdomain | `fr.example.com` | Clear separation, easy hosting split | Authority split, DNS/TLS overhead |
| ccTLD | `example.fr` | Strongest geo signal | Expensive, fragmented ops |
| Query param | `example.com?lang=fr` | Easiest | Weak signals, caching confusion |

Subdirectories are the common default for most products. Whatever you choose, **do not auto-redirect
by IP alone**; offer a language selector and remember the choice. Auto-redirecting can hide content
from crawlers and trap users in the wrong locale.

### Signaling

```html
<link rel="alternate" hreflang="en" href="https://example.com/en/page" />
<link rel="alternate" hreflang="fr" href="https://example.com/fr/page" />
<link rel="alternate" hreflang="x-default" href="https://example.com/page" />
<html lang="fr" dir="ltr">
```

- `hreflang` must be reciprocal; each page links all alternates including itself.
- `x-default` for the language-selector/global page.
- `lang` attribute must match the content language; wrong `lang` breaks screen readers and SEO.
- Keep locale in the cache key and in canonical URLs. Do not serve multiple languages from one URL.
- Never translate URLs by machine; keep slugs stable per locale and configured.

### Content pipeline

- Use **ICU MessageFormat** (or equivalent) for plurals, gender, and selects: `{count, plural, one {# item} other {# items}}`.
  Do not concatenate strings.
- Use `Intl` for dates, numbers, currency, relative time, and lists: `Intl.DateTimeFormat`,
  `Intl.NumberFormat`, `Intl.RelativeTimeFormat`, `Intl.ListFormat`, `Intl.PluralRules`.
- Avoid embedding grammar in code; locales have different word orders and cases.
- Translation keys must be stable and namespaced (`checkout.summary.total`); never use English
  source strings as keys if copy may change.
- Ship translations per locale as separate chunks; do not bundle all locales into the main bundle.
- Provide context/screenshots to translators; machine translation plus review only for low-stakes
  content.
- ICU/CLDR data changes; update with the runtime and verify fallback behavior for missing keys
  (fall back to default locale, never show raw keys in production).
- Pseudolocale testing (accented, 150% length) catches truncation and hard-coded strings early.

### Layout and RTL

- Logical CSS properties (`margin-inline`, `inset-inline-start`) so RTL mirrors automatically; see
  [03-css-design-systems.md](./03-css-design-systems.md).
- Design for text expansion: German/Finnish strings run 30-40% longer than English; buttons and nav
  must tolerate it.
- Numbers, dates, and names must not be concatenated into sentence templates. Use full-message
  placeholders.
- Test with the longest locale and an RTL locale (Arabic/Hebrew) as part of the standard QA matrix.

## Analytics

### Event model

Define a small, versioned event schema before instrumenting. Consistency beats volume.

```ts
// One typed helper, one transport; events documented in the repo
type Event =
  | { name: "page_view"; path: string; locale: string }
  | { name: "signup_complete"; method: "email" | "oauth" }
  | { name: "checkout_step"; step: number; cartValue: number };

function track(event: Event) {
  navigator.sendBeacon("/api/events", JSON.stringify(event)); // non-blocking
}
```

- Event names: `noun_verb` (past tense for completed), snake_case, stable forever.
- Properties: primitives only; no PII, no free-text user input, no URL query strings that may
  contain tokens.
- One tracking plan per product; changes reviewed like schema changes. Deprecate, never rename in
  place.
- Client-side tracking loses ad-blocked/offline events; use server-side events for critical
  conversions and reconcile.
- Bot filtering and sampling must be documented; do not mix sampled and unsampled series in one
  dashboard.
- SPAs: track virtual page views explicitly on route change (History API does not fire page loads).

### Privacy and consent

- **GDPR/ePrivacy** (EU/UK): consent required before non-essential cookies/trackers; analytics may
  be exempt only under strict conditions (no cross-site tracking, no personal identifiers) that
  differ by member state — verify with counsel upstream.
- **CCPA/CPRA** and similar: honor Global Privacy Control (GPC) signals and provide opt-out of
  "sale/share".
- Consent banner requirements: reject is as easy as accept (same prominence), granular categories,
  no pre-ticked boxes, no cookie walls, re-ask only after material change, record consent proof
  (timestamp, version, choices).
- Gate scripts: do not load marketing tags before consent; conditional loading is cleaner than
  loading and disabling.
- Data minimization: reduce retention (e.g. 14 months for identifiers), anonymize IPs where
  possible, hash stable identifiers, document subprocessors and cross-border transfers.
- Server-side tagging improves performance and control but does not remove consent requirements.
- Provide a privacy policy that matches actual data flows; review when adding vendors.

### Instrumentation hygiene

- Load analytics asynchronously; never block rendering for measurement.
- Respect Do Not Track and GPC as product decisions, not afterthoughts.
- Sample high-volume events at the pipeline, document the sample rate with the data.
- Keep a debug mode to verify events locally; test consent-denied paths to confirm nothing fires.

## Anti-Patterns

- Client-only rendering of content that must rank.
- Duplicate `<title>`/descriptions across a catalog.
- `noindex` accidentally shipped to production (check robots meta in previews and tests).
- hreflang pointing to 404s, redirects, or non-canonical URLs.
- Machine-translated UI strings with broken pluralization and truncated buttons.
- Storing locale only in a cookie with no URL signal.
- Analytics events with PII or user-entered text.
- Marketing tags firing before consent.
- Counting bots and reporting them as conversions.

## Checklist

- [ ] Server-rendered content; crawlable pagination and internal links.
- [ ] Unique titles/descriptions; self-canonicals; valid sitemap and robots.txt.
- [ ] JSON-LD matches visible content and validates.
- [ ] Locale URLs stable, reciprocal hreflang, correct `lang`/`dir`, ICU/`Intl` formatting.
- [ ] Longest-locale and RTL layouts tested.
- [ ] Event schema versioned, documented, free of PII; server-side paths for critical conversions.
- [ ] Consent gates all non-essential tags; reject as easy as accept; consent state recorded.
- [ ] Privacy policy reflects actual vendors and retention.
