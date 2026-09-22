---
name: senior-performance
description: 'Performance engineering reference pack for senior work across stacks:
  measurement discipline (USE/RED, percentiles, Little''s Law, Amdahl), caching layers
  and invalidation, database indexing and query tuning, CPU and memory profiling with
  flamegraphs, frontend Core Web Vitals and bundle control, concurrency limits and
  backpressure, memory and GC tuning, load test scenario design, and capacity and
  cost planning. Use when investigating a latency or throughput regression, setting
  performance budgets, designing a cache or invalidation strategy, fixing N+1 queries
  or connection pool sizing, profiling CPU, memory, or lock contention, reducing bundle
  size or INP, tuning queues and rate limits, diagnosing memory leaks or OOM kills,
  designing smoke/load/stress/spike/soak tests, or planning capacity and cost per
  request.'
---

# Performance

Reference pack for senior performance engineering: measurement, caching, databases, backend profiling, frontend, concurrency and backpressure, memory and GC, load testing, and capacity/cost. Depth lives in `references/`; this file is the map.

## Baseline (2026)

- Performance work is empirical: every change starts from a measured baseline and ends with a re-measurement under comparable conditions. An unmeasured optimization is a guess.
- Latency budgets are dominated by tails. p50 is marketing; p95/p99 plus saturation metrics are engineering. Averages hide the incidents that page people.
- Utilization is the enemy of latency. Queueing behavior means a system at 80-90 percent utilization has non-linear latency growth. Headroom is a design decision, not waste.
- The cheapest request is the one never made, the second cheapest is served from cache, and only then is optimization of the origin path relevant.
- Vendor and cloud defaults (pool sizes, timeouts, GC settings, autoscaling signals) are starting points, not answers; tune against measured load.
- Managed runtimes keep improving (generational collectors, AOT, better JIT), so GC and profiling advice must be re-validated per runtime version — verify upstream.
- Version claims in this pack are floors, ranges, or "verify upstream"; never treat them as pinned exact versions.

## Non-Negotiable Core Rules

1. Measure before and after; keep the number with the change. No optimization merges without a baseline, a method, and a re-measurement at the same load level. See `./references/01-methodology.md`.
2. State the target as a budget: a latency percentile, throughput floor, memory ceiling, or cost-per-request ceiling. "Faster" is not a target.
3. Track tails, not averages: report p50, p95, p99 (and p99.9 for critical paths) with the sample window and load level. See `./references/01-methodology.md`.
4. Bound every resource: connection pools, queues, thread pools, caches, request concurrency, retry counts. Unbounded anything becomes an outage under load. See `./references/06-concurrency-backpressure.md`.
5. Cache with an invalidation story. If you cannot name how a cached entry becomes correct again, do not cache it. See `./references/02-caching.md`.
6. Never cache private data without user or tenant scope in the key; never let one tenant's response leak into another's cache. See `./references/02-caching.md`.
7. Every remote call has a timeout, and every retry is bounded, jittered, and idempotent. Retry storms turn a blip into a meltdown. See `./references/06-concurrency-backpressure.md`.
8. Database changes are measured against a representative data volume; N+1 and missing indexes rarely show themselves on seed data. See `./references/03-databases.md`.
9. Profile production-like builds with symbols and production-like data shapes; debug builds and toy data produce misleading flamegraphs. See `./references/04-backend-profiling.md`.
10. Frontend performance is tracked with field data (RUM/CrUX), not only lab scores; ship budgets in CI so regressions fail the build. See `./references/05-frontend.md`.
11. Capacity plans include a peak factor and headroom, not just current traffic; autoscaling without a measured saturation signal oscillates or lags. See `./references/09-capacity-cost.md`.
12. Load tests are open or closed models chosen deliberately; closed-loop tests hide coordinated omission and overstate capacity. See `./references/08-load-testing.md`.

## Decision Tables

### First Move by Symptom

| Symptom | First move | Reference |
|---|---|---|
| Latency grows with load, CPU flat | Look for queueing, locks, pools, or downstream waits | `./references/01-methodology.md`, `./references/06-concurrency-backpressure.md` |
| p99 far above p50 | Find tail sources: GC, lock contention, cold caches, retries, fan-out | `./references/01-methodology.md`, `./references/07-memory-gc.md` |
| Throughput plateaus while load rises | Find the saturated resource: CPU, DB, connection pool, network, lock | `./references/04-backend-profiling.md`, `./references/08-load-testing.md` |
| Database CPU or I/O high | Slow query workflow, plan inspection, index and N+1 review | `./references/03-databases.md` |
| CPU high without traffic growth | Profile CPU and allocations; check busy loops, regex, serialization | `./references/04-backend-profiling.md` |
| Memory grows without bound | Leak detection and GC tuning; inspect retainers and object lifetimes | `./references/07-memory-gc.md` |
| Slow page load or bad INP | Bundle, images, fonts, hydration, and third-party cost | `./references/05-frontend.md` |
| Cost per request rising | Unit economics: traffic mix, instance size, cache hit rate, egress | `./references/09-capacity-cost.md` |

### Cache Layer Selection

| Need | Layer | Notes |
|---|---|---|
| Static asset repeat visits | Browser / CDN | Long TTL plus content-hash filenames; purge on release |
| Public API response, tolerant of staleness | CDN or shared cache | `s-maxage` plus `stale-while-revalidate`; validate with `ETag` |
| Hot shared data across instances | Redis/Valkey or equivalent | TTL plus jitter; single-flight on miss |
| Per-request repeated reads | In-process (L1) | Short TTL or explicit invalidation; watch memory ceiling |
| Expensive deterministic computation | Application cache | Versioned keys tied to input or schema version |
| Database read amplification | Materialized view or read replica | Not a cache; plan staleness and lag budgets |

