# Frontend Performance

Scope: bundles, Core Web Vitals and INP, images and fonts, hydration cost, rendering performance, and measurement tooling for web frontends.

## Field Data First

- Core Web Vitals are assessed on field data at the 75th percentile, segmented by mobile and desktop. Lab scores are diagnostic, not the goal.
- Track real-user monitoring (RUM) with the `web-vitals` library or equivalent; align metric definitions with CrUX so dashboards and search tooling agree.
- Lab tools (Lighthouse, WebPageTest, DevTools) explain causes; field data decides whether users are actually affected.
- Keep a lab budget in CI for regressions and field alerts for reality. Neither replaces the other.

| Metric | Good | Needs improvement | Poor | Measures |
|---|---|---|---|---|
| LCP | <= 2.5 s | 2.5-4.0 s | > 4.0 s | Loading: largest visible element |
| INP | <= 200 ms | 200-500 ms | > 500 ms | Responsiveness across interactions |
| CLS | <= 0.1 | 0.1-0.25 | > 0.25 | Visual stability |
| TTFB | <= 0.8 s | 0.8-1.8 s | > 1.8 s | Server and network latency |
| FCP | <= 1.8 s | 1.8-3.0 s | > 3.0 s | First content painted |

- INP replaced FID as a Core Web Vital in 2024; FID is retired. Use INP plus TTFB as the working pair.
- Report distributions and the worst interactions, not just a page-level average; INP is scored per interaction and reported as a high percentile.

## LCP: Loading

LCP decomposes into four phases; optimize the largest one you control:

| Phase | Levers |
|---|---|
| Time to first byte | Server rendering, caching, CDN, edge, database. See `./02-caching.md` and `./03-databases.md` |
| Resource load delay | Discoverability: preload, early hints, no render-blocking chains |
| Resource load time | Compression, format, smaller payloads, faster origin |
| Element render delay | Unblock the main thread; avoid lazy-loading the LCP element |

- Identify the LCP element per template (hero image, heading, video poster) and optimize that specific resource.
- Preload the LCP image or font with `fetchpriority="high"`; never lazy-load an above-the-fold LCP element.
- Serve modern formats (AVIF, WebP) with fallbacks and correct `srcset`/`sizes`; let a CDN transform and cache derivatives.
- Avoid render-blocking third-party scripts before the LCP; defer, async, or move them behind interaction facades.
- Streaming SSR and server components can improve TTFB and LCP together; measure per template rather than trusting a framework default.

## INP: Responsiveness

INP measures the latency from user input to the next paint across the interaction.

- Break long tasks into smaller chunks; keep any single task well under 50 ms to stay responsive. Use `scheduler.yield()` where available, and a `setTimeout`/`MessageChannel` fallback otherwise; verify browser support upstream.
- Move expensive work off the main thread: Web Workers for parsing, computation, and search indexes.
- Keep event handlers thin: capture the input, update state minimally, and schedule the heavy work. Avoid synchronous layout reads in handlers.
- Debounce expensive work but never the visual response; the interface should acknowledge input immediately.
- Third-party scripts are a leading cause of long tasks: load analytics and tag managers late, with size and CPU budgets, and prefer server-side or first-party wrappers.
- Measure with the Long Animation Frames (LoAF) API and `PerformanceObserver` where supported; attribute the worst interactions to scripts and frames.

## CLS: Stability

- Reserve space for images and media with explicit `width`/`height` or `aspect-ratio`.
- Reserve space for ads, embeds, banners, and consent dialogs; late-inserted content is the common cause of CLS.
- Avoid inserting content above existing content unless triggered by user interaction.
- Prefer `transform` and `opacity` animations; they stay on the compositor and do not shift layout.
- Use font fallback metric tuning (`size-adjust`, `ascent-override`) to reduce reflow when the web font swaps in.

## Bundles

| Technique | Typical effect | Notes |
|---|---|---|
| Dependency audit and dedupe | Removes duplicate versions and dead weight | Check package manager aliases and lockfile duplicates |
| Tree shaking | Drops unused exports | Requires ESM and side-effect-free modules |
| Route-level code splitting | Loads only what the route needs | Lazy boundaries per route and heavy component |
| Dynamic import for rare UI | Defers modals, editors, charts | Prefetch on intent where possible |
| Compression (Brotli preferred) | Large transfer reduction | `Content-Encoding` with correct Vary |
| HTTP/2 or HTTP/3 | Multiplexing, fewer round trips | Keep request count sane; no domain sharding |
| Long-term caching | Repeat visits near zero transfer | Content-hash filenames plus immutable caching |
| Polyfill trimming | Drops legacy JavaScript | Ship modern bundles to modern browsers |

- Analyze the bundle before optimizing: a visualizer, `source-map-explorer`-style tools, or framework bundle analysis. React to the biggest rectangles, not to raw total size.
- Watch for duplicate framework copies and full-library imports (`lodash`-style) where per-function imports exist.
- Budget per route and per entry: initial JavaScript (compressed), total fonts, total images, third-party count.
- Do not ship source maps publicly unless intended; use hidden maps for error reporting.
- Evaluate dependencies by cost, not popularity: a date library or icon set can outweigh application code.

## Resource Loading Strategy

| Hint | Use |
|---|---|
| `preload` | Critical late-discovered resources (LCP image, hero font, critical CSS) |
| `preconnect` | Origins needed early (font, API, CDN) |
| `dns-prefetch` | Cheap fallback for origins likely needed |
| `prefetch` | Next navigation resources for likely paths |
| `modulepreload` | ESM entry chunks and their dependencies |
| `fetchpriority="high"` | The LCP image or critical script; use sparingly |
| Lazy loading | Below-the-fold images and iframes only |

