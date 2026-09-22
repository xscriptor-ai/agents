# Concurrency and Backpressure

Scope: pools, bounded queues, rate limiting, batching, bulkheads, backpressure, timeouts, retries, and load shedding under overload.

## Why Concurrency Control

- Latency is a queueing function. Past roughly 70-80 percent utilization, waiting dominates service time and tails explode. See `./01-methodology.md`.
- Unbounded concurrency converts overload into an outage: every new request adds work, queues grow, timeouts fire, and retries multiply the load.
- The goal is not maximum parallelism; it is the highest sustainable throughput that keeps the latency budget. That requires explicit limits on every shared resource.
- Limits belong in code and configuration, not in hope: connection pools, worker pools, request concurrency, queue lengths, retry counts, and cache sizes.

## Pools and Sizing

| Pool | Bounds | Sizing basis |
|---|---|---|
| CPU thread/worker pool | Concurrent CPU work | CPU cores, with slight oversubscription for mixed workloads |
| Blocking I/O pool | Threads blocked on I/O | Runtime limits plus downstream concurrency budget |
| Async task concurrency | In-flight coroutines/tasks | Semaphore from Little's Law and downstream capacity |
| Database connections | DB sessions | Little's Law plus headroom; fleet total under server max |
| HTTP client connections | Sockets per host | Per-host limit to protect dependencies |
| Queue workers | Parallel consumers | Downstream throughput and queue drain SLO |

- Little's Law sizing: `concurrency = arrival_rate * latency`. If a service handles 2,000 rps at 40 ms downstream, about 80 calls are in flight; a pool of 8 will queue forever. See `./01-methodology.md`.
- CPU-bound work should roughly match available cores; oversubscribing threads adds context switching and worsens tails.
- Blocking runtimes (traditional servlet, sync Python) need pools sized by downstream capacity, not by thread-count slogans. Async runtimes need semaphores because the event loop will happily schedule unlimited concurrent operations.
- Pools are per dependency: one slow dependency must not consume the capacity reserved for others. Give each downstream its own bound.
- GIL and event-loop notes: Python threads do not parallelize CPU work; use processes or native extensions. Node.js and single-threaded event loops need bounded async concurrency and worker threads for CPU tasks.
- Tune from measured wait time: if pool usage is high and wait time is non-trivial, either raise the pool (if the downstream can absorb it) or reduce work per item.

## Queues and Queueing

- Prefer bounded queues everywhere: worker queues, message consumption, request admission, log buffers, and retry queues. Unbounded queues are delayed outages with good initial metrics.
- Queue depth is both a buffer and a signal: use it for autoscaling and alerts, but cap it by expected drain time. A queue 10 minutes long cannot meet a 1-second latency SLO.
- Choose queue semantics deliberately: FIFO for fairness, priority for incident-critical traffic, LIFO only when old work is worthless (freshness-first feeds).
- Backpressure propagation: when a queue fills, the producer must slow down, block, or be rejected. A full queue that silently drops is a data-loss decision; make it explicit.
- Dead-letter queues need an owner, a review cadence, and replay tooling. An unmonitored DLQ is a silent failure store.

## Backpressure Mechanisms

| Mechanism | How | Where it fits |
|---|---|---|
| Bounded blocking | Producer blocks until space is available | In-process pipelines, streaming |
| Credit-based flow control | Consumer grants permits | gRPC, message protocols, custom pipelines |
| `429 Too Many Requests` | Reject with `Retry-After` | Public APIs, per-tenant limits |
| `503 Service Unavailable` | Reject when shedding, with retry guidance | Overloaded services, maintenance |
| TCP flow control | Kernel receive window closes | Network-level, automatic |
| Reactive streams / demand | Consumer requests N items | Reactive stacks, stream processing |
| Client-side adaptive limiting | Clients reduce concurrency on errors/latency | SDKs, service meshes |

