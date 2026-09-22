# Architecture and Rendering

How HTML reaches the browser: SSR, SSG, ISR, streaming, RSC, islands, SPA, and the cache and
revalidation layers that surround them.

## The Mental Model

Every page decision reduces to four questions:

1. **When is the HTML produced?** Build time, first request, every request, or never (client-only).
2. **Where is the data fetched?** Database/API at render time, at request time, or in the browser.
3. **How much JavaScript ships?** None, islands, route-level, or whole-app hydration.
4. **What is cached at which layer, and how is it invalidated?**

Pick the answers per route, not per app. A marketing page, a product listing, and an account
dashboard in the same codebase can and should use different strategies.

## Rendering Modes

### Static Site Generation (SSG)

HTML is produced once at build time and served from a CDN. Fastest possible TTFB and the simplest
cache story. Correct for docs, blogs, marketing, and any content that changes on deploy cadence.

```ts
// Build-time data in Next.js App Router (default for static routes)
export default async function Page() {
  const posts = await getPosts(); // runs at build unless dynamic APIs are used
  return <PostList posts={posts} />;
}
```

Trade-offs: rebuilds are required for content changes; large sites pay build-time cost; per-user
content is impossible without client-side fetching.

### Incremental Static Regeneration (ISR)

Static output regenerated on a schedule or on demand. The page serves a cached HTML artifact; a
background job refreshes it after the revalidation window.

```ts
export const revalidate = 60; // seconds; also settable per fetch
// On-demand: revalidateTag("products") / revalidatePath("/products")
```

Wins for large catalogs, CMS content, and pages where "a few minutes stale" is acceptable. The
hard part is invalidation: tag content at write time so a single mutation can purge exactly the
affected routes. Pair with [09-seo-i18n-analytics.md](./09-seo-i18n-analytics.md) when content
pages drive acquisition.

### Server-Side Rendering (SSR)

HTML produced per request. Necessary for authenticated, personalized, or fast-changing data.
Costs compute per request and needs care with cache headers to avoid thundering herds.

Best practices:
- Keep the request path fast: parallelize data calls, avoid waterfalls.
- Set explicit `Cache-Control`; consider `stale-while-revalidate` at the CDN for semi-personal data.
- Separate the personalized shell from cacheable fragments where possible.

### Streaming SSR

Send the document shell immediately, then stream suspended fragments as their data resolves. This
is the default mental model in modern frameworks (React Suspense, SvelteKit streaming, Nuxt).

```tsx
// React Server Components with Suspense: shell flushes, ProductList streams in
export default function Page() {
  return (
    <main>
      <h1>Catalog</h1>
      <Suspense fallback={<Skeleton rows={5} />}>
        <ProductList /> {/* awaits slow data */}
      </Suspense>
    </main>
  );
}
```

Use when first byte matters and some data is slow; avoid when the entire page is one slow query
(streaming buys nothing) or when crawlers must see complete HTML immediately. Ordering matters:
put the most important content first so it arrives in the earliest chunk.

### React Server Components (RSC)

RSC splits components into server (data access, zero client JS, no hooks) and client (interactivity).
The server tree is serialized as a payload the client runtime reconciles; client components
hydrate as islands within it.

```tsx
// app/page.tsx - server component: direct data access, no bundle cost
import { db } from "@/lib/db";
import { LikeButton } from "./like-button"; // client component

export default async function Page() {
  const post = await db.post.findFirstOrThrow();
  return (
    <article>
      <h1>{post.title}</h1>
      <LikeButton postId={post.id} initialLikes={post.likes} />
    </article>
  );
}
```

Rules of thumb:
- Push `"use client"` to the leaves; a single client boundary pulls its whole subtree into the bundle.
- Never pass functions or class instances across the boundary unless they are server actions.
- Server components cannot use browser APIs, state, effects, or context providers.
- On navigation, RSC payloads deduplicate against the client router cache; understand that cache
  before debugging "stale UI".

Non-React alternatives to the same idea: SvelteKit server load functions, Nuxt server routes,
Astro server islands.

### Islands Architecture

Static HTML plus independently hydrated interactive widgets. Only the islands pay JavaScript cost.
Astro, Fresh, Eleventy with web components, and Qwik (resumability) are the canonical examples.

```astro
---
// Astro: page is static; only Counter hydrates
import Counter from "../components/Counter.tsx";
---
<h1>Docs</h1>
<Counter client:visible />
```

Use `client:visible` / `client:idle` / `client:media` directives (or lazy hydration equivalents) to
defer hydration until an island is actually needed. Best fit: content-first sites with a handful of
interactive components. Poor fit: dashboards where nearly everything is interactive.

### Single-Page Application (CSR)

