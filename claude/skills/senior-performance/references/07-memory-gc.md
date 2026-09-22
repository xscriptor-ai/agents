# Memory and GC

Scope: leak detection, per-runtime GC tuning, allocation reduction, pools and arenas, object lifetimes, and OOM diagnosis.

## Memory Model Basics

- Distinguish virtual memory, resident set size (RSS), heap, and off-heap. Only RSS and container/cgroup accounting decide whether the OOM killer fires.
- Page cache and memory-mapped files count against the cgroup in container environments; a service can be OOM-killed while its own heap looks small.
- Managed heaps need headroom beyond live data; collectors need room to run concurrently, and allocators fragment. A heap 95 percent full is already unhealthy.
- Distinguish leak (live set grows forever), burst (temporary spike), working-set growth (legitimate new data), and fragmentation (high RSS with low live bytes). The fixes are different.
- Set memory requests and limits thoughtfully: too low causes OOM kills; too high wastes capacity. See `./09-capacity-cost.md`.

## Object Lifetimes

- Most objects die young in most workloads (the generational hypothesis). Nursery/young collections are cheap; promotion of surviving objects into long-lived space is what causes major collections.
- Long-lived object graphs are expensive: they get marked on every major collection and retain everything they reference. Keep caches and registries bounded and evictable.
- Escape analysis lets compilers allocate on the stack when references do not escape; returning pointers to locals or capturing them in closures forces heap allocation.
- Allocation rate is the primary GC lever: halving allocation rate often cuts collection CPU and pause frequency more than any collector flag.
- Watch object graph depth: a long linked structure or deeply nested tree keeps many objects alive transitively and slows marking.
- Ephemeral but large allocations (big buffers, parsed documents, response payloads) dominate peak RSS even if they are short-lived; reuse or stream them.

## Allocation Reduction

| Pattern | Problem it fixes | Notes |
|---|---|---|
| Reusable buffers (pool or explicit) | Per-request buffer churn | Reset length, never reuse across security domains |
| Streaming instead of buffering | Large payload memory spikes | Parse and emit incrementally |
| Slice/array preallocation | Repeated growth copies | Size hints from expected cardinality |
| String building (builder/rope) | Quadratic concatenation | Avoid `+=` in loops on immutable strings |
| Struct/value types | Boxing and heap escapes | Language-specific; measure first |
| Zero-copy views | Copies between layers | Watch lifetime and aliasing hazards |
| Batching of small objects | Allocator overhead per object | Better locality and fewer collections |

- Profile allocations before optimizing; the hottest allocator call site is often not the largest consumer. See `./04-backend-profiling.md`.
- Reduce temporary objects in serialization paths: encoders that allocate per field dominate CPU profiles in some services. Reuse encoders and write into buffers.
- Avoid accidental retention: closure captures, slices of large arrays, and substring implementations that keep the parent buffer alive.
- For JSON and binary formats, consider zero-copy or precompiled codecs; verify latency and memory tradeoffs with a benchmark.
- Beware copy amplification: a payload copied through several layers can multiply memory and CPU. Pass references or move ownership.

## Pools and Arenas

- Object and buffer pools amortize allocation and collection cost for frequently created, similarly sized, short-lived objects. They are most effective under high churn and predictable sizes.
- Pools require discipline: reset state on get/put, bound total size, and account for pooled memory in limits. A pool that only grows is a leak with extra steps.
- Buffer pools (`sync.Pool`-style, `bytebufferpool`-style) reduce GC pressure in network services; bytes must be cleared or truncated before reuse when they held sensitive data.
- Arena and region allocators allocate many objects in one block and free together; ideal for request-scoped or batch-scoped lifetimes.
- Slab allocators reduce fragmentation for same-size allocations at the system-allocator level; mostly an infrastructure concern unless you write a custom allocator.
- Pools can hurt: cache misses, retention of rarely used objects, and cross-thread contention. Benchmark with and without.

## Allocators and Fragmentation