### Concurrency and Overload Controls

| Problem | Control | Reference |
|---|---|---|
| Unbounded fan-out to a dependency | Bounded concurrency pool or semaphore | `./references/06-concurrency-backpressure.md` |
| Queue grows without bound | Bounded queue plus load shedding | `./references/06-concurrency-backpressure.md` |
| One tenant consumes the fleet | Per-tenant limits and bulkheads | `./references/06-concurrency-backpressure.md` |
| Burst arrives faster than capacity | Admission control; return 429/503 with `Retry-After` | `./references/06-concurrency-backpressure.md` |
| Retries amplify an outage | Retry budget, jitter, circuit breaker | `./references/06-concurrency-backpressure.md` |
| Scaling lags traffic spikes | Queue-depth or concurrency-based autoscaling | `./references/09-capacity-cost.md` |

### Measurement Tool by Layer

| Layer | Lab | Field / production |
|---|---|---|
| Backend code | Benchmarks, profilers | Continuous profiling, traces |
| Database | `EXPLAIN ANALYZE` on cloned volume | `pg_stat_statements` / slow query log |
| API | Load generator against staging | RUM plus server-side latency histograms |
| Frontend | Lighthouse CI, WebPageTest | RUM (CrUX-compatible), INP attribution |
| Capacity | Breakpoint test | Saturation metrics, cost reports |

## Reference Index

| File | Scope | Load when |
|---|---|---|
| `./references/01-methodology.md` | Measurement discipline, USE/RED, percentiles and tails, Little's Law, Amdahl, budgets, benchmarking hygiene | Starting any performance investigation, defining metrics or budgets, reviewing a benchmark methodology |
| `./references/02-caching.md` | Browser/CDN/application/database cache layers, HTTP caching, Redis/Valkey patterns, invalidation, stampede protection | Designing or reviewing a cache, fixing staleness or hit rate, protecting against stampedes |
| `./references/03-databases.md` | Indexing strategy, query plans, N+1 detection, connection pool math, partitioning, replicas, slow query workflow | Slow queries, missing indexes, ORM N+1, pool exhaustion, replica lag, partition design |
| `./references/04-backend-profiling.md` | CPU and memory profiling, flamegraphs, continuous profiling, eBPF, lock contention, slow path tracing | CPU or latency hot spots, contention, profiling in production, choosing a profiler |
| `./references/05-frontend.md` | Bundles, Core Web Vitals and INP, images and fonts, hydration cost, rendering, RUM and lab tools | Slow load, poor INP or CLS, bundle growth, SSR/hydration cost, frontend budget setup |
| `./references/06-concurrency-backpressure.md` | Pools, bounded queues, rate limiting, batching, bulkheads, backpressure, retries, load shedding | Overload, pool sizing, timeouts and retries, tenant isolation, rate limit design |
| `./references/07-memory-gc.md` | Leak detection, GC tuning per runtime, allocation reduction, pools and arenas, OOM diagnosis | Growing RSS, leak hunts, OOM kills, GC pause tuning, allocation-driven CPU |
| `./references/08-load-testing.md` | Smoke/load/stress/spike/soak design, open vs closed models, k6 and locust patterns, result interpretation | Designing or reviewing load tests, capacity tests, interpreting throughput/latency curves |
| `./references/09-capacity-cost.md` | Capacity planning, autoscaling signals, SLO-aware scaling, cost per request, tradeoff checklist | Sizing fleets, choosing scaling signals, unit economics, cost regressions |

## Load Order

- First response to any regression: `./references/01-methodology.md`, then the reference matching the symptom table above.
- Latency with unknown cause: `./references/01-methodology.md` -> `./references/04-backend-profiling.md` -> `./references/07-memory-gc.md` or `./references/06-concurrency-backpressure.md` depending on the profile.
- Database-shaped problem: `./references/03-databases.md`, with `./references/02-caching.md` if reads dominate.
- Frontend task: `./references/05-frontend.md`, then `./references/01-methodology.md` for budget and measurement discipline.
- Capacity, scaling, or cost work: `./references/09-capacity-cost.md` plus `./references/08-load-testing.md` for evidence.
- Load only the references the task needs; do not inject the whole pack into context.

## Performance Review Workflow

1. Confirm the target: metric, percentile, load level, and budget (`./references/01-methodology.md`).
2. Verify the measurement method: sample size, warmup, environment parity, and noise control.
3. Identify the saturated resource before touching code; classify CPU, memory, I/O, lock, or downstream wait (`./references/04-backend-profiling.md`).
4. For data paths, measure query plans and fan-out on realistic volume (`./references/03-databases.md`).
5. For shared state, check cache correctness, invalidation, and stampede behavior (`./references/02-caching.md`).
6. For overload paths, check bounds, timeouts, retries, and shedding behavior (`./references/06-concurrency-backpressure.md`).
7. For user-facing surfaces, check field metrics and budgets, not just lab scores (`./references/05-frontend.md`).
8. Confirm the change is re-measured and the result recorded with the commit; add a budget gate where regression risk is high.

## Port

- **Port id** — `skill://senior/performance` (version in `metadata.port-version`, currently `2.0.0`).
- **Kind** — read-only reference pack; no side effects, no tools required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "performance" })` in OpenCode; Claude Code reads `<skills-dir>/performance/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers reference it as `load skill senior-performance (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major.

## Contract

- References are numbered `01`-`09`; keep them mutually consistent and cross-linked with relative paths.
- Version claims are floors or qualified with "verify upstream"; never present invented exact versions as fact.
- Anti-patterns and checklists close every reference; treat unchecked boxes as review findings.
- No emojis, English only, and no tooling that mutates the user's systems.