- Every hint is a resource claim: too many preloads compete for bandwidth and delay the critical path.
- Inline critical CSS and defer the rest; avoid shipping a large stylesheet that blocks first paint.
- Use early hints (103) only when the origin can support them correctly; verify behavior at the CDN upstream.

## Images and Fonts

- Images usually dominate transfer weight. Set explicit dimensions, use responsive `srcset`/`sizes`, and serve formats matched to device capability.
- Lazy-load below-the-fold images with native `loading="lazy"`; keep above-the-fold and LCP images eager with high priority.
- Use a CDN image pipeline for resize, format negotiation, and caching instead of runtime transforms.
- Fonts: prefer `woff2`, self-host for control and privacy, subset to the scripts actually used, and preload only the critical face.
- `font-display: swap` trades a flash of unstyled text for no invisible text; tune with fallback metrics so the swap does not shift layout.
- Variable fonts reduce file count but can carry large glyph sets; subset aggressively.
- Avoid icon fonts; inline SVG or sprite sheets render faster and are more accessible.

## Rendering Performance

- Avoid layout thrash: batch DOM reads before writes; never interleave `getBoundingClientRect`-style reads with style mutations in a loop.
- Reduce DOM size and depth; huge trees slow style recalculation, layout, and reconciliation. Virtualize long lists.
- Use CSS containment (`contain`, `content-visibility: auto`) for large offscreen sections, and verify paint behavior.
- Animate only compositor-friendly properties (`transform`, `opacity`); avoid animating layout properties (`width`, `top`, `margin`).
- Keep `will-change` off long-lived elements; promote layers only around active animations.
- In component frameworks, memoize expensive subtrees deliberately, keep state local to avoid broad re-renders, and profile renders rather than guessing. Framework-specific devtools exist; use them.

## Hydration and SSR Cost

- Server rendering improves first paint but hydration re-executes component code on the client, which costs main-thread time and hurts INP.
- Choose the rendering model per route: static, SSR, streaming, islands, partial hydration, or client-only. Mixed models are normal in 2026-era frameworks; verify what your framework version supports upstream.
- Keep server-only data out of client bundles; serialized payloads are easy to duplicate and expensive to parse.
- Hydration mismatches cause re-renders and layout shifts; keep server and client output deterministic (avoid `Date.now()`, random ids, locale-dependent formatting on first render).
- Islands and partial hydration restrict interactivity to the components that need it; restructure components to make that boundary possible.
- Consider progressive enhancement: the page should be usable before hydration completes, at least for reading and navigation.

## Third-Party Scripts

- Treat every third party as a performance dependency with a budget: count, bytes, main-thread time, and failure mode.
- Load non-critical tags behind interaction facades (click-to-load maps, video players, chat widgets) or after `load`, idle, or first interaction.
- Prefer first-party or server-side integrations over client-side tags where the data flow allows.
- Sandbox third-party scripts in iframes where possible; verify supply-chain and consent requirements. Cross-pack: the security pack covers third-party risk.
- Audit tags quarterly; stale marketing tags are a common source of silent regressions.

## Measurement Tools

| Tool | Mode | Use for |
|---|---|---|
| Chrome DevTools Performance / Insights | Lab, per session | Long tasks, layout, INP attribution on a reproduction |
| Lighthouse / PageSpeed Insights | Lab | Category diagnosis and CI regression checks |
| WebPageTest | Lab, controlled | Filmstrips, network shaping, multi-run variance |
| `web-vitals` + RUM endpoint | Field | Real Core Web Vitals with attribution |
| CrUX / CrUX History | Field | Competitor and origin-level baseline |
| LoAF plus `PerformanceObserver` | Field | Script and frame attribution for INP |
| Bundle analyzers | Build | Bundle composition and duplication |

- Instrument with real devices and throttling that matches your audience; fast desktops hide mobile INP problems.
- Segment RUM by route, device, connection, and release; aggregate scores hide the templates that hurt.
- Keep synthetic and field definitions aligned to avoid chasing phantom regressions.

## Budgets and CI

- Set budgets per route and entry: JavaScript compressed, CSS, images, fonts, third-party requests, and metric thresholds.
- Enforce with Lighthouse CI assertions, bundle-size checks, and field alerts. Fail builds on budget breaches before merge.
- Track budgets over releases to catch slow creep; small regressions compound and are harder to attribute later.
- Re-baseline deliberately after intentional redesigns, with a recorded decision.

## Anti-Patterns

- Optimizing to a green Lighthouse score while field 75th percentile INP or LCP stays poor.
- Lazy-loading the LCP element.
- Shipping a full component library and a tag manager before any content renders.
- Synchronous, layout-reading event handlers.
- Hydrating the entire page for one interactive widget.
- Unbounded third-party scripts with no budget or owner.
- Animating layout properties and shifting content.
- Measuring on a fast machine with warm caches and calling it done.
- Adding preload hints to everything until the critical path is congested.

## Checklist

- [ ] Field RUM tracks LCP, INP, and CLS with 75th-percentile reporting by segment.
- [ ] The LCP element per template is identified and explicitly prioritized.
- [ ] INP long tasks are attributed to scripts; third-party work moved off the critical path.
- [ ] Images have dimensions, responsive sources, and modern formats above the fold.
- [ ] Fonts are subset, self-hosted where practical, and styled to avoid layout shift.
- [ ] Bundles are split by route; duplicate and unused dependencies removed.
- [ ] Hydration model chosen per route; server data not duplicated into client bundles.
- [ ] Budgets enforced in CI with field alerts in production.
- [ ] Third-party scripts have owners, budgets, and facades.
- [ ] Release process re-measures field metrics after deploy.