- Backpressure should propagate end to end. If the innermost dependency is slow and every caller buffers unboundedly, the pressure never reaches the source; the system just accumulates latency and memory.
- Prefer explicit rejection over unbounded waiting: a fast `429` with retry guidance preserves the capacity to serve other users.
- Include a machine-readable reason and a `Retry-After` where supported; clients that ignore it must be rate-limited or blocked.

## Rate Limiting

| Algorithm | Burst behavior | Notes |
|---|---|---|
| Token bucket | Allows configured bursts | Default choice; simple and intuitive |
| Leaky bucket | Smooths output | Good for shaping downstream calls |
| Fixed window | Burst at window edges | Simplest; double-rate edge effects |
| Sliding window log | Exact but memory-heavy | Small keys or low volumes |
| Sliding window counter | Approximate and smooth | Common in distributed limits |
| Concurrency limit | Caps in-flight, not rate | Better for long-lived or streaming calls |

- Distinguish rate (requests per second) from concurrency (requests in flight). Long-running calls need concurrency limits even at low rates.
- Distributed limits need shared state; a Redis/Valkey script or equivalent provides atomic counters. Verify your implementation handles clock skew and partition failure upstream.
- Decide failure mode when the limiter store is unavailable: fail open (allow) can overload the backend; fail closed (reject) can take down the API. Most systems choose fail open with a local fallback limit.
- Per-tenant limits protect the fleet from a single customer; global limits protect shared dependencies. Implement both, with different thresholds.
- Return limit information (`RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`) where the standard is supported, and document the policy.

## Timeouts and Deadlines

- Every network call needs a timeout: connect, read, and total. Defaults that wait forever are latent outages.
- Propagate deadlines: downstream calls get less time than the caller has remaining, leaving time to serialize and respond.
- Do not set all timeouts equal across layers; the budget shrinks as requests move inward. A common shape: client 5 s, gateway 3 s, service 2 s, database 1.5 s.
- On timeout, cancel remaining work (context cancellation or equivalent); canceled work still consumes real CPU and connections if nothing stops it.
- Timeout values must exceed the observed healthy p99.9 with margin, or healthy requests will fail under normal variance.
- Streaming and long-lived connections need idle timeouts in addition to total duration limits.

## Retries and Circuit Breakers

- Retry only transient errors, only idempotent operations, and only within a budget. Blind retries turn a brief dependency failure into a self-inflicted DDoS.
- Cap retry attempts (commonly 1-2 beyond the original), use exponential backoff with jitter, and honor `Retry-After`.
- A retry budget caps retries as a fraction of successful requests (for example, 10 percent of traffic), so healthy systems can retry more while overloaded ones retry less.
- Use idempotency keys for writes that may be retried; otherwise a retried payment or order becomes a duplicate.
- Circuit breakers protect callers from slow dependencies: half-open probes, failure thresholds, and a short-circuit response are the common shape. Return a degraded response rather than hanging.
- Hedging (sending the same request twice after a delay) improves tails only with strict budgets and idempotency; otherwise it doubles load.
- Track retry rate as a first-class metric; a rising retry rate is an early warning even when success rates look fine.

## Batching

- Batching trades latency for throughput. Use it where the downstream supports bulk operations and the extra wait fits the latency budget.
- Micro-batching: accumulate requests for a few milliseconds, then send one bulk call. Pair a size limit with a time limit (for example, 100 items or 10 ms, whichever first).
- Coalesce identical concurrent reads into one call (single-flight); this is batching by another name. See `./02-caching.md`.
- Dynamic batch sizes that grow under load and shrink on latency pressure are effective but need guardrails; never let a batch exceed the downstream's maximum payload.
- Batch writes need partial-failure semantics: one bad item must not fail the whole batch, and callers must know which items succeeded.
- Batch at the boundary where it pays: database round trips, object storage, message publishes, and external APIs. Do not batch when the latency budget has no room.

