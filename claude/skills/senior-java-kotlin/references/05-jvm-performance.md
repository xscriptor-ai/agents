# JVM Performance

Scope: measuring and tuning JVM services: JIT behavior, garbage collector choice, JFR, heap sizing, thread scaling, and profiling workflow.

## Method before flags

1. Define the objective: latency SLO (p50/p95/p99), throughput, memory footprint, startup time, or cost.
2. Establish a baseline with production-like load. Numbers without a load model are noise.
3. Measure with the right tool: JMH for microbenchmarks, JFR for production, load generators (k6, Gatling, wrk) for macro.
4. Change one variable at a time; keep a written record of flag, expectation, and result.
5. Re-measure after every dependency, JDK, or traffic change. Performance is not a permanent property.

Golden rules:

- Percentiles, never averages. A p99 that trips the SLO is the user-visible problem.
- Allocation rate drives GC pressure; reducing garbage usually beats GC tuning.
- Latency budgets decompose: queue time + service time + downstream + GC pauses. Identify which term dominates before tuning.
- Beware coordinated omission in load tests; use constant-rate generators with correct latency accounting.
- Do not tune the JVM when the database, network, or lock contention is the bottleneck (`./04-persistence.md`).

## JIT basics

| Stage | Role |
| --- | --- |
| Interpreter | Executes bytecode immediately; collects profile data |
| C1 (client) | Fast compilation, light optimization; good for short-lived methods |
| C2 (server) | Aggressive optimization after profiles mature; peak performance |
| Tiered compilation | Default: interpreter → C1 → C2 based on invocation/loop counters |

What C2 does:

- Inlining (the gateway to most other optimizations), devirtualization, escape analysis (scalar replacement, lock elision), loop unrolling, constant folding.
- Deoptimization: when an assumption breaks (new subclass loaded, type profile mismatch), the method falls back and may be recompiled.
- Inlining limits: `-XX:MaxInlineSize`, `-XX:FreqInlineSize`; rarely worth changing. Prefer small, monomorphic call sites in hot paths.

Hot-path guidance:

- Keep hot code simple and monomorphic; avoid megamorphic dispatch (many implementations of the same interface at one call site).
- Avoid allocation in hot loops (boxing, varargs, streams over primitives, string concatenation) when profiling shows allocation pressure.
- `-XX:+PrintCompilation` and `-XX:+UnlockDiagnosticVMOptions -XX:+PrintInlining` for investigation, not production.
- Warmup matters: serverless and short-lived processes pay compilation cost every cold start; consider AOT caches or native images (`./10-migration-modernization.md`).
- Do not micro-tune what the profiler does not show. Measure allocation and CPU with JFR/async-profiler first.

Anti-patterns:

- Adding complexity for CPU wins that are lost in database or network time.
- Running microbenchmarks without JMH (dead-code elimination, constant folding, no warmup).
- Disabling tiered compilation or forcing C2-only because "it is faster".

## Garbage collector selection

| Collector | Best for | Pause profile | Status |
| --- | --- | --- | --- |
| G1 (default) | Balanced web services, heaps ~4-32 GB | Tens to low hundreds of ms, region-based | Mature default |
| Generational ZGC | Latency SLOs, large heaps, high allocation | Sub-millisecond to low ms | Production since 23, default generational mode |
| Generational Shenandoah | Latency with lower footprint, no large-heap requirement | Low ms | Available and maturing; verify status in your JDK |
| Parallel | Batch/throughput, pause-insensitive | Long stop-the-world pauses | Mature |
| Serial | Tiny heaps, single-core containers | Full pauses, short heaps | Mature |
| Epsilon | Testing allocation behavior, latency measurement | None (never collects) | Diagnostic only |

Selection guidance:

- Start with G1. Move to generational ZGC when p99 latency is dominated by GC pauses or heap/allocations grow beyond what G1 handles smoothly.
- For pure throughput batch jobs, Parallel often wins on CPU efficiency; measure instead of assuming.
- ZGC's CPU overhead is real; latency-sensitive but CPU-constrained services may prefer Shenandoah or G1.
- Never run non-generational ZGC: it was removed; generational is the only mode.
- Keep collectors consistent across environments; GC behavior differences cause "works in staging" incidents.

Key flags (prefer minimal tuning):

```bash
# Balanced default
-XX:+UseG1GC -XX:MaxGCPauseMillis=200

# Low-latency large heap
-XX:+UseZGC -XX:+ZGenerational

# Throughput batch
-XX:+UseParallelGC

# Always useful on modern JVMs
-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/var/dumps
-Xlog:gc*:file=/var/log/gc.log:time,uptime,level,tags:filecount=5,filesize=20M
```

