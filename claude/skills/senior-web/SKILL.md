---
name: senior-web
description: 'Web platform reference pack (2026): rendering architectures (SSR, SSG,
  ISR, streaming, RSC, islands, SPA), client and server state, forms and optimistic
  UI, modern CSS and design systems, Core Web Vitals, WCAG 2.2 accessibility, edge
  runtimes, PWAs and offline, browser security, and technical SEO/i18n/analytics.
  Use when designing or reviewing a web front end, choosing a rendering or caching
  strategy, debugging performance, accessibility, or security problems, building offline
  or installable experiences, selecting edge versus origin compute, or making framework
  and deployment decisions for browser-delivered applications.'
---

# Web

Reference pack for building and reviewing browser-delivered applications in 2026. It covers the
full delivery path: how HTML is produced and cached, where state lives, how it is styled, how fast
and accessible it is, where compute runs, what happens when the network fails, and how it stays
secure discoverable, and measurable.

The pack is framework-agnostic but current: examples use React/Next.js, Vue/Nuxt, Astro, SvelteKit,
and standards (HTML, CSS, HTTP) side by side. Treat named tools as examples of a category, not
endorsements. Version numbers are floors/ranges; when an API or limit matters, verify upstream.

## Non-Negotiable Core Rules

1. **Semantic HTML first, ARIA last.** Use the native element that already has the role and
   behavior (`button`, `dialog`, `details`, `nav`, `main`). Hand-rolled widgets are accessibility
   debt unless a reference pattern test proves otherwise.
2. **Render on the server by default; ship JavaScript only where interaction requires it.** The
   cheapest client script is the one never sent. Prefer server components, islands, or plain HTML
   with small enhancement layers.
3. **Accessibility is a correctness requirement, not polish.** WCAG 2.2 AA is the floor for any
   public interface. Keyboard, screen reader, zoom, and reduced-motion paths must work.
4. **The URL is state.** Filters, tabs, pagination, and deep-linkable views belong in the URL, not
   only in memory. Back/forward, refresh, and sharing must reproduce the view.
5. **Every cache has an owner, a TTL, and an invalidation trigger.** If you cannot name how stale
   data becomes fresh, you do not have a caching strategy; you have a bug with a delay.
6. **Measure in the field, not only in the lab.** Field data (CrUX/RUM) decides; Lighthouse is a
   smoke test. Test on mid-range mobile and constrained networks, not just a developer laptop.
7. **Set performance budgets and enforce them in CI.** Bundle size, LCP, INP, and image weight are
   ratchets that fail the build, not dashboard decorations.
8. **Security defaults are deny-by-default.** Strict CSP, `SameSite=Lax` cookies minimum,
   `HttpOnly; Secure`, CORS by explicit allowlist, and no unvetted third-party scripts.
9. **Progressive enhancement where feasible; graceful degradation everywhere.** Content and primary
   flows should survive JS failure, slow hydration, and offline conditions.
10. **Internationalize at design time.** Text expands, languages have plural rules, and layouts
    must mirror for RTL. Retrofitting i18n costs multiples of building it in.
11. **Minimize and pin dependencies; audit the supply chain.** Every runtime dependency is attack
    surface and bytes. Lockfiles, provenance, and SRI for third-party assets are mandatory.
12. **Prefer platform APIs over libraries.** `fetch`, `URL`, `Intl`, `dialog`, `popover`, CSS
    container queries, and view transitions remove code you must maintain.

## Decision Tables

### Rendering strategy at a glance

| Strategy | HTML produced | Best for | Avoid when |
|---|---|---|---|
| SSG | At build | Content sites, docs, marketing | Data changes faster than deploys |
| ISR / revalidate | Build + background | Catalog, CMS, large content sets | Strict per-request personalization |
| SSR (per request) | At request | Auth dashboards, personalized pages | Traffic is static and cost-sensitive |
| Streaming SSR | At request, chunked | Slow data + fast shell | SEO crawlers are the sole consumer and shell is trivial |
| RSC (server components) | Server tree + client islands | Data-heavy React apps | Non-React stacks, heavy client-only UI |
| Islands | Static + hydrated widgets | Content-first sites with interactive parts | App-like UI with pervasive interactivity |
| SPA (CSR only) | Empty shell | Auth-only internal apps, no SEO need | Public, SEO-sensitive, slow devices |

### Where state belongs

