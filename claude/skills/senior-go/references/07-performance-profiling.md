# Performance and Profiling

Scope: measuring before optimizing, pprof profiles, execution traces, escape analysis, allocation reduction, GC tuning, `sync.Pool`, and benchmark discipline for Go 1.22-1.26.

## Method

1. **Define the metric** — latency percentiles, throughput, allocations per op, RSS, or GC pause. "Slow" is not a metric.
2. **Reproduce** with a benchmark, load test, or a profile from production. Never optimize from code reading alone.
3. **Profile** to find where time/memory actually goes.
4. **Change one thing** and re-measure with the same harness and `benchstat`.
5. **Guard the regression** with a benchmark or budget test in CI.

Most production latency is waiting (I/O, locks, queueing), not CPU. Start with traces/logs for latency and CPU profiles for throughput.

## pprof

Enable in servers via `net/http/pprof` (import for side effects) on an internal-only listener or admin mux. **Never expose it publicly**: profiles leak memory contents and function arguments, and CPU profiling is a DoS vector.

```go
admin := http.NewServeMux()
admin.HandleFunc("/debug/pprof/", pprof.Index)
admin.HandleFunc("/debug/pprof/profile", pprof.Profile)
admin.HandleFunc("/debug/pprof/trace", pprof.Trace)
go http.ListenAndServe("127.0.0.1:6060", admin)
```

| Profile | Collect | Shows | Use for |
|---|---|---|---|
| CPU | `/debug/pprof/profile?seconds=30` | sampled stack time at 100 Hz | hot functions, cycles |
| Heap | `/debug/pprof/heap` | sampled allocations (`alloc_space`/`alloc_objects`) and live (`inuse_space`) | allocation sources vs retained memory |
| Goroutine | `/debug/pprof/goroutine?debug=2` | all goroutine stacks | leaks, blocked workers |
| Block | `runtime.SetBlockProfileRate` | time blocked on sync primitives | channel/mutex contention |
| Mutex | `runtime.SetMutexProfileFraction` | lock contention | hot locks |
| Threadcreate | `/debug/pprof/threadcreate` | OS thread creation | cgo/syscall storms |

Block and mutex profiles are off by default because they add overhead; enable with rates (for example `SetMutexProfileFraction(100)` samples 1/100 events) in staging, not permanently in production.

Interpreting:

```bash
go tool pprof -http=:8081 http://localhost:6060/debug/pprof/profile?seconds=30
go tool pprof -top -cum ./bin/app cpu.prof
go tool pprof -list=MyFunc ./bin/app cpu.prof
go tool pprof -diff_base=before.prof after.prof
```

- `-cum` shows cumulative cost including callees; `-flat` shows self time. Read both.
- `-list=Func` maps samples to source lines; the answer is usually a specific line, not an architecture.
- Compare profiles with `-diff_base` to prove a change helped.
- For tests: `go test -bench=. -cpuprofile=cpu.prof -memprofile=mem.prof`, then `go tool pprof -http=:8080 cpu.prof`.
- For CLIs: `runtime/pprof` `StartCPUProfile`/`WriteHeapProfile` behind a flag.
- Continuous profiling (Pyroscope, Grafana, cloud profilers) is the production-grade alternative; it samples many instances over time and shows trends. Overhead is usually low single-digit percent; verify per vendor.

## Execution trace

Use `runtime/trace` when the question is about **scheduling, blocking, or latency**, not CPU cost.

```go
f, _ := os.Create("trace.out")
defer f.Close()
if err := trace.Start(f); err != nil {
	return err
}
defer trace.Stop()

ctx, task := trace.NewTask(ctx, "request")
defer task.End()
trace.WithRegion(ctx, "db-query", func() { ... })
```

- `go tool trace trace.out` opens the web UI: goroutine states, syscalls, GC, network waits, scheduler latency.
- Tasks/regions give semantic context in the trace; without them you see addresses of functions, not user journeys.
- The **flight recorder** (1.25+) keeps a rolling window and writes it on trigger, which is the right tool for rare latency spikes; verify the current API upstream.
- Trace overhead is higher than pprof; record short windows (seconds), not hours.

## Escape analysis and allocation discipline

```bash
go build -gcflags='-m=2' ./... 2>&1 | grep -E 'escapes to heap|moved to heap'
```

Common escape causes:

- Returning a pointer to a local: legal and usually necessary, but it allocates; returning a value can keep it on the stack for small types.
- Interface boxing: passing a concrete value to `any` (fmt, errors, slog args) allocates unless the value fits an internal cache.
- Closures capturing variables that outlive the function; goroutines always capture.
- Sending a pointer through a channel or storing it in a slice of interfaces.
- `defer` with a closure over loop state (open-coded defers avoid the allocation for simple cases).
- Converting between `[]byte` and `string` around I/O; use `unsafe` only with a documented, measured reason.

High-yield allocation fixes:

| Fix | Gain |
|---|---|
| `strconv` instead of `fmt.Sprintf`/`Sprintf` in hot paths | removes boxing + parsing |
| `strings.Builder` with `Grow` | linear instead of quadratic concat |
| Presize `make([]T, 0, n)` and `make(map[K]V, n)` | removes growth copies/rehashes |
| `slices.Grow`/`bytes.Buffer.Grow` | predictable buffers |
| `io.CopyBuffer` with a pooled buffer | avoids default 32 KiB alloc per call |
| Return values instead of pointers for small structs | fewer heap objects |
| Avoid `[]any`/`map[string]any` for row data | fewer allocations, better type safety |
| Struct field ordering largest→smallest | less padding (measure first) |