Rules:

- Log GC always. GC logs are cheap and invaluable; structured unified logging (`-Xlog`) replaced the old flags.
- `MaxGCPauseMillis` is a goal, not a guarantee; for ZGC it is irrelevant.
- Tuning knobs like region size, IHOP (`InitiatingHeapOccupancyPercent`), and survivor sizes should only move with JFR evidence.
- Watch allocation rate (`jdk.ObjectAllocationSample`), promotion rate, and GC cause in JFR.
- Container CPU limits throttle GC threads; ensure `ActiveProcessorCount` reflects the limit and GC thread counts are sane.

Anti-patterns:

- Copy-pasting flag sets from blog posts without understanding heap sizes and allocation profiles.
- Setting `-Xmn`/new-gen sizes on collectors that manage them dynamically.
- Disabling explicit GC (`-XX:+DisableExplicitGC`) without knowing what calls it (`System.gc()` in libraries).
- Ignoring GC logs until an incident.

## Heap sizing and memory anatomy

Process memory is more than heap:

| Region | Notes |
| --- | --- |
| Heap (`-Xmx`) | Java objects; GC-managed |
| Metaspace | Class metadata; grows with frameworks/proxies; cap with `MaxMetaspaceSize` |
| Code cache | JIT-compiled code; bounded by `ReservedCodeCacheSize` |
| Thread stacks | ~0.5-1 MB per platform thread; virtual threads are heap objects |
| Direct/native buffers | Netty, NIO; bounded by `MaxDirectMemorySize` |
| GC structures | Marking bitmaps, remembered sets; grows with heap |
| Class data sharing / AOT | Shared archive mappings |

Sizing rules:

- Set `-Xms` equal to `-Xmx` in containers to avoid resizing churn and fragmentation.
- Container awareness is on by default: the JVM reads cgroup limits. Use `-XX:MaxRAMPercentage` (e.g., 70-75) instead of absolute `-Xmx` in autoscaled environments.
- Leave headroom beyond the heap: metaspace, code cache, stacks, and direct buffers can add hundreds of MB. A container OOM-killed at the limit with a healthy heap is a sizing bug.
- Cap `MaxMetaspaceSize` to surface classloader leaks as `OutOfMemoryError: Metaspace` instead of node exhaustion.
- Thread-per-request services with large platform-thread pools burn stack memory; virtual threads trade that for heap objects.
- Use `-XX:NativeMemoryTracking=summary` in staging (not production) and `jcmd <pid> VM.native_memory summary` to reconcile.

OOM taxonomy:

| Error | Meaning | Typical cause |
| --- | --- | --- |
| `Java heap space` | Heap exhausted | Leak, cache without bounds, oversized fetch |
| `GC overhead limit exceeded` | Heap ~full, GC thrash | Same, plus undersized heap |
| `Metaspace` | Class metadata exhausted | Redeploys, dynamic proxies, classloader leak |
| `Compressed class space` | Class pointers exhausted | Same classloader leaks |
| `Direct buffer memory` | NIO allocations exceed cap | Netty leaks or missing release |
| `unable to create native thread` | OS thread limit | Thread leak or huge pools |
| Container killed (OOMKilled) | cgroup limit exceeded | Heap + off-heap over the limit |

Anti-patterns:

- Chasing heap size when off-heap/direct memory is the real consumer.
- Using heap dumps as the only diagnostic: capture thread dumps, JFR, and GC logs in parallel.
- Huge `-Xmx` with G1 and no pause SLO; pauses scale with live set/region work.

## JFR and profiling workflow

JFR (Java Flight Recorder):

- Built into the JVM, low overhead (about 1% at default settings), safe for production.
- Continuous recording with a disk-backed repository: `-XX:StartFlightRecording:disk=true,maxsize=512m,filename=/var/rec/ongoing.jfr`.
- Or start on demand: `jcmd <pid> JFR.start name=incident settings=profile duration=5m filename=/tmp/incident.jfr`.
- Key events: `jdk.ExecutionSample`, `jdk.ObjectAllocationSample`, `jdk.JavaMonitorEnter`, `jdk.ThreadPark`, `jdk.GCPhasePause`, `jdk.VirtualThreadPinned`, `jdk.SocketRead/Write`, `jdk.FileRead/Write`, `jdk.ThreadStart`.
- Analyze with JDK Mission Control (JMC) or the `jfr` CLI (`jfr summary`, `jfr print --events jdk.ExecutionSample`).