- General-purpose allocators trade speed, overhead, and fragmentation. Under churn with mixed size classes, RSS can exceed live bytes by a large factor.
- Size-class fragmentation comes from many distinct allocation sizes; aligning buffer sizes to common classes improves reuse.
- Arena retention: freed memory may stay in the process instead of returning to the OS. Release policies exist per allocator and runtime; verify upstream.
- Switch allocators only with benchmarks: jemalloc, mimalloc, and tcmalloc often help multicore scaling and fragmentation, but change CPU behavior too.
- Distinguish allocator fragmentation from collector heap fragmentation; the metrics and fixes differ.
- Huge-page and transparent huge-page settings change both performance and memory accounting on modern kernels and cloud hosts.

## Leak Detection

- Leaks are trends, not snapshots. Monitor RSS and heap live-set over days, normalized by traffic; a slow upward slope under steady load is the signal.
- Heap snapshot diff workflow: capture under steady traffic, wait or force GC, capture again, then rank by delta and inspect the dominant retainer path of the largest growers.
- Compare live size after full collections, not total heap size; a large heap can be mostly garbage waiting to be collected.
- Common leak sources:

| Source | Signature | Fix |
|---|---|---|
| Unbounded cache / map | Live set tracks key cardinality | Bound, TTL, evict. See `./02-caching.md` |
| Event listeners never removed | Listeners equal subscriptions over time | Deregister on teardown and scope lifetimes |
| Captured request context in long-lived closure | Heap grows with requests processed | Do not hold request-scoped objects in singletons |
| Static or global registry | Unique keys accumulate | Weak references or explicit expiry |
| Thread-locals holding payloads | Per-thread growth that never shrinks | Clear on release; sized pools |
| Queue or DLQ backlog | Depth grows, not heap shape | Bound and drain; fix consumer. See `./06-concurrency-backpressure.md` |
| Goroutines/threads blocked | Stack memory plus retained references | Find blocking call; add timeouts |
| Subprocesses or file handles | OS memory outside the heap | Close/reap; watch handle counts |

- In managed runtimes, weak and soft references plus reference queues help caches hold objects only while memory permits; understand which reference type the runtime treats as evictable.
- Native and off-heap memory leaks do not appear in heap profiles: watch metrics for direct buffers, JNI/native areas, mmap counts, and RSS. Tools differ per runtime.
- Add a soak test to CI or staging that asserts a stable memory ceiling under sustained load. See `./08-load-testing.md`.

## OOM Diagnosis

1. Confirm the mechanism: kernel OOM killer (cgroup limit), runtime out-of-memory error (heap), or native allocation failure. They need different fixes.
2. Read the evidence: cgroup `memory.events`/`memory.peak` on v2 or `memory.usage_in_bytes` on v1, kernel logs for OOM kills, and the runtime's own logs.
3. Check limits against actual usage: a working set that grew past a stale limit looks like a leak but may be legitimate growth. Reconcile with traffic growth.
4. Capture before death: configure heap dump on OOM where supported, and core dumps only if you have the tooling and storage to use them.
5. Distinguish scenarios:

| Scenario | Evidence | Typical fix |
|---|---|---|
| Leak | Live set rises steadily under steady load | Fix retainer; see leak table above |
| Traffic growth | Memory tracks load, resets on scale-in | Right-size limits and instance count |
| Burst / large request | Spike around specific payloads | Stream, bound request size, pool buffers |
| Fragmentation | High RSS, low live heap | Allocator tuning, size classes, pools |
| GC headroom too small | GC thrash before OOM | Raise heap/limit or cut allocation rate |
| Off-heap growth | Heap stable, RSS grows | Direct buffers, JNI, mmap, native libs |

6. After the fix, add a memory ceiling alert and a soak test so the failure mode stays visible.

## GC Fundamentals

- Every collector trades throughput, latency (pause), and footprint. You cannot maximize all three; tune for the service's SLO.
- Stop-the-world pauses are what users feel; concurrent phases cost CPU and need headroom to complete before the heap fills.
- Generational collectors assume most objects die young; surviving data is promoted, which is why long-lived caches eventually make every major collection expensive.
- Allocation stalls and "GC thrash" happen when the live set approaches the heap limit; the collector spends most of its CPU reclaiming little memory. The fix is less live data or a larger ceiling, not more aggressive collection.
- Compact or evacuate based collectors move objects, which limits fragmentation but adds copy cost; mark-sweep leaves fragmentation behind.
- GC logging is nearly free and should be enabled in production where supported; you cannot tune what you cannot see.

