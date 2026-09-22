# Backend Profiling

Scope: CPU and memory profiling, flamegraph reading, continuous profiling, eBPF, lock contention, and tracing slow paths in backend services.

## Choosing the Signal

| Question | Signal | Cost |
|---|---|---|
| Which endpoint or dependency is slow? | Traces, latency histograms | Low |
| Which function burns CPU? | On-CPU profile | Low with sampling |
| Why is latency high while CPU is low? | Off-CPU or wall-clock profile, traces | Low to moderate |
| What allocates and drives GC? | Allocation profile | Moderate |
| What retains memory? | Heap profile or snapshot | Moderate to high |
| What serializes work? | Block/mutex/lock profiles, thread dumps | Low |
| Did this version regress? | Continuous profile diff by version | Low |

- Profiles explain code-level cost; traces explain request-level cost; metrics explain resource-level cost. Use all three together. Cross-pack: the sibling observability pack covers telemetry plumbing and SLO alerting.
- If the CPU profile shows the runtime mostly idle, stop profiling CPU and look at waits, queues, and downstream latency instead.

## Profiling Workflow

1. State the question: CPU, allocation, retention, lock, or off-CPU latency.
2. Establish a baseline from the same build type and load level; debug builds and seed data produce misleading profiles.
3. Pick the least invasive method that answers the question: continuous profiler for production, snapshot profiler for staging, system profiler for native issues.
4. Capture with symbols and useful labels (service, version, environment, and span when available).
5. Read top-down for the call path and bottom-up for self-time; ignore cheap frames.
6. Validate against an independent signal (metric, trace, or benchmark) before concluding.
7. Fix one hot path, redeploy, recapture the identical view, and compare.
8. Guard with a benchmark or budget so the regression cannot return silently.

## CPU Profiling

- Sampling profilers interrupt at a fixed frequency and aggregate stacks; they have low overhead and are the default for production. Instrumentation profilers count every call and distort hot loops; use them for call counts, not timing.
- Sampling frequency trades overhead for detail. Raise it briefly for an investigation; leave production at defaults.
- Symbols and unwinding decide profile quality. Build with debug info or publish symbol mappings keyed by build ID. Inlined and optimized frames are approximate.
- CPU time and wall-clock time are different profiles. CPU profiles omit blocked threads; a service waiting on a lock or network shows low CPU and high wall time.
- Container note: profile inside the container's namespaces so host noise does not contaminate results, and account for CPU limits and throttling in the labels.

## Reading Flamegraphs

- Width is cost or time in the aggregate, not call order. A wide frame is expensive; a deep stack can be cheap.
- Top-down view: follow the widest branch from the root to find the dominant subsystem. Bottom-up view: sort by self-time to find the function actually burning samples.
- Self-time versus total time: dispatchers, frameworks, and middleware look expensive in total time and cheap in self-time. Optimize self-time first, then reconsider architecture.
- Look for landmarks: serialization (JSON encode/decode), regex compilation, TLS handshakes, syscalls, allocator paths, collector/GC frames, lock waits, and retry loops.
- Inverted (icicle) graphs read better for deep stacks; differential graphs color added versus removed cost between two captures.
- Compare version to version or before to after; a single graph proves very little. A new frame at the top of a broken stack usually means missing symbols, not a new hotspot.
- Aggregate across hosts but watch for one host dominating; check per-host profiles before drawing fleet-wide conclusions.

## Memory Profiling

- Allocation profiles find churn (what allocates the most bytes/objects), heap profiles find retention (what is still live). GC pressure and leaks require both.
- Analyze allocation rates, not just totals: high allocation rate with short lifetimes causes CPU-heavy collection even without a leak.
- Heap snapshots: capture, then diff two snapshots taken minutes apart under steady traffic. Sort by delta and then find the dominant retainer path of the biggest growth.
- Common retainers: unbounded maps and caches, request-scoped data captured in long-lived closures, event listeners never removed, thread-locals, connection pools holding large buffers, and static registries.
- Managed runtimes can force a GC before a heap snapshot for a cleaner reading; expect a pause, and avoid doing it in latency-critical production windows.
- Correlate memory profiles with runtime GC metrics and container memory to distinguish leak from working-set growth from fragmentation.

