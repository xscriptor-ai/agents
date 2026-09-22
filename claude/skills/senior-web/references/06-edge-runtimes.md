# Edge Runtimes

Edge functions and workers: provider landscape, execution limits, storage primitives, latency
patterns, and honest cases for origin compute.

## What Edge Compute Is

Edge functions run your code in many datacenters close to users, typically on V8 isolates (workerd,
Deno, or provider variants) rather than containers. They start in single-digit milliseconds and bill
per request plus CPU time. The trade-off: a constrained runtime (no Node core APIs by default, no
native modules, tight CPU and memory limits) and a distributed data problem (state is far away even
if code is near).

Isolate model versus containers: isolates share a process and have no cold-start container boot, but
you cannot assume Node internals, threads, or long-lived memory. Some providers now offer hybrid
models (for example regional Node runtimes or "fluid" compute) that blur the line; verify the
execution model and limits for your provider before designing around them.

## Provider Landscape (verify upstream)

| Provider | Model | Notable primitives | Typical fit |
|---|---|---|---|
| Cloudflare Workers | V8 isolates, global | KV, D1 (SQLite), R2, Durable Objects, Queues, Hyperdrive | Middleware, APIs, full apps |
| Vercel Edge / Functions | Isolates via edge runtime; regional Node functions | Edge Config, KV, Blob, Fluid compute | Next.js middleware and route handlers |
| Deno Deploy | V8 isolates, Deno APIs | Deno KV, Queues (per release) | Standards-first APIs |
| Netlify Edge Functions | Deno-based | Blobs, Edge handlers | Framework middleware, personalization |
| Fastly Compute | Wasm (Rust/JS/Go compiled) | KV Store, Config Store | High-performance filtering, A/B |
| AWS CloudFront Functions / Lambda@Edge | JS sub-ms / Node or Python | CloudFront key-value store | Header rewrites, light auth at CDN |
| Fly.io / Koyeb | Micro-VMs at edge regions | Full VMs, volumes, Postgres | When you need a real runtime near users |

Prefer providers that implement **WinterCG/Web-interoperable** APIs (`fetch`, `Request`, `Response`,
`URL`, `crypto`, `TextEncoder`, streams) so code ports between runtimes.

## Limits That Bite

Exact numbers vary by provider and plan and change frequently; always verify upstream. Typical
constraint classes:

| Constraint | Typical magnitude | Design consequence |
|---|---|---|
| CPU time per request | 10-50 ms free tier; up to seconds on paid | No heavy parsing, image processing, or ML |
| Wall-clock time | Seconds (waiting on I/O usually allowed) | Streaming responses can be long; keep total bounded |
| Memory | 128 MB class | No large buffers; stream instead of accumulate |
| Script/bundle size | 1-10 MB compressed class | Avoid large dependencies; tree-shake |
| Subrequests per request | Dozens | Batch and cache upstream calls |
| Concurrent connections | Provider-specific | Use connection pooling/proxies for databases |
| Runtime API surface | Web APIs; subset of Node | Prefer Web standards; polyfills cost size |

Additional traps:
- No filesystem, no `child_process`, no native addons, no long-lived timers.
- Module-scope code runs per isolate, not per request; caching in module scope is real but not
  guaranteed to persist or be shared.
- `waitUntil`/`ctx.waitUntil` for background work after response: excellent for analytics, but the
  work may be cut off and cannot exceed the execution budget.

## Runtime APIs and Code Shape

```ts
// A portable edge handler: Web Fetch API, no Node built-ins
export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/api/flags") {
      const cached = await env.KV.get("flags", "json"); // provider primitive
      return Response.json(cached ?? {}, {
        headers: { "cache-control": "public, max-age=30, stale-while-revalidate=120" },
      });
    }

    ctx.waitUntil(analytics.track(request)); // does not block the response
    return new Response("Not found", { status: 404 });
  },
};
```

Rules:
- Use `Response.json`, `crypto.randomUUID`, `crypto.subtle`, `URL`, and streams — all portable.
- Read config from environment bindings, not `process.env` (that may exist, but bindings are the
  portable model).
- Keep bundles small: import only what you call. Webpack/esbuild tree-shaking cannot save you from
  a dependency that is genuinely large.
- Treat execution as stateless; use storage primitives for anything that must survive.

## Storage Primitives

