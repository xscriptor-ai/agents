# Measurement Methodology

Scope: measurement discipline for performance work — USE and RED, percentiles and tails, Little's Law, Amdahl's law, performance budgets, and benchmarking hygiene.

## Measurement Discipline

- Start from a question, not a tool: "Is p95 checkout under 400 ms at 2x peak traffic?" is measurable; "make it faster" is not.
- Capture a baseline before touching anything, under conditions you can recreate: same build type, same data volume, same hardware class, same load model.
- Change one variable at a time. Bundled changes make attribution impossible.
- Record the method next to the number: build, commit, environment, load level, sample window, and percentile.
- Prefer production evidence when available; production is the only environment with real data shape, cache state, and traffic mix.
- Treat every performance number as a distribution, never a scalar. A single "average" has hidden the last decade of performance incidents.

## The Investigation Loop

1. Define the metric and the budget (latency percentile, throughput, memory, cost).
2. Measure the current state and quantify the gap against the budget.
3. Classify where time or capacity goes: CPU, memory, I/O, locks, queueing, downstream dependency.
4. Form one hypothesis and predict its effect if true.
5. Test the hypothesis with the smallest safe experiment (profile, query plan, canary, load test slice).
6. Fix, re-measure under the same conditions, and store the before/after with the change.
7. Guard the result with a CI gate, dashboard, or alert so it cannot silently regress.

## USE and RED

Two complementary checklists. Use them before reaching for a profiler.

- **USE** — for every resource (CPU, memory, disk, network, connection pools, thread pools, queues): **U**tilization, **S**aturation, **E**rrors.
- **RED** — for every service: **R**ate, **E**rrors, **D**uration (as a distribution).

| Question | Method | Typical signals |
|---|---|---|
| Is a resource near its limit? | USE | CPU %, run-queue length, memory used, pool in-use, disk await, retransmits |
| Is a service healthy? | RED | requests/s, error ratio, latency histogram |
| Is the system queueing? | USE saturation plus Little's Law | queue depth, wait time, in-flight requests |
| Is the tail caused by the resource or the code? | Histogram plus profile | p99 trend vs saturation, flamegraph |
| Did a deploy regress it? | RED split by version | latency per service.version |

- Utilization alone lies. A pool at 60 percent utilization can still produce multi-second queue waits if service-time variance is high.
- Saturation is the leading indicator; errors are the lagging one. Alert on saturation and latency before errors spike.
- For every resource, write down its unit, ceiling, and current headroom. Unknown ceilings cause surprise outages.

## Percentiles and Tails

- Report p50, p95, p99 for most APIs; add p99.9 for payment, auth, and control-plane paths. State the window and load level with every number.
- Never average percentiles across instances or time buckets. Average the underlying histograms, then compute the percentile.
- Percentile accuracy needs samples: you cannot resolve p99.9 from 1,000 requests. Rule of thumb: collect at least 100x the sample size of the percentile you claim.
- Use exponential or log-linear histogram buckets so tail resolution is not lost; the oldest fixed linear buckets are the most common cause of useless p99 dashboards.
- Heatmaps over time show bimodality and shifts that a single percentile hides. A rising p99.9 with flat p50 usually means a growing slice of slow paths, not a uniform slowdown.

Common tail sources, in rough order of frequency:

| Source | Signature | Where to look |
|---|---|---|
| Queueing at a saturated resource | latency rises non-linearly with load | pool, queue, CPU, DB |
| GC pauses or collector work | periodic spikes, CPU frames in collector | `./07-memory-gc.md` |
| Lock contention | spikes under concurrency, flat when single-threaded | `./04-backend-profiling.md` |
| Cache misses or cold starts | spikes after deploys or expiry windows | `./02-caching.md` |
| Fan-out to N dependencies | tail is max of N, grows with N | `./06-concurrency-backpressure.md` |
| Retries and timeouts | clusters at timeout boundaries | `./06-concurrency-backpressure.md` |
| Noisy neighbors or throttling | host-correlated, sporadic | `./09-capacity-cost.md` |

- Tail latency interacts with fan-out: at 50 ms p99 per call, a request touching 20 calls in parallel has an expected worst-call tail far above 50 ms. Reduce fan-out or hedge deliberately.
- Percentiles from a closed-loop benchmark understate real tails because clients wait (coordinated omission). Use arrival-rate models. See `./08-load-testing.md`.

## Little's Law

The most useful back-of-envelope formula in performance work:

```text
L = lambda * W
concurrency = arrival rate * time in system
```

Where `L` is the number of items in the system, `lambda` the arrival rate, and `W` the average time each item spends.

- 1,000 req/s at 80 ms end-to-end means about 80 requests are in flight. Size pools, workers, and instance limits to cover that number with headroom.
- Required DB connections: `arrival rate * average query time`. 500 queries/s at 10 ms is about 5 busy connections; with headroom and variance, size for a multiple, not the minimum.
- Queue wait is a function of utilization. An M/M/1 approximation: `Wq = rho / (1 - rho) * service time`. The same service time at 50 percent utilization queues about 1x service time; at 90 percent it queues about 9x.

| Utilization | Approx. queue factor | Practical reading |
|---|---|---|
| 50% | ~1x | Comfortable; room for bursts |
| 70% | ~2.3x | Normal operating target |
| 80% | ~4x | Tails become visible |
| 90% | ~9x | Fragile; small spikes hurt |
| 95% | ~19x | Incident waiting to happen |