| State kind | Home | Examples |
|---|---|---|
| Navigational | URL | filters, sort, page, tab, selected entity |
| Server data | Data cache keyed by URL/query | lists, profiles, dashboards |
| Form draft | Component + URL for steps | wizard progress, validation state |
| Ephemeral UI | Component state | open menus, hover, transient input |
| Cross-cutting client | Small store / context | theme, locale, session identity |
| Persistent user prefs | Cookie or `localStorage` | theme choice, dismissed banners |

### CSS strategy

| Approach | Strength | Cost |
|---|---|---|
| Utility CSS (Tailwind) | Consistency, no dead CSS, fast iteration | Verbose markup; design encoded in config |
| CSS Modules | Locality, plain CSS, zero runtime | Class name indirection; no token system by itself |
| Vanilla-extract / typed CSS | Types + tokens + static extraction | Build coupling; learning curve |
| CSS-in-JS runtime | Dynamic theming, co-location | Runtime cost; avoid for new work |
| Native CSS (layers, nesting, `:has`) | Zero tooling, future-proof | Team discipline required |

### Compute placement

| Need | Edge | Origin |
|---|---|---|
| Header/auth rewrite, geo, A/B | Yes | Possible but slower |
| Read-mostly cached data | Yes (KV/D1/R2) | Yes |
| Heavy CPU, native modules, large bundles | No | Yes |
| Multi-row transactions, strict consistency | No | Yes |
| Long-running jobs, queues, cron | No | Yes |

### Cache layers (typical stack)

| Layer | Keyed by | Invalidate with |
|---|---|---|
| CDN / HTTP cache | URL + `Vary` + method | `Cache-Control`, purge API, surrogate keys |
| Framework route cache | route + params | `revalidate`, tag/path invalidation |
| Data cache | query + args | tag-based revalidation, TTL |
| Browser memory cache | in-flight dedupe | refetch on focus/mount as configured |
| Service worker | request + strategy | versioned precache, `skipWaiting` on deploy |

## Reference Index

| File | Scope | Load when |
|---|---|---|
| [references/01-architecture-rendering.md](./references/01-architecture-rendering.md) | SSR, SSG, ISR, streaming, RSC, islands, SPA; caching layers and revalidation | Choosing a rendering mode, designing caching, migrating between architectures |
| [references/02-state-data.md](./references/02-state-data.md) | Client vs server state, forms, URL state, optimistic UI, fetch/cache/invalidate patterns | Wiring data flow, forms, or state management in any framework |
| [references/03-css-design-systems.md](./references/03-css-design-systems.md) | Cascade layers, container queries, `:has`, nesting, OKLCH, logical properties, tokens, theming | Building or reviewing styling architecture, tokens, or theming |
| [references/04-performance.md](./references/04-performance.md) | Core Web Vitals, critical path, images/fonts, splitting, speculation rules, budgets | Diagnosing slow pages, setting budgets, optimizing LCP/INP/CLS |
| [references/05-accessibility.md](./references/05-accessibility.md) | WCAG 2.2 AA, semantic HTML, ARIA patterns, keyboard/focus, SR testing | Any UI review, new component, audit, or compliance question |
| [references/06-edge-runtimes.md](./references/06-edge-runtimes.md) | Edge functions/workers landscape, limits, storage, latency patterns | Deciding edge vs origin, writing middleware, debugging edge limits |
| [references/07-pwa-offline.md](./references/07-pwa-offline.md) | Service workers, caching strategies, offline UX, background sync, push, installability | Building offline-capable or installable web apps |
| [references/08-security.md](./references/08-security.md) | CSP, Trusted Types, CORS, cookies, CSRF, third parties, headers, supply chain | Threat modeling, hardening headers, handling auth and third-party scripts |
| [references/09-seo-i18n-analytics.md](./references/09-seo-i18n-analytics.md) | Technical SEO, structured data, i18n architecture, analytics, consent | Launching public pages, adding locales, or instrumenting analytics |

## How to Use This Pack

- Start from the decision tables above, then load exactly the references the task needs.
- For a new product surface, load 01 (rendering) and 02 (state) first; load 04, 05, and 08 before
  launch.
- For reviews, load the reference matching the defect class; do not load all nine by default.
- References cross-link each other with relative paths; follow those links when a topic borders
  another domain.

## Port

- **Port id** — `skill://senior/web` (version in `metadata.port-version`).
- **Kind** — read-only reference pack; no side effects, no tools, no scripts required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "web" })` in OpenCode; Claude Code reads
     `<skills-dir>/web/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the
     degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers
  reference it as `load skill senior-web (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major.