Empty shell plus client routing. Acceptable for authenticated internal tools with no SEO need and
tolerant performance expectations. For public surfaces it fails Core Web Vitals fundamentals and
search indexing quality; prefer SSR/SSG with client navigation, which now feels identical to an SPA
while shipping real HTML.

### Partial Prerendering and Hybrid Routes

Modern frameworks blur modes: a static shell (CDN-cacheable) with holes filled per request at the
edge. Treat it as "static shell + streamed personalization" and apply the same rules: cache the
shell, measure the dynamic hole, fail closed for auth.

## Choosing a Strategy

| Page type | Recommended | Why |
|---|---|---|
| Marketing, docs, blog | SSG (+ CDN) | Cheapest, fastest, simple invalidation |
| E-commerce listing | ISR + on-demand tags | Large scale, tolerable staleness, fast TTFB |
| Product detail | ISR or SSR + cache | Price/stock freshness matters |
| Search results | SSR (no cache) or client fetch | Per-query, must be shareable via URL |
| Logged-in dashboard | SSR + RSC | Private, personalized, data-heavy |
| Settings/forms | SSR + server actions | Mutations and validation server-side |
| Internal admin tool | SPA acceptable | No SEO, known devices, long sessions |
| Real-time collab | SPA/client + WebSocket | Persistent interactive session |

## Caching Layers

A typical modern stack has five caches. Know each one's key, lifetime, and invalidation.

1. **CDN/HTTP cache** — keyed by URL, method, and `Vary`. Controlled by `Cache-Control`,
   `s-maxage`, `stale-while-revalidate`, and purge APIs. The only layer shared across all users.
2. **Full-route cache** (framework) — server-rendered output keyed by route and params. Controlled
   by `revalidate`, dynamic APIs, and preview/draft modes.
3. **Data cache** (framework or query library) — per-query results keyed by arguments. Controlled by
   tags, TTLs, and explicit `refresh`.
4. **Client cache** — in-memory (React Query/SWR/router cache). Deduplicates requests and powers
   instant back/forward. Must be revalidated on focus, reconnect, and mutation.
5. **Service worker cache** — request-level strategy in the browser. See
   [07-pwa-offline.md](./07-pwa-offline.md); it is the easiest layer to get stuck stale.

### Cache-Control Quick Reference

| Header | Meaning | Use for |
|---|---|---|
| `public, max-age=0, s-maxage=300, stale-while-revalidate=60` | CDN fresh 5 min, SWR 1 min | Semi-dynamic pages |
| `private, no-store` | Never cache anywhere | Auth responses, cart |
| `public, max-age=31536000, immutable` | Content-addressed assets | Hashed JS/CSS/fonts |
| `private, max-age=0, must-revalidate` | Browser may store but must check | Per-user HTML |
| `no-cache` | Store but always revalidate | Rarely what you want on CDN |

### Revalidation Strategies

- **Time-based** — simplest; risk of staleness bounded by TTL. Good default for catalogs.
- **On-demand/tag-based** — invalidate precisely when data mutates. Requires discipline: every write
  path must emit the right tags. Test invalidation like any other code path.
- **Event-driven** — webhooks from a CMS/DB stream trigger rebuilds or purge calls. Strong choice
  for headless CMS content.
- **Polling/refresh** — client refetch on interval, focus, or reconnect. Use for volatile data only;
  it multiplies origin load.

## Anti-Patterns

- Caching authenticated HTML in a shared CDN cache.
- `revalidate = 0` while a global fetch cache still serves stale data.
- Purging "everything" on every write instead of tagging precisely.
- Forgetting `Vary` on headers that change the response (`Accept-Language`, A/B cookies).
- Rendering client-only content that must be indexed or fast on first paint.

## Migration Notes

- **CSR SPA to SSR/RSC** — move data fetching into server components/loaders route by route; keep
  interactive islands client-side. Expect to delete most global state stores. See
  [02-state-data.md](./02-state-data.md).
- **SSR every page to hybrid** — classify routes with the table above; make the default static and
  opt into dynamic. This usually cuts origin cost more than any code optimization.
- **Pages Router to App Router / equivalent** — do not attempt a big-bang migration; run both
  routing models in parallel and move leaf routes first.
- **Client-side rendering for SEO-critical content** — stop. Serve real HTML per
  [09-seo-i18n-analytics.md](./09-seo-i18n-analytics.md).

## Pre-Launch Checklist

- [ ] Every route has an explicit rendering mode and cache policy.
- [ ] Authenticated responses are never stored in shared caches.
- [ ] Mutations invalidate tags/paths for all affected views, verified by test.
- [ ] Streaming response orders meaningful content first; skeleton states match final layout.
- [ ] Client bundles contain only genuinely interactive leaf components.
- [ ] Back/forward navigation restores state without full reloads.
- [ ] Field metrics (LCP/INP/CLS) are within budget on mid-range mobile — see
      [04-performance.md](./04-performance.md).