- Convert every latency SLO into a concurrency limit: `max in-flight = throughput target * latency budget`. Enforce it rather than hoping load balancers distribute perfectly.
- Little's Law applies to any stable queue: message consumers, thread pools, CDN requests, database sessions. Use it to reconcile "we have capacity" claims with observed queue depth.

## Amdahl and the Scalability Law

- Amdahl: if a fraction `s` of the work is serial, speedup is capped at `1/s` no matter how many workers you add. `S(n) = 1 / (s + (1-s)/n)`.
- A 10 percent serial fraction caps total speedup at 10x. Optimization effort spent parallelizing the 90 percent has a hard ceiling until the serial part shrinks.
- Serial sources are often hidden: a shared lock, a single writer, a global counter, one database primary, a synchronous audit log, a global rate limiter.
- The Universal Scalability Law adds coherency cost: past a point, adding workers can reduce throughput because coordination grows. Retrogression is real; measure scaling curves by traffic level, not just at one point.
- Practical rule: find the serial fraction first. Parallelizing an already-parallel section is often wasted work.

## Performance Budgets

A budget turns performance into an engineering constraint that can be reviewed, tested, and alerted on.

| Budget type | Example | Enforced by |
|---|---|---|
| Latency | API p95 < 300 ms server time | Alert on histogram, CI threshold on benchmark |
| Frontend | LCP p75 < 2.5 s, INP p75 < 200 ms | RUM alert, Lighthouse CI budget |
| Throughput | 2x peak with p99 < 1 s | Load test gate, capacity plan |
| Resource | < 100 MB RSS per pod, < 2 CPU cores per 1k rps | Limits, saturation alerts, profiling |
| Connections | DB pool never > 80 percent busy at peak | Pool metrics alert |
| Cost | < $0.002 per 1k requests | Cost dashboard and unit review |
| Regression | no benchmark slower by more than noise band | CI benchmark comparison |

Latency budget example for a 400 ms p95 API endpoint:

| Segment | Budget |
|---|---|
| Client network | 40 ms |
| Edge / gateway | 20 ms |
| Auth / middleware | 25 ms |
| Application logic | 80 ms |
| Database | 150 ms |
| Serialization and payload | 25 ms |
| Slack for variance | 60 ms |

- Allocate budgets before optimizing; when a segment exceeds its share, that is the target.
- Budgets must have an owner and a consequence (build failure, alert, ticket). A budget nobody enforces is documentation.
- Set budgets from user impact: research on abandonment and conversion thresholds, not from what the current system happens to do.

## Benchmarking Hygiene

- Warm up before measuring: JIT compilation, lazy initialization, connection pools, and caches all change behavior in the first seconds.
- Measure steady state, then report variance. If run-to-run spread exceeds the effect you are claiming, the claim is noise.
- Use open models (arrival-rate) for latency claims; closed-loop models hide coordinated omission and can overstate capacity by large factors. See `./08-load-testing.md`.
- Pin and document the environment: CPU model and frequency, memory, container limits, kernel and runtime versions, database volume. Compare like with like.
- Disable or account for background work (autovacuum, backups, cron, log shipping) during benchmark windows.
- Run at least 3-5 repetitions and report median plus range; never pick the best run.
- For microbenchmarks, use a real harness (JMH, criterion, pytest-benchmark, hyperfine) to avoid dead-code elimination, constant folding, and loop-invariant hoisting.
- Validate that the benchmark measures what you think: instrument it, count calls, and confirm the work actually happens.

Microbenchmark pitfalls worth stating explicitly:

| Pitfall | Effect | Mitigation |
|---|---|---|
| Dead-code elimination | Optimizer removes the work | Consume results via side effect or sink |
| Constant folding | Same inputs optimized away | Vary inputs from an array or runtime source |
| Loop-invariant hoisting | Computation moves out of the loop | Time inside the loop body explicitly |
| Timer resolution | Tiny operations measure as zero | Batch iterations, use monotonic clocks |
| Warmup mixing | Mean skews high or low | Discard warmup runs, report medians |

## Reading Results Without Fooling Yourself

- Compare against the budget first; ignore improvements that do not move the target metric.
- Check the load level alongside the number. "p99 improved" is meaningless if the new test ran at half the traffic.
- Look for discontinuities: a knee in the throughput/latency curve marks the real operating ceiling, not the peak number observed.
- Distinguish throughput-limited from latency-limited results; the fix is different.
- Treat single-run wins under 2x the noise band as unproven and repeat the measurement.

## Anti-Patterns

- Optimizing from intuition with no baseline, then declaring victory without a re-measurement.
- Reporting an average latency and calling it the latency.
- Averaging percentiles across hosts or minutes.
- Comparing benchmarks run on different hardware, builds, or data volumes.
- Closed-loop load testing and then quoting the resulting percentile as the production tail.
- Tuning the benchmark rather than the system (shorter payloads, warm caches, seed data).
- Chasing a 5 percent win while a 10x pathological path remains on the critical route.
- Measuring only with empty caches and then promising cache-friendly numbers.
- Letting performance numbers live in a chat thread instead of next to the change.

## Checklist

- [ ] The question, metric, percentile, load level, and budget are written down before work starts.
- [ ] A reproducible baseline exists in a comparable environment.
- [ ] USE and RED checked for every component on the path.
- [ ] Latency reported as percentiles with sample size and window; no averaged percentiles.
- [ ] Little's Law used to sanity-check concurrency, pool sizes, and queue depths.
- [ ] Serial fraction identified before parallelization work.
- [ ] Budgets have owners and enforcement (CI gate or alert).
- [ ] Benchmarks use open models, warmup, repetitions, and documented environments.
- [ ] Before/after numbers recorded with the change and re-measured after release.
