# Caching

Scope: cache layers from browser to database, HTTP caching semantics, application and Redis/Valkey patterns, invalidation, and stampede protection.

## Cache Layer Map

Order layers by distance from the user; each layer removes load from everything behind it.

| Layer | Typical latency | Scope | Eviction | Typical use |
|---|---|---|---|---|
| Browser cache | 0 ms (local) | Per user/device | TTL, storage pressure | Static assets, immutable bundles |
| Service worker / app cache | ~0 ms | Per user origin | Explicit, versioned | Offline assets, API read cache |
| CDN / edge | 5-40 ms | Shared, global | TTL plus purge | Static assets, public API responses |
| Reverse proxy / gateway | ~1 ms | Shared, per region | TTL, LRU | Authenticated API reads, fragments |
| In-process (L1) | microseconds | Per instance | LRU/TTL, size-bounded | Hot config, dictionaries, computed values |
| Shared cache (Redis/Valkey) | 0.5-3 ms | Fleet-wide | TTL, LRU/LFU | Sessions, rate limits, shared reads |
| Database cache / materialized view | query-dependent | Shared | Engine-managed | Precomputed aggregates, denormalized reads |

- Every layer is a consistency decision: each hop you add increases the set of things that can be stale.
- The fastest cache hit is one that never has to traverse the network; prefer L1 for hot immutable data with a memory ceiling.
- Do not use a cache to hide a query you could fix; indexed reads beat cached reads on correctness and cost. See `./03-databases.md`.

## Correctness Before Speed

- Define the cache key identity explicitly. What inputs change the response? User, tenant, locale, role, feature flag, device class, API version.
- Private data must be scoped by user or tenant in the key, and must not be stored in shared layers without that scope. Cross-tenant leakage from a cache is a security incident.
- Be deliberate about negative caching: cache "not found" briefly to absorb abuse, but never cache transient errors as if they were data.
- Distinguish client-visible validation from server-side reuse. A `304 Not Modified` can save bandwidth without saving origin compute.
- Decide freshness tolerance per data class: prices and balances may be seconds; permissions and feature flags often need explicit invalidation.
- Write down the answer to "how does this entry become correct again after a mutation?" before the cache ships.

## HTTP Caching

HTTP caching is the highest-leverage, lowest-cost layer because it is implemented by browsers and CDNs.

| Directive | Meaning |
|---|---|
| `max-age=N` | Fresh for N seconds in any cache |
| `s-maxage=N` | Fresh for N seconds in shared caches; overrides `max-age` there |
| `public` / `private` | Shared caches may / may not store |
| `no-store` | Do not store at all (sensitive responses) |
| `no-cache` | May store, but must revalidate before each use |
| `must-revalidate` | Cannot serve stale once expired |
| `immutable` | Do not revalidate during freshness (fingerprinted assets) |
| `stale-while-revalidate=N` | Serve stale for N seconds while refreshing in background |
| `stale-if-error=N` | Serve stale for N seconds if origin errors |
| `Vary` | Key on request headers (for example `Accept-Encoding`) |

- Fingerprinted static assets: `Cache-Control: public, max-age=31536000, immutable`, with a new filename per release.
- HTML and API reads: short `max-age`, longer `s-maxage`, plus `stale-while-revalidate` to absorb bursts without origin load.
- Use `ETag` or `Last-Modified` validators for mutable resources so conditional requests return `304` cheaply. Weak validators are acceptable when byte equality is not required.
- `Vary` is part of the key: a careless `Vary: *` or `Vary: Cookie` makes the cache useless or unsafe. Prefer explicit `Vary: Accept-Encoding` and route identity through the URL or explicit cache keys.
- CDN purge is an operational dependency: know the purge latency, API limits, and failure behavior before promising "instant" invalidation.
- Cache poisoning: never let user-controlled headers or parameters enter shared cache keys in a way that lets one user poison responses for others. Normalize inputs and strip unknown keys.
- Cookie-bearing responses default to private; verify that sessions are not accidentally shared by an over-broad CDN rule.

## Application Patterns

| Pattern | Flow | Strengths | Weaknesses | Use when |
|---|---|---|---|---|
| Cache-aside | App reads cache, on miss reads source and populates | Simple, resilient, lazy | Race on fill, first-miss slow | General purpose |
| Read-through | Cache library loads on miss | Uniform code path | Needs library support | Repeated reads of same shape |
| Write-through | Write cache and source together | Fresh, predictable | Write latency includes cache | Strong read-your-write needs |
| Write-behind | Write cache, flush source asynchronously | Fast writes | Data-loss window, complexity | High write throughput, loss-tolerant |
| Refresh-ahead | Refresh before expiry | Few cold misses | Wasted refresh on cold keys | Hot keys with strict latency |
| Negative caching | Cache misses briefly | Protects against abuse | Can hide new data | Scanned or probed identifiers |

- TTLs plus jitter: add random +/- 10-20 percent to TTLs so entries do not expire in synchronized waves.
- Key design: stable prefix, tenant or user segment, entity id, schema or version suffix. Include a version component so a data-shape change invalidates implicitly.
- Serialization costs count: JSON is portable but expensive at volume; compact binary formats reduce CPU and bytes. Measure before choosing.
- Compress large values, but do not compress tiny ones; compression has fixed overhead and CPU cost.
- Bound the in-process cache by entry size and count; unbounded maps are memory leaks that happen to have a TTL. See `./07-memory-gc.md`.
- Cache the result of expensive deterministic computation by input hash, never by a mutable object identity.

## Redis and Valkey Patterns