| Primitive | Model | Consistency | Latency | Use for |
|---|---|---|---|---|
| KV | Eventually consistent global map | Eventual (often seconds) | Low reads at edge, higher writes | Flags, config, cached API responses, sessions |
| SQLite at edge (D1, Turso, Deno KV SQL) | SQL, regional primary | Strong per-region; read replicas lag | Low reads near replica | Small relational data, app state |
| Object storage (R2/S3/Blob) | Blob store | Strong for reads after write | Higher than KV | Assets, uploads, large payloads |
| Durable Objects / stateful actors | Single-instance coordination | Strong (single-writer) | Single-region latency | Locks, counters, rooms, rate limits |
| Managed Postgres with edge drivers | Full SQL | Strong (primary) | Depends on region; pooling via proxy | Primary application data |
| Edge queues | Async delivery | At-least-once | Variable | Background jobs, retries |

Guidelines:
- **KV is a cache, not a database.** Reads may be stale by seconds and writes are not transactional.
- **One writer, many readers** is the edge-friendly data shape: take writes in one region, fan out
  reads globally.
- Database access from edge requires HTTP-based or pooled drivers (Hyperdrive, Neon serverless
  driver, PlanetScale HTTP). Direct TCP connection storms are the classic outage.
- Durable Objects (or equivalents) are the right tool for coordination and rate limiting; they are
  not a general-purpose database.
- Version and invalidate cached data explicitly; edge caches amplify stale reads.

## Latency Patterns That Win

- **Geo-routing and redirects** — send users to the right regional origin or locale.
- **Header rewriting and security** — CSP nonces, security headers, bot checks before origin.
- **Auth checks and token validation** — JWT verification at the edge stops unauthenticated traffic
  cold; keep the heavy authorization logic where the data is.
- **A/B testing and feature flags** — assign buckets at the edge with a stable cookie, then cache
  per variant.
- **Personalization of cached shells** — render a static shell at the CDN and patch user-specific
  fragments at the edge; never cache personalized HTML in a shared cache.
- **API aggregation** — collapse several origin calls into one edge response, cached briefly.
- **Image/asset transforms** — only where the provider has a real pipeline; CPU limits make DIY
  resizing a bad idea.
- **Webhook ingestion and fan-out** — verify signatures at the edge, enqueue work, respond fast.

## When Edge Is the Wrong Choice

- **Heavy CPU** — image processing, PDF generation, ML inference, large JSON transforms.
- **Large dependencies** — ORMs with native modules, headless browsers, SDKs with big trees.
- **Strict transactions** — multi-row/multi-table integrity with immediate consistency.
- **Long-running work** — video encoding, report generation, crawls.
- **Full Node semantics** — anything requiring `fs`, sockets you own, or native addons.
- **Data-locality dominance** — if every request must query a single primary database, running
  compute far from it adds latency instead of removing it. Measure; do not assume edge is faster.
- **Compliance constraints** — data residency may forbid processing in arbitrary PoPs.

Decision test: if the request can be answered from nearby cached data or by light cryptographic
work, edge wins. If it requires the primary database or sustained CPU, keep it regional.

## Operations and Debugging

- **Local dev**: providers ship emulators (`wrangler dev`, `vercel dev`, `deno`). Verify bindings and
  limits locally, but confirm CPU/limits in a preview deployment.
- **Observability**: logs are per-request and ephemeral; ship structured logs to a central store.
  Distributed traces across edge-to-origin calls are essential; a request ID propagated end to end
  pays for itself.
- **Error handling**: return responses, do not throw raw errors to users. Standardize a JSON error
  envelope and log the detail.
- **Rollouts**: deploy progressively; edge code propagates globally in seconds, which makes bad
  deploys instant too. Use versioned deploys with instant rollback.
- **Testing**: unit-test handlers as pure functions of `Request`; integration-test against emulator
  bindings; load-test origin paths the edge will amplify.

## Anti-Patterns

- Using KV as a transactional store, then debugging lost updates.
- Connecting to Postgres with a new TCP connection per edge request.
- Bundling a full ORM/server framework and hitting the size limit.
- Caching personalized responses in shared edge caches.
- Relying on module-scope state for correctness across requests or regions.
- Assuming clock/ordering guarantees across PoPs.
- Moving compute to the edge while keeping all data in one far-away region.

## Checklist

- [ ] Runtime model and limits confirmed for the target provider (verify upstream).
- [ ] Code uses Web-interoperable APIs; no hidden Node/native dependencies.
- [ ] Bundle size and CPU per request measured against plan limits.
- [ ] Storage primitive chosen by consistency needs; KV treated as a cache.
- [ ] Database access uses pooling/HTTP drivers; no per-request TCP storms.
- [ ] Personalized responses never land in shared caches.
- [ ] Logs, traces, and request IDs propagate to origin; rollback path exists.