Inlining: small functions (roughly under the compiler's cost budget) inline automatically; `-gcflags=-m` reports decisions. Mid-stack inlining has widened what inlines. For hot paths, avoid making wrapper functions too large to inline, but do not contort code for it.

Profile-Guided Optimization (PGO, 1.21+): commit `default.pgo` (from production samples) and the build applies it; typical gains are modest (a few percent) and workload-dependent. Verify current tooling support upstream.

## GC tuning

Go's GC is a concurrent mark-sweep with a pacing controller. Two knobs matter:

- `GOGC` (default 100) — target heap growth between collections. Lower = less memory, more CPU; higher = the reverse.
- `GOMEMLIMIT` (1.19+) — soft memory limit; the GC works harder to respect it. This is the correct response to container memory limits.

```go
debug.SetMemoryLimit(512 << 20)
debug.SetGCPercent(200) // when CPU-bound and memory is abundant
```

- `GOMEMLIMIT` is soft: it cannot stop allocation, so a leak still OOMs. Leave headroom above it for non-heap memory (stacks, OS buffers, cgo).
- Setting `GOMEMLIMIT` slightly below the container limit lets the runtime throttle instead of the kernel killing the process.
- The old "ballast" trick is obsolete; `GOMEMLIMIT` supersedes it.
- Container awareness: recent toolchains derive `GOMAXPROCS` from cgroup CPU limits (1.25+, verify), reducing scheduler oversubscription. If you pin CPU via `GOMAXPROCS`, do not exceed the cgroup quota.
- Diagnose GC problems with `GODEBUG=gctrace=1` (pause times, heap growth) and heap profiles, then adjust.
- `runtime.ReadMemStats`/`runtime/metrics` for programmatic telemetry; export key GC metrics via Prometheus ([./08-observability-security.md](./08-observability-security.md)).

## sync.Pool

Use for short-lived temporary buffers where allocation is a measured hotspot; not as a general cache.

```go
var bufPool = sync.Pool{
	New: func() any { b := make([]byte, 0, 32<<10); return &b },
}

func handle(w io.Writer, data []byte) {
	bp := bufPool.Get().(*[]byte)
	defer bufPool.Put(bp)
	b := (*bp)[:0]
	b = append(b, data...)
	w.Write(b)
}
```

- Pooled values may be dropped at any GC; never rely on state or count.
- Reset before use and before returning; do not return huge buffers, or the pool becomes a memory retention bug (cap them).
- `sync.Pool` is safe for concurrent use and cheap; `bytes.Buffer` values can be pooled directly.
- Avoid pooling small structs; the pool overhead exceeds the allocation savings. Measure.
- Go 1.24+ runtime has improved small-object allocation paths (for example, small non-pointer allocations); still measure on your workload, not from release notes.

## Latency and throughput work

- Track percentiles (p50/p95/p99) via histograms, not averages.
- Queueing is the usual culprit: bounded pools, connection limits, and single-threaded locks create wait time that CPU profiles cannot see. Use the block/mutex profiles and execution traces.
- Batching and pipelining beat micro-optimizations for I/O-bound code: fewer round trips, fewer syscalls (`bufio`, bulk writes).
- Avoid N+1 queries and per-request client construction ([./04-web-services.md](./04-web-services.md), [./05-data.md](./05-data.md)).
- Beware coordinated omission when load testing: a closed-loop generator hides stalls; use open-loop arrival with long enough duration.
- Watch for thundering herds after deploy: jitter TTLs, backoff, and warm caches.

## Benchmark hygiene

- Compare only identical workloads: same CPU governor, same machine class, same build flags; avoid running other heavy processes.
- Use `-count=10` and `benchstat old.txt new.txt` for decisions; single runs are anecdotes.
- Benchmark realistic data sizes and include setup outside the timed region (`b.ResetTimer` or `b.Loop`).
- Prevent dead-code elimination with `b.Loop` (1.24+) or a package-level sink; `b.ReportAllocs` for allocations.
- Profile the benchmark (`-cpuprofile`, `-memprofile`) before optimizing; see [./06-testing.md](./06-testing.md).
- Never optimize from an unrepresentative microbenchmark alone; validate with production-like load.

## Anti-patterns

- Optimizing without a profile; "this looks slow".
- Adding caches to fix CPU instead of fixing algorithmic complexity.
- Growing goroutine/connection pools without measuring downstream saturation.
- Tuning `GOGC`/`GOMEMLIMIT` before fixing leaks and allocations.
- Using `sync.Pool` to hide unbounded allocation rates.
- Ignoring p99 because p50 looks fine; ignoring GC because CPU looks fine.
- Public pprof endpoints; profiling with `seconds=300` in production loops.
- Microbenchmarks with constant inputs the compiler can fold.

## Review checklist

- [ ] A metric and a reproduction exist before optimization claims.
- [ ] CPU/heap/block/mutex profiles (or traces) captured and compared, not guessed.
- [ ] Allocations per request/op measured; hot paths avoid `fmt` and repeated conversions.
- [ ] Heap retained (`inuse_space`) vs allocated (`alloc_space`) distinguished when chasing memory.
- [ ] GOMEMLIMIT set below container limit; GOGC justified; GC telemetry exported.
- [ ] sync.Pool used only with measured benefit and reset/cap discipline.
- [ ] Benchmarks reproducible, alloc-reporting, and regression-checked in CI.
- [ ] Latency measured with percentiles and load realistic enough to expose queueing.