## Continuous Profiling

- Sample production continuously at low overhead (typically low single-digit percent CPU with sane settings) and aggregate over time; this turns "SSH and profile" into a query.
- Labels make profiles useful: `service.name`, `service.version`, `deployment.environment.name`, host or pod, and ideally `span_id` during span-correlated sampling.
- Version labels attribute regressions directly: compare the profile of the new version against the previous release.
- Span profiles attach sampled stacks to active traces and pinpoints which span consumed the time; verify upstream support for your profiler and SDK versions.
- Keep label cardinality controlled for long retention; per-span samples are high-cardinality and should be short-lived.
- Budget the agent: measure its own CPU, memory, and egress, and keep ingestion off the request path.

## eBPF Profiling

- eBPF profiles sample stacks in the kernel without linking a language agent, covering every process on a node including legacy binaries and JIT runtimes.
- Typical coverage: on-CPU stacks, off-CPU and I/O waits, scheduler delays, and some allocation and network signals. Language-aware unwinding exists for major runtimes but quality varies.
- Constraints: kernel version and build flags, container privilege model (`CAP_BPF` or privileged), available symbols, stripped binaries, and JIT runtimes that need runtime-specific unwinders. Verify the matrix upstream for your kernel and runtime versions.
- Security: eBPF agents observe process memory and syscalls. Run with least privilege, restrict the loaded programs, and treat profile data as sensitive.
- Cluster deployment: one agent per node (DaemonSet) exporting to a central backend is the common shape; per-pod sidecars rarely justify the overhead.
- Use eBPF when you need coverage without redeploying or when per-language agents conflict; use language agents when you need allocation and runtime-internal detail.

## Syscall and I/O Visibility

- System-level views answer what language profilers cannot: syscall mix, socket and file waits, page faults, and scheduler delay.
- `strace -c -f` summarizes syscalls; per-call latency modes show tail waits. Trace for short windows only; tracing itself is expensive.
- `perf stat` reports cycles, instructions, cache misses, and context switches, which distinguish CPU-bound from stalled.
- `iostat` and `/proc/pressure/io` expose disk saturation; `ss` exposes socket queue and retransmit behavior.
- cgroup metrics (`cpu.stat`, `memory.events`, PSI files) reveal throttling and pressure that in-process profilers never see.
- Correlate I/O waits with traces: a slow span usually ends at a socket, disk, or lock rather than in application code.
- CPU throttling looks like latency spikes with CPU "not busy"; check throttled periods before blaming the code.

## Lock Contention

| Tool / signal | Runtime | Reveals |
|---|---|---|
| Mutex / block profiles | Go | Time blocked on mutexes and channels |
| `perf lock` / off-CPU analysis | Native, any | Kernel lock waits and scheduler delay |
| JFR lock events, thread dumps | JVM | Monitor contention, deadlocks, thread states |
| Thread dump stacks | Any | Who waits on what; repeated dumps show stalling |
| `strace -c -f` | Any | Syscall mix and time, futex waits |
| Tracing around the critical section | Any | Time inside versus outside the lock |

- Lock contention signature: latency grows with concurrency while CPU stays partial; throughput plateaus and then degrades.
- Find the lock: block/mutex profiles, lock-wait traces, or repeated thread dumps showing many threads parked on the same object.
- Shrink critical sections: move I/O, serialization, and callbacks outside the lock; compute under the lock only what must be atomic.
- Reduce lock scope with per-shard or striped locks, read-write locks for read-dominated data, or copy-on-write snapshots for readers.
- Immutable data and message passing remove locks structurally and are usually more maintainable than clever lock-free code. Use lock-free structures only with evidence and careful review.
- Watch coarse locks hidden in libraries: global buffers, connection acquisition, logging appenders, metrics registries, and lazy initialization.

## Tracing Slow Paths

