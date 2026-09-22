# Profiling

Scope: continuous profiling, CPU/heap/goroutine profiles, pprof, eBPF-based profilers, and correlating profiles with traces.

## Why Continuous Profiling

- Metrics tell you something is slow; traces tell you which service and span; profiles tell you which function, line, and allocation. Profiles are the code-level layer of observability.
- Continuous profiling samples production at low overhead (typically low single-digit percent CPU with sane settings) and aggregates over time, replacing ad-hoc "SSH and run perf" sessions.
- Profiles are aggregated by labels (service, version, host, region, and ideally span or trace) into flame graphs. Aggregation across time makes small costs visible and attributable.
- Use continuous profiling when you need to answer: what consumes CPU after a deploy, what allocates, what leaks, what blocks, and which thread/goroutine holds resources.

## Profile Types

| Profile | Measures | Question it answers | Typical signal |
|---|---|---|---|
| CPU (on-CPU) | Sampled stack traces of running code | Where is CPU time spent? | `process_cpu` / wall-clock samples |
| Wall clock | Stacks by elapsed time including waits | Where is latency spent? | Blocking, I/O waits, scheduler |
| Allocation | Bytes and objects allocated | What allocates and churns? | GC pressure, hot allocations |
| Heap (in-use) | Live objects at snapshot | What holds memory? | Leaks, growth over time |
| Goroutine/threads | Count and stacks of live goroutines/threads | Why are threads piling up? | Leaks, blocked workers |
| Block/mutex | Blocked and contended time | What serializes work? | Lock contention, pool exhaustion |
| Off-CPU | Stacks while not running | Where does time go while idle? | I/O, locks, page faults |
| Lock/contention | Per-lock wait profiles | Which lock hurts? | Contended hot locks |

- On-CPU profiles miss everything waiting. If latency grows while CPU is flat, look at wall-clock or off-CPU profiles.
- Allocation and heap profiles answer different questions: allocation finds the churn, heap finds the retention. Use both for memory incidents.
- Goroutine/thread leaks look like slow memory growth with steady CPU; profile goroutine counts over time, not a single snapshot.
- Sampling profilers assume some regularity; very short-lived processes and functions may be underrepresented. Correlate with traces and metrics before concluding.

## Formats and Tooling

| Tool | Profiles | Notes |
|---|---|---|
| `pprof` | CPU, heap, goroutine, block, mutex, threadcreate | Ubiquitous Go; also consumed by many profilers |
| Linux `perf` | CPU, off-CPU, call graphs | System-wide to container-level; needs symbols |
| `async-profiler` / JFR | CPU, allocation, lock, wall | JVM standard in production |
| `py-spy` | CPU, wall, native stacks | Python without code changes |
| `dotnet-trace` / `dotnet-gcdump` | CPU, GC, allocations | .NET production profiling |
| `--cpu-prof` / `--heap-prof` (Node) | CPU, heap | Built into the runtime; snapshots |
| Pyroscope, Parca, Polar Signals, Coroot | Continuous, aggregated | Server components plus language agents |
| Cloud APM profilers | Continuous, vendor-hosted | Convenient, less portable; watch cost and egress |

- The pprof wire format is the lingua franca: language agents, eBPF agents, and backends move pprof over HTTP for ingestion and query. OTLP profiles exist as a signal but are stabilizing — verify upstream support.
- Keep the profiling agent's ingestion path separate from the request path; a blocked profiler upload must never add latency to the application.
- Symbols matter: build with debug info or a symbol server and keep a mapping from build ID to symbols. Profiles without symbols are just stack addresses.
- Frame pointers or DWARF unwinding: some runtimes and eBPF profilers assume frame pointers for clean stacks. Decide the build flag per language and test unwinding in staging.

## eBPF-Based Profiling