## Bulkheads

- Partition capacity by failure domain: separate pools, queues, or even clusters per dependency, tenant tier, or route class.
- A bulkhead means one tenant or dependency exhausting its share cannot consume everyone else's. Without it, shared pools convert any single slow caller into a site-wide incident.
- Cell-based architecture extends the idea to infrastructure: independent cells limit blast radius and allow incremental rollout. Costlier to operate; use for high-consequence systems.
- Resource isolation is not free: more pools mean more overhead and more configuration. Reserve bulkheads for proven shared-fate risks.

## Load Shedding and Admission Control

- Shed before saturation, not after: reject early with `503` or queue with a deadline long before every worker is stuck.
- Admission control checks capacity at the edge: concurrency limits, queue depth thresholds, and priority classes decide what enters.
- Priority classes: interactive traffic above batch, paying tenants above free tiers, health checks above product traffic. Prefer explicit classes over implicit arrival order.
- Degrade features before failing requests: serve a cached or partial response, disable recommendations, skip analytics writes, shorten results. State the degradation in logs and metrics.
- Emergency limits are configuration, not deploys: a runbook switch to tighten limits must not require a release.
- Keep a static floor of capacity reserved for health checks and critical operations; otherwise the service cannot even report that it is overloaded.

## Autoscaling Interplay

- Scale on demand signals, not just CPU: queue depth, request concurrency, and arrival rate respond before CPU saturates. See `./09-capacity-cost.md`.
- Targets should leave headroom: scaling to 60-70 percent utilization keeps queueing in the linear region.
- Scale-out is not instant: pods take seconds to minutes to become ready. Shedding and queueing cover the gap; that is why limits are not optional with autoscaling.
- Scale-in must respect in-flight work; terminating a pod mid-request adds latency and errors. Use graceful shutdown with drain windows and connection draining.

## Observability

| Signal | Why it matters |
|---|---|
| In-flight requests / tasks | Concurrency versus limit |
| Queue depth and oldest item age | Latency already accumulated |
| Wait time for pool/queue | Saturation before errors |
| Rejection and shed rate | How much user demand is being refused |
| Timeout and cancellation rate | Downstream health |
| Retry rate per dependency | Amplification risk |
| Per-tenant concurrency and rate | Noisy-neighbor detection |

- Alert on saturation and wait time; errors and timeouts are the late signals.
- Track limits as configuration with values visible in dashboards; unknown limits cannot be reasoned about during incidents.

## Anti-Patterns

- Unbounded queues, unbounded pools, unlimited retries, or unlimited fan-out.
- One shared pool for all dependencies, so the slowest consumes everything.
- Timeouts missing, equal across layers, or longer than the caller's own budget.
- Retry without jitter, budget, or idempotency.
- Rate limiting only at the edge while internal callers bypass it.
- Batching without a latency cap or partial-failure handling.
- Shedding only after CPU is pegged and memory is exhausted.
- Buffering in every layer so backpressure never reaches the producer.
- Treating autoscaling as a substitute for admission control.

## Checklist

- [ ] Every shared resource has an explicit, documented limit.
- [ ] Pool sizes derived from Little's Law and measured wait time, not defaults.
- [ ] Queues bounded with a drain-time rationale; DLQ owned and monitored.
- [ ] Backpressure propagates to producers; rejection reasons and `Retry-After` returned.
- [ ] Rate limits exist per tenant and globally, with a defined failure mode.
- [ ] Timeouts per hop with deadline propagation; cancellation honored.
- [ ] Retries bounded, jittered, budgeted, and idempotent; circuit breakers configured.
- [ ] Batching has size and time caps plus partial-failure semantics.
- [ ] Bulkheads isolate high-risk dependencies and top tenants.
- [ ] Load shedding with priority classes and a static capacity floor.
- [ ] Saturation metrics (in-flight, queue depth, wait time, shed rate) alerted before errors.
