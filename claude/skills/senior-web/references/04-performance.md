# Performance

Core Web Vitals in 2026, the critical path, images and fonts, code splitting, speculation rules,
protocols, and performance budgets tied to field measurement.

## Core Web Vitals

The current CWV set is LCP, INP, and CLS. FID was retired in favor of INP in 2024; do not target it.
Thresholds are evaluated at the 75th percentile of page loads, segmented across mobile and desktop.

| Metric | Good | Needs improvement | Poor | Measures |
|---|---|---|---|---|
| LCP (Largest Contentful Paint) | <= 2.5 s | 2.5-4.0 s | > 4.0 s | Loading: when the main content element renders |
| INP (Interaction to Next Paint) | <= 200 ms | 200-500 ms | > 500 ms | Responsiveness: latency of all interactions |
| CLS (Cumulative Layout Shift) | <= 0.1 | 0.1-0.25 | > 0.25 | Stability: unexpected layout movement |

Verify current thresholds upstream; the metric set has changed before (FID to INP) and can change
again.

### Diagnosing LCP

LCP has four phases; find the dominant one before optimizing:

1. **TTFB** — server and network. Fix with CDN caching, edge rendering, and faster backends.
2. **Resource load delay** — time until the LCP resource request starts. Fix with discovery:
   `<link rel="preload">`, no lazy-loading on the hero image, no render-blocking CSS chains.
3. **Resource load duration** — bytes over bandwidth. Fix with compression, modern formats,
   responsive sizes, CDN.
4. **Element render delay** — main-thread work between resource arrival and paint. Fix with smaller
   bundles, fewer blocking scripts, and splitting hydration.

```html
<!-- Hero image: discovered early, high priority, correct size -->
<link rel="preload" as="image" href="/hero.avif" fetchpriority="high" />
<img src="/hero.avif" width="1600" height="900" fetchpriority="high" alt="" decoding="async" />
```

### Diagnosing INP

INP is bounded by the longest interaction, composed of input delay, processing time, and
presentation delay.

- Break long tasks: yield to the main thread (`scheduler.yield()` where available, `setTimeout`
  fallback) between chunks of work.
- Keep event handlers thin; move work off the critical interaction.
- Debounce/throttle high-frequency input (scroll, resize, keydown).
- Avoid layout thrash: batch DOM reads then writes; use `requestAnimationFrame` for visual updates.
- Reduce hydration cost: fewer client components per route, islands, lazy hydration.
- Watch third-party scripts; they are a leading cause of long tasks.

### Diagnosing CLS

- Always set `width`/`height` or `aspect-ratio` on images, videos, iframes, and ads.
- Reserve space for banners, cookie bars, and dynamically injected content.
- Use `font-display: swap` **with** a matched fallback (`size-adjust`, `ascent-override`) to reduce
  swap shift; `optional` where brand fonts are non-critical.
- Never insert content above existing content after load without user action.
- Prefer `transform` animations, which do not trigger layout.

## The Critical Path

1. **HTML** arrives (TTFB).
2. **Render-blocking CSS** is fetched and parsed. Inline critical CSS; defer the rest.
3. **Preload scanner** finds subresources. Keep critical resources reachable in initial HTML;
   JS-injected preloads are discovered late.
4. **JS** is fetched, parsed, compiled, executed, then **hydration** happens.

Practical rules:
- Minimize render-blocking requests to one stylesheet (or inlined critical CSS).
- Serve hashed static assets with `Cache-Control: public, max-age=31536000, immutable`.
- Add `defer` to non-critical scripts; `async` only for independent scripts. Prefer ES modules via
  `<script type="module">` (deferred by default).
- Reduce initial JS: route-level splitting, dynamic `import()`, server components/islands, and
  avoiding barrel files that defeat tree-shaking.

## Images

- Formats: **AVIF** first, **WebP** fallback, original only as last resort. Serve via `<picture>`
  or a framework image component.
- Always provide `srcset`/`sizes`; never send a 2000 px image to a 400 px slot.
- `loading="lazy"` for below-the-fold images; **never** on the LCP candidate.
- `fetchpriority="high"` on the LCP image, `low` on decorative background images.
- Set dimensions or `aspect-ratio` to prevent CLS.
- Use a CDN/image service for resizing and format negotiation; avoid shipping PNG/JPEG heroes.
- Icon strategy: inline SVG sprites or individual SVGs; avoid icon fonts.

```html
<picture>
  <source srcset="/hero.avif 1x, /hero@2x.avif 2x" type="image/avif" />
  <source srcset="/hero.webp 1x, /hero@2x.webp 2x" type="image/webp" />
  <img src="/hero.jpg" width="1200" height="675" alt="Product dashboard" fetchpriority="high" />
</picture>
```

## Fonts

```css
@font-face {
  font-family: "Inter var";
  src: url("/fonts/inter-var.woff2") format("woff2-variations");
  font-weight: 100 900;
  font-display: swap;
  unicode-range: U+0000-00FF, U+0131, U+2000-206F, U+2190-21BB, U+2212;
}

@font-face {
  font-family: "Inter fallback";
  src: local("Arial");
  size-adjust: 107%;
  ascent-override: 90%;
  descent-override: 22%;
  line-gap-override: 0%;
}
```