- eBPF profilers sample stacks in the kernel without linking a language agent, which covers any runtime, including legacy binaries and services you cannot redeploy.
- Typical coverage: on-CPU stacks, off-CPU and I/O waits, some allocation/network signals, and language-aware unwinding for common runtimes.
- Constraints: kernel version and build flags, container privilege model (CAP_BPF or privileged), symbol availability, stripped binaries, and JIT runtimes (JVM, Node, .NET) needing per-runtime unwinders. Verify support upstream for your exact versions.
- Security review: eBPF agents see process memory and syscalls. Run with least privilege, restrict the agent's load surface, and treat the profiling data as sensitive (function names, file paths, sometimes string arguments).
- In clusters, run one profiling agent per node (DaemonSet) and aggregate centrally; per-pod sidecars are usually not worth the overhead.

## Correlating Profiles With Traces

| Level | Mechanism | Precision |
|---|---|---|
| Service + time window | Labels shared by all signals | Coarse; good for regressions |
| Version/deploy | `service.version` on profiles | Attributes a regression to a release |
| Span | Span ID attached to samples during a span | Pinpoints the span that was slow |
| Trace | Trace ID on samples | Reconstructs the full request cost |
| Function | Stack labels plus trace attributes | Direct code-to-request link |

- Span profiles (sampling labels while a span is active) connect a slow trace to the exact stack consuming its time. This is the highest-value correlation; verify what your profiler supports upstream.
- Grafana-style "profiles for this service" drilldown from a trace depends on shared `service.name` and time ranges. Ensure clock sync (NTP) across nodes or correlation windows will be off.
- When a latency alert fires, the workflow is: exemplar or trace to find the slow request, then span profile or service profile to find the function, then a fix. Without correlation, profiling becomes guesswork.
- Keep profiling labels low-cardinality except span/trace IDs, which are intentionally high-cardinality but short-lived. Retention for trace-correlated samples can be shorter than for aggregate profiles.

## Workflow

1. Establish the question and the profile type: CPU, allocation, heap, locks, goroutines, or off-CPU.
2. Capture a baseline before the change, ideally at the same load level and time of day.
3. Collect with symbols, correct labels, and enough duration to cover the workload cycle (at least several minutes; hours for leaks).
4. Read top-down for call hierarchy and bottom-up for self-time. Ignore functions that are cheap; fix the widest bar.
5. Check for measurement artifacts: sampling bias, missing symbols, one host dominating the aggregate, or a single outlier trace.
6. Fix, redeploy, recapture, and compare the same view. Record the before/after in the change description.
7. Guard with a benchmark or budget where possible; continuous profiling then serves as the regression detector.

## Overhead and Safety

- Sampling frequency is the main overhead knob. Defaults are usually sane; raising frequency for a short investigation is fine, keeping it raised forever is not.
- Heap profiles can stop the world or force a GC depending on the runtime and options; do not run them continuously at full fidelity in latency-sensitive services.
- Profiling endpoints (`/debug/pprof`, JMX, runtime diagnostics) expose code paths, memory, and sometimes secrets. Bind them to localhost or an internal port, require auth, and never expose them publicly.
- Profiling agents add CPU, memory, and network egress. Budget them like telemetry: measure the agent's own cost and cap upload rate.
- PII risk: stack traces include file paths and function names; some profilers capture string arguments or allocation call sites. Treat profile data under the same privacy policy as logs.
- Test the profiler in staging after kernel, runtime, and orchestrator upgrades; unwinding and privilege models are the usual breakage points.

## Reading a Flame Graph

- Width is cost or time, not call order. A wide frame is expensive; a tall stack is deep, not necessarily slow.
- Top-down view: follow the widest branch from the root to understand which subsystem dominates. Bottom-up view: sort by self-time to find the function that actually burns the samples.
- Self-time versus total time: wrapper and dispatcher frames look expensive in total time but cheap in self-time. Optimize self-time first.
- Look for known landmarks: JSON/marshal, regex compilation, lock waits, GC, syscalls, and allocation paths. Recurring shapes across services usually mean shared library costs.
- Compare, do not eyeball: side-by-side before/after or version-over-version flame graphs make regressions obvious. A single graph in isolation rarely proves anything.
- Watch for sampling artifacts: a new function appearing only at the top of a broken stack, missing frames from inlined code, or one host dominating the aggregate.
- Inverted and differential views: inverted flame graphs (icicle) are easier for deep stacks; differential graphs color added versus removed cost per frame.