## Per-Runtime Tuning

| Runtime | Collector(s) | Primary knobs | Notes |
|---|---|---|---|
| JVM | G1 (default), ZGC, Shenandoah | `-Xmx`/`-Xms`, `MaxRAMPercentage`, region size, GC threads | Generational ZGC and Shenandoah are the low-pause options in the JDK 21+ era; verify upstream |
| Go | Concurrent mark-sweep with pacing | `GOGC`, `GOMEMLIMIT`, `GOMAXPROCS`, `GODEBUG` | `GOMEMLIMIT` is a soft limit; set it under container limits. Verify upstream for your Go release |
| Python | Reference counting plus cyclic GC | `gc.freeze`, generation thresholds, `PYTHONMALLOC` | Cyclic GC handles reference cycles only; pymalloc fragmentation is a separate problem |
| Node.js | Scavenger plus mark-compact | `--max-old-space-size`, `--max-semi-space-size`, GC traces | External buffers live outside the V8 heap; track them separately |
| .NET | Workstation and Server GC, background GC | Server GC mode, heap hard limit, DATAS | LOH and POH have special allocation behavior |
| Rust | None (ownership) | Allocator choice, arena crates | Reference cycles need `Weak` or arenas; native memory is still yours to manage |

- JVM in containers: use `MaxRAMPercentage` or an explicit `-Xmx` derived from the cgroup limit, leaving headroom for metaspace, threads, JIT code, direct buffers, and the collector's own structures.
- Go: `GOGC` sets the heap growth target; `GOMEMLIMIT` complements it for containerized services. Set the limit below the container limit and watch for GC thrash if live data approaches it.
- Python: long-running services with many immutable objects can disable or tune cyclic GC only after proving no cycles leak; `gc.freeze` helps fork-heavy prefork servers.
- Node: raise `--max-old-space-size` only with matching container limits; most "Node memory leaks" are unbounded caches, listeners, or async queues.
- GC tuning changes should be measured with the same load model; small pause improvements that cut throughput are usually a bad trade.

## Sizing and Limits

- Container limit = runtime heap + off-heap + native + page-cache share + collector headroom. Undersizing headroom is the most common OOM cause after actual leaks.
- Leave at least 20-30 percent headroom beyond the expected live set so concurrent collection and bursts have room; verify with a soak test and a worst-case workload.
- Prefer live-set monitoring over heap-size monitoring: heap utilization near 100 percent with a low live set is healthy; a high live set is the risk.
- Scale out when per-instance memory cannot grow further, and revisit object lifetimes before scaling up. See `./09-capacity-cost.md`.

## Anti-Patterns

- Treating any memory growth as a leak without normalizing by traffic and time.
- Tuning GC flags before reducing allocation rate or bounding caches.
- Setting container limits without heap/off-heap headroom analysis.
- Using `RSS` or heap size as the sole alert when live-set is the actionable metric.
- Pools without size bounds or reset discipline.
- Heap snapshots taken without a GC, then interpreted as live data.
- Ignoring off-heap and native allocations because the managed heap looks clean.
- Disabling GC logging in production, then guessing during an incident.
- Copying GC flags between services with different allocation profiles.

## Checklist

- [ ] Memory alerts use live-set and RSS trends normalized by traffic, not raw heap size.
- [ ] Caches, registries, and queues are bounded and evictable.
- [ ] Allocation hot spots reviewed before/after GC tuning.
- [ ] Collector and heap settings derived from container limits with documented headroom.
- [ ] GC logging enabled where supported; pause and CPU metrics collected.
- [ ] Leak workflow documented: trend, snapshot diff, dominant retainer, fix, verify.
- [ ] OOM response distinguishes leak, growth, burst, fragmentation, and headroom.
- [ ] Off-heap and native memory tracked separately from the managed heap.
- [ ] Soak test asserts a stable memory ceiling under sustained load.
- [ ] Tuning changes are measured under the same load model and recorded.