- Prefer **variable fonts** and subset to the scripts you ship (`unicode-range`).
- Self-host for privacy and to remove a third-party connection; preconnect only if necessary.
- Preload only the primary font file; more preloads compete with LCP.
- Use `font-display: swap` (or `optional` for decorative faces) and a metric-matched fallback to
  keep CLS low.
- Avoid loading more than two families/weights; each is latency.

## Code Splitting and Bundling

- Split by route (automatic in modern frameworks) and by heavyweight, conditionally used features
  (editors, charts, maps, modals).
- Keep shared chunks stable so they cache: vendor chunking is often worth it, but over-splitting
  causes request waterfalls.
- Watch for barrel files (`index.ts` re-exports) and side-effect imports that block tree-shaking.
- Prefer ESM; check `"sideEffects": false` correctness before relying on it.
- Analyze the bundle in CI; fail on size regressions.

```ts
const Chart = lazy(() => import("./Chart")); // loads only when rendered
```

## Speculation Rules

Prefetching and prerendering via the Speculation Rules API can make navigations feel instant.

```html
<script type="speculationrules">
{
  "prerender": [{ "where": { "href_matches": "/products/*" }, "eagerness": "moderate" }],
  "prefetch": [{ "where": { "href_matches": "/*" }, "eagerness": "conservative" }]
}
</script>
```

- Use `conservative` (hover) or `moderate` (pointer down) for most sites; `eager` wastes bandwidth.
- Prerender only same-origin, side-effect-free, authenticated-safe pages. Prerendering a checkout
  or a logout link is a bug.
- Exclude links marked with `data-no-prerender` from ad/tracking-heavy destinations.
- Prefetch uses the HTTP cache; pair with CDN caching to be effective.
- Provide `<link rel="prefetch">` fallback only for targeted resources, not site-wide.

## Protocols and Transport

- **HTTP/2** minimum; **HTTP/3 (QUIC)** where available, especially for high-latency mobile.
- **Compression**: Brotli for text; check whether your CDN supports zstd. Never serve uncompressed
  JS/CSS/HTML.
- **103 Early Hints** to let the client preload critical assets before the full response; requires
  CDN/origin support.
- **Connection reuse**: avoid unnecessary third-party origins; each costs DNS+TLS+RTT.
- **Priority hints**: `fetchpriority` is broadly available; use it deliberately on LCP resources.
- Measure with throttled profiles (slow 4G, mid-range mobile CPU), not a desktop on gigabit.

## Performance Budgets

Budgets are contracts enforced in CI, not aspirations. Start from field data, ratchet down.

| Budget | Suggested starting point | Enforced by |
|---|---|---|
| Initial JS (compressed, per route) | 150-200 KB gzip | bundler analysis, CI check |
| CSS (compressed) | 50-75 KB | bundler analysis |
| LCP (field, p75 mobile) | <= 2.5 s | RUM alert |
| INP (field, p75 mobile) | <= 200 ms | RUM alert |
| CLS (field, p75) | <= 0.1 | RUM alert |
| Hero image bytes | <= 200 KB | asset check |
| Total page weight | <= 1.5-2 MB | Lighthouse CI / bundle bot |

Rules: block merges on regressions above a threshold; track budgets per route template; revisit
quarterly. A budget nobody sees is not a budget.

## Measurement

- **Field (decides)**: CrUX for public sites; RUM (web-vitals library) for your own segmentation by
  route, device, country.
- **Lab (diagnoses)**: Lighthouse CI as a smoke test; WebPageTest for filmstrip and throttled runs;
  DevTools Performance panel for main-thread traces.
- Attribute regressions to deploys by annotating RUM timelines with release markers.
- Measure interactions (`event` timing, long animation frames where available) to catch INP issues
  the lab cannot reproduce.
- Use real-user segmentation: slowest device class and lowest connection should set priorities.

```ts
import { onLCP, onINP, onCLS } from "web-vitals";

onLCP((m) => send("/rum", { name: m.name, value: m.value, id: m.id, route: location.pathname }));
onINP((m) => send("/rum", { name: m.name, value: m.value, route: location.pathname }));
onCLS((m) => send("/rum", { name: m.name, value: m.value, route: location.pathname }));
```

## Anti-Patterns

- Optimizing Lighthouse scores while field CWV fail.
- Lazy-loading the LCP image or using a hero video without a poster.
- Third-party tag managers loading dozens of scripts before content.
- `font-display: block` on body text; invisible text for seconds.
- Shipping a full client-side framework for a content page.
- Re-rendering entire trees on every keystroke/scroll.
- Preloading everything (no preload is a priority signal anymore).
- Measuring only first load and ignoring client-side navigations, which is where INP issues hide.

## Checklist

- [ ] Field RUM reports LCP/INP/CLS with route and device segmentation.
- [ ] LCP element identified per route template; resource discovered in initial HTML.
- [ ] All images have dimensions, modern formats, and responsive `srcset`.
- [ ] Fonts subset, preloaded once, with metric-matched fallback.
- [ ] Bundle budgets enforced in CI with fail thresholds.
- [ ] Long tasks profiled on mid-range hardware; interactions yield.
- [ ] Speculation rules limited to safe, same-origin destinations.