## Profile Storage and Labels

| Label | Purpose | Cardinality |
|---|---|---|
| `service.name` | Primary grouping | Low |
| `service.version` | Regression attribution | Medium; churns per deploy |
| `deployment.environment.name` | Environment split | Low |
| `k8s.pod.name` / `host.name` | Instance comparison | High but bounded by fleet size |
| `region`, `zone` | Locality comparison | Low |
| `span_id`, `trace_id` | Request correlation | Very high; short retention |

- Keep label sets identical to traces and metrics so all three overlay in one UI (`./01-opentelemetry.md`). Drift makes correlation impossible.
- High-cardinality labels (pod, span) are useful for spot checks but expensive for long retention. Aggregate profiles by service and version for the long term; keep per-instance and per-span data short.
- Storage format: pprof over HTTP is the common ingest and query format; some backends store columnar representations for large-scale aggregation. Verify the query and ingest formats your backend supports upstream.
- Query language is usually label selector plus profile type plus time range, with optional function filters. Learn the top queries: top functions by self-time, cost by version, and compare two windows.
- Access control: profiles reveal internal structure. Restrict who can query per-environment data and audit exports.

## Language Notes

| Runtime | Practical profiler | Notes |
|---|---|---|
| Go | `net/http/pprof`, `runtime/pprof` | CPU, heap, goroutine, block, mutex; sample rate configurable; goroutine profiles are cheap and excellent for leaks |
| JVM | async-profiler, JFR | Wall-clock and allocation modes are the differentiators; JFR is built in and low overhead |
| Python | `py-spy`, OTel profiling agents | GIL means wall-clock and native stacks matter; pure-Python CPU profiles can mislead |
| Node.js | `--cpu-prof`, inspector, profiling agents | Event-loop lag metrics pair well with profiles; async stacks need runtime cooperation |
| .NET | `dotnet-trace`, `dotnet-gcdump` | GC and allocation profiles are first-class; EventPipe is the mechanism |
| Native (C/C++/Rust) | `perf`, eBPF agents | Symbols and frame pointers dominate profile quality; stripped release builds need a symbol store |

- Always check whether the profile is CPU-time or wall-clock. For I/O-bound and lock-bound services, CPU profiles systematically understate the problem.
- For managed runtimes, separate GC time from application time; a "CPU" profile that is mostly collector work points at allocation reduction, not algorithm changes.
- Keep profiler sampling rates sane in production; investigate with higher rates only for short windows.

## Anti-Patterns

- Profiling only in development, where load and data shape rarely match production.
- Chasing the widest bar without checking self-time; a wrapper function is not a hotspot.
- Comparing profiles from different build types (debug vs release) or different optimization flags.
- Leaving pprof endpoints publicly reachable.
- Treating a single heap snapshot as a leak proof; leaks are a trend over time.
- Ignoring GC pauses and off-CPU time because the CPU profile looks clean.
- Running full-fidelity heap profiling continuously in a p99-sensitive service.
- Profiling without symbols and then concluding "the profile is useless".

## Checklist

- [ ] Continuous profiling runs in production with documented overhead and an owner.
- [ ] Build artifacts carry symbols or a symbol mapping; build IDs recorded.
- [ ] Profile types selected per question (CPU, allocation, heap, goroutine, locks, off-CPU).
- [ ] Service, version, and environment labels consistent with traces and metrics.
- [ ] Span or trace correlation enabled where supported and verified in staging.
- [ ] Profiling endpoints private, authenticated, and off the public listener.
- [ ] Retention and egress budget defined for profile data.
- [ ] Regression workflow: baseline, fix, recapture, compare, guard.
- [ ] eBPF agent privilege and kernel/runtime compatibility reviewed on upgrades.