async-profiler:

- Flame graphs for CPU, allocation (`-e alloc`), lock (`-e lock`), and wall-clock (`-e wall`) profiles.
- Wall-clock profiling is the right tool for latency work: it shows blocked time, which CPU sampling misses.
- Safe-mode profilers (JFR-based, `-e itimer`) avoid safepoint bias when needed.
- `-d 60 -f out.html` for a 60-second incident capture; attach to a PID without restarting.

Workflow:

1. Reproduce with a load model matching production traffic mix.
2. Capture JFR + async-profiler wall/CPU for the affected window.
3. Classify: CPU-bound, allocation/GC-bound, lock/park-bound, I/O-bound, or downstream-bound.
4. Fix the dominant term; re-measure.
5. For leaks: enable heap dumps, take two dumps separated by time, diff dominator trees in Eclipse MAT or `jcmd GC.class_histogram` for a quick view.

Common findings and fixes:

| Finding | Likely fix |
| --- | --- |
| High `jdk.ObjectAllocationSample` on JSON/serialization | Streaming serializers, reuse buffers, project only needed fields |
| Lock contention on a monolith object | Narrow locks, concurrent collections, striping, or split state |
| Threads parked on DB sockets | Connection pool too small, slow queries, or missing indexes (`./04-persistence.md`) |
| Frequent young GC with short-lived survivors | Increase eden or reduce allocation rate; check promotion |
| CPU in regex/string ops | Precompile patterns, avoid `String.split` in loops, use `indexOf` |
| Pinning events | Replace `synchronized`/native calls on virtual-thread paths (JDK 21-23) |
| Classloader growth after redeploys | Framework proxy leaks, unclosed contexts, thread locals holding classloaders |

## Threads vs virtual threads at scale

- Platform threads: roughly 1 MB stack each plus scheduling cost; a few thousand is the practical ceiling before memory and context switching dominate.
- Virtual threads: heap-allocated continuations mounted on a small carrier pool (default parallelism = available processors). Hundreds of thousands are feasible for blocking I/O workloads.
- Scaling model: platform-thread services scale by pool sizing; virtual-thread services scale by heap and downstream capacity.
- Carrier pool tuning exists (`jdk.virtualThreadScheduler.parallelism`, `maxPoolSize`) but is rarely the right lever; fix pinning and downstream limits first.
- What breaks first after adopting virtual threads is usually the database pool or a downstream rate limit, not the JVM. Add concurrency limiters (semaphores, rate limiters, bulkheads).
- CPU-bound work should stay on a bounded pool (`Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors())` or `ForkJoinPool`); virtual threads add scheduling overhead without parallel speedup.
- Thread locals on virtual threads multiply with task count; prefer scoped values (`./01-java-core.md`).

Anti-patterns:

- Pooling virtual threads to "protect" resources.
- Migrating to virtual threads while leaving `synchronized` blocking sections on JDK 21-23.
- Assuming virtual threads fix slow downstreams; they only remove thread scarcity.

## Microbenchmarking with JMH

```java
@Benchmark
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@Warmup(iterations = 5, time = 1)
@Measurement(iterations = 10, time = 1)
@Fork(3)
public long parse(BenchmarkState state) {
    return state.parser.parse(state.input).size();
}
```

Rules:

- Use JMH; never `System.nanoTime()` loops. JMH handles warmup, dead-code elimination, forks, and statistics.
- Consume results (`Blackhole`) and avoid loop-invariant hoisting.
- Report p50/p99 (`Mode.SampleTime`) when tail behavior matters.
- Benchmark realistic data sizes and shapes; microbenchmarks validate hypotheses, they do not predict system performance.
- Keep JMH benchmarks in a separate source set/module so they never ship in production artifacts.

## Production safety checklist

- [ ] Latency SLO defined in percentiles, with a load model that reflects production.
- [ ] JFR continuous recording enabled with bounded disk usage; GC logging on.
- [ ] Heap sized with off-heap headroom; `Xms == Xmx`; container limits honored.
- [ ] Collector chosen deliberately and documented; no cargo-cult flags.
- [ ] Thread model documented (platform vs virtual); pinning checked on JDK 21-23.
- [ ] Downstream limits (DB pool, HTTP concurrency, rate limits) set from capacity, not hope.
- [ ] Heap dumps and thread dumps captured automatically on OOM/crash.
- [ ] Performance regression tests or canary checks in CI/CD for critical paths.
- [ ] Runbooks for CPU, memory, and latency incidents reference actual dashboards and JFR commands.