- Distributed traces show where a request spent time across services; use them to localize before profiling. Span granularity is a design choice: instrument database calls, HTTP clients, queue publishes, and expensive local steps.
- The critical path is what matters; parallel sibling spans mean total time is the max, not the sum.
- Async and fire-and-forget work needs links or explicit child spans, or the trace will hide the real queueing.
- Exemplars connect histogram buckets to concrete traces, so a p99 latency alert can open the exact slow request.
- Fan-out amplifies tails: a request calling 20 services inherits the slowest of 20 tails. Reduce fan-out, hedge deliberately, or cache aggressively. See `./06-concurrency-backpressure.md` and `./02-caching.md`.
- Sample smartly: keep all errors and slow requests, sample the rest. Cross-pack: the observability pack covers sampling strategy and collector configuration.

## Tooling by Runtime

| Runtime | CPU | Memory / heap | Locks / off-CPU |
|---|---|---|---|
| Go | `pprof` CPU, continuous agents | heap, allocs profiles | block, mutex profiles |
| JVM | async-profiler, JFR | JFR allocation, heap dumps | JFR monitor events, thread dumps |
| Python | `py-spy`, sampling agents | `tracemalloc`, `memray` | `py-spy` wall mode, `faulthandler` |
| Node.js | `--cpu-prof`, inspector | `--heap-prof`, heap snapshots | async hooks, `--prof`, event-loop lag |
| .NET | `dotnet-trace`, EventPipe | `dotnet-gcdump`, `dotnet-counters` | `dotnet-dump`, contention events |
| Native / Rust | `perf`, eBPF | `valgrind`, heaptrack, jemalloc stats | `perf lock`, off-CPU profiling |
| Any (kernel) | eBPF profilers | eBPF allocation probes | off-CPU eBPF |

- Check whether a profile is CPU-time or wall-clock before interpreting it; I/O-bound services look innocent under CPU profiles.
- For managed runtimes, separate GC time from application time. A CPU profile dominated by collector work points to allocation reduction, not algorithm changes. See `./07-memory-gc.md`.

## Overhead and Safety

- Profiling endpoints (`/debug/pprof`, JMX, inspector sockets, diagnostics ports) expose internals. Bind them to localhost or an internal interface, require authentication, and never expose them publicly.
- Sampling agents add CPU, memory, and egress; budget them like telemetry and measure their cost.
- Heap snapshots and forced GCs pause the process; schedule them outside peak windows or in staging.
- Stack data can contain PII: file paths, function names, and sometimes captured strings. Treat profiles under the same privacy policy as logs.
- Test profilers after runtime, kernel, and orchestrator upgrades; unwinding and privilege changes are the usual breakage points.

## Anti-Patterns

- Profiling only in development with debug builds and toy data.
- Chasing the widest bar without checking self-time; wrappers are not hotspots.
- Comparing profiles from different builds, flags, or environments.
- Leaving pprof or diagnostics endpoints publicly reachable.
- Treating a single heap snapshot as leak proof; leaks are trends.
- Ignoring off-CPU time because the CPU profile looks clean.
- Running full-fidelity heap profiling continuously on p99-sensitive services.
- Concluding "the profile is useless" because symbols were missing.
- Fixing micro-hotspots before checking the database, lock, or downstream waits that dominate wall-clock time.

## Checklist

- [ ] The question determined the profile type: CPU, wall/off-CPU, allocation, heap, lock, or goroutine/thread.
- [ ] Baseline captured on a production-like build and data shape.
- [ ] Symbols or a symbol mapping exist and build IDs are recorded.
- [ ] Flamegraphs read both top-down and bottom-up; self-time verified before optimizing.
- [ ] Continuous profiling runs in production with documented overhead and owner.
- [ ] Labels consistent with traces and metrics; span correlation verified where supported.
- [ ] eBPF agent privilege and kernel/runtime compatibility reviewed on upgrades.
- [ ] Lock contention checked when latency grows with concurrency and CPU stays low.
- [ ] Profiling endpoints private and authenticated; profile data treated as sensitive.
- [ ] Before/after profile comparison recorded with the fix.