- Redis 7.x and Valkey 7.x/8.x era APIs are broadly compatible; clustering, scripting, and eviction semantics differ in details. Verify the exact feature set upstream for your distribution and version.
- Choose the data structure for the operation: strings for counters and blobs, hashes for objects, sorted sets for rankings and sliding windows, sets for membership, streams for event fan-out.
- Set `maxmemory` and an eviction policy deliberately: `noeviction` for authoritative data (fail writes rather than silently drop), `allkeys-lru` or `allkeys-lfu` for pure caches. `volatile-*` policies only evict keys with TTLs.
- Use pipelining or multi-key commands to cut round trips; latency is often RTT-bound, not CPU-bound.
- Lua scripts and `MULTI`/`EXEC` give atomicity for read-modify-write; prefer scripts for idempotent compound operations, and keep them short.
- Keyspace design: use hash tags to colocate related keys in cluster mode; avoid hot keys that land on one shard. Replicate or shard hot keys deliberately.
- Separate logical databases or instances by use: sessions, cache, rate limits, and queues have different failure and persistence needs.
- Persistence and replication affect latency: AOF fsync policies and replica syncs can pause writes. Decide whether the cache is allowed to be lost entirely.
- Use cache timeouts and a circuit breaker. If the cache is down, the application must degrade to the source of truth, not hang.

## Invalidation Strategies

| Strategy | Mechanism | Latency to correct | Notes |
|---|---|---|---|
| TTL expiry | Time-based | Up to TTL | Simplest; tune per data class |
| Versioned keys | Key includes content or schema version | Immediate on version bump | Old keys age out; doubles storage briefly |
| Write-invalidate | Delete or update keys on mutation | Near-immediate | Must cover all mutation paths |
| Write-through | Update cache in the same transaction path | Immediate | Write cost; partial failure handling |
| Event-driven | CDC or pub/sub triggers invalidation | Seconds | Decoupled but adds moving parts |
| Purge API | CDN or gateway purge by key/tag | Seconds to minutes | Vendor limits and propagation delays |

- The classic race: request A reads stale value, request B updates the source and evicts, request A then writes the stale value into the cache. Mitigations: versioned writes, delete-after-write with a short delay, or write-through with version checks.
- Update paths that bypass the invalidation hook are the most common source of stale data. Centralize writes or enforce invalidation in one layer.
- Prefer invalidation by version or generation over enumerating keys; pattern deletes are slow and dangerous at scale.
- For search or list caches, cache the page identity and fetch entities from a fresher store so entity updates do not require purging every list.

## Stampede and Failure Protection

- A cold key under high concurrency triggers many identical origin requests at once. Single-flight or request coalescing collapses them into one.
- Implementation options: per-key mutex or promise map in-process, distributed lock (with a timeout), or a cache library with load coalescing.
- Probabilistic early expiration (XFetch): refresh a key slightly before expiry with a probability proportional to remaining time, spreading refreshes.
- Serve stale on origin error where the business tolerates it (`stale-if-error`); fail fast where it does not.
- Warm critical caches on deploy or after eviction events so the first users do not pay for everyone.
- Hot keys: a single key exceeding one shard's capacity needs key splitting or a local L1 in front of the shared cache.
- Decide what happens when the cache dies: fail open (hit the database and risk overload) or fail closed (reject traffic). Most read paths should fail open with concurrency limits. See `./06-concurrency-backpressure.md`.

## Metrics and Operations

| Metric | Why | Watch for |
|---|---|---|
| Hit ratio (overall and per key class) | Direct input to origin load | Aggregate ratios hide cold classes |
| Miss cost | Origin time per miss | A 90 percent hit ratio can still be bad if misses are expensive |
| Evictions and expirations | Working-set fit | Rising evictions mean undersized cache |
| Memory used and fragmentation | Capacity planning | Fragment ratio and allocator overhead |
| Cache call latency p99 | User-facing impact | Tail latency from network or hot shards |
| Error and timeout rate | Failure mode | Must trigger degradation, not hangs |
| Stale-serve count | Correctness exposure | Should be visible and bounded |

- Test invalidation explicitly: mutate, then assert the cache and origin agree within the stated window.
- Load-test cold-cache and cache-down scenarios; both are common post-deploy incidents. See `./08-load-testing.md`.

## Anti-Patterns

- Caching without a defined invalidation path, hoping TTL will be short enough.
- Unbounded in-process caches with no size limit.
- Sharing one cache namespace across environments or tenants.
- Caching errors or empty results indefinitely.
- Using cache to mask an unindexed query.
- Synchronized TTLs that expire a whole working set at once.
- No single-flight protection on an expensive key.
- Treating a cache outage as impossible; no timeout, no fallback, no breaker.
- Invalidating by scanning or pattern-deleting production keys at scale.
- Ignoring serialization and compression CPU cost in the cache's own budget.

## Checklist

- [ ] Cache key identity and scope (user, tenant, locale, version) are explicit.
- [ ] Invalidation story documented: TTL, version, write-invalidate, or purge, with expected correction window.
- [ ] TTLs jittered; critical keys warmed or refreshed ahead.
- [ ] Single-flight or distributed lock protects expensive misses.
- [ ] Cache-down behavior defined (fail open with limits, or fail closed) and tested.
- [ ] `maxmemory` and eviction policy set deliberately; not silently dropping authoritative data.
- [ ] Hit ratio, miss cost, evictions, and p99 cache latency are monitored.
- [ ] Private data never stored in shared layers without key scoping.
- [ ] CDN purge latency and limits verified upstream; release process updates fingerprinted assets.
- [ ] Cold-cache and cache-failure load tests exist.
