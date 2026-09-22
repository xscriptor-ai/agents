# Performance, Security, Observability

Scope: profiling tools, allocation and CPU optimization, rayon, SIMD basics, crypto and secrets hygiene, and tracing/metrics instrumentation policy.

## Performance Method

1. Define the metric and budget (p99 latency, throughput, RSS, binary size, energy).
2. Measure with a representative workload; record a baseline in version control or CI.
3. Profile to find the hotspot; fix the largest cost first.
4. Verify with the same measurement; add a regression guard (benchmark, size check).
5. Repeat. Never optimize from intuition.

| Symptom | First tool | Then |
|---|---|---|
| CPU-bound slowness | `perf record --call-graph dwarf` | `cargo-flamegraph`, `samply` |
| Allocation pressure | DHAT/heaptrack | `cargo-bloat`, massif |
| Long compile times | `cargo build --timings` | `cargo-llvm-lines` |
| Large binary | `cargo bloat` | `cargo size`, `nm --size-sort` |
| Lock contention | `perf lock`? use `samply`/`perf` with thread views | loom, redesigned ownership |
| High syscall overhead | `strace -c`, `perf trace` | buffering, batching |

- `cargo-flamegraph` (`CARGO_PROFILE_RELEASE_DEBUG=true` or the profiling profile) gives a quick live view; `samply` provides a nicer timeline and is widely used in 2026 — verify current project status upstream.
- `perf` needs symbols and frame pointers for good stacks: build with `debug = true` and prefer `--call-graph dwarf` when frame pointers are unavailable.
- DHAT (`dhat-rs`), `heaptrack`, and `bytehound` find allocation hot spots; `dhat` integrates as an allocator behind a feature flag and writes a JSON report.
- `cargo-bloat --release` ranks functions by size; `cargo-bloat --crates` splits by crate.
- For I/O-bound services, measure queue times and connection pools, not CPU.
- Profile release-like builds: optimizations change hotspots. Use a custom `profiling` profile with `debug` symbols (see `./09-tooling-build.md`).

## Allocation Reduction

- `Vec::with_capacity`, `String::with_capacity` when sizes are known; `reserve` before loop growth.
- Reuse buffers across requests (pool them) instead of allocating per request; `bytes::Bytes`/`BytesMut` for zero-copy slicing of shared buffers.
- Replace small `Vec`/`String` with `SmallVec`/`ArrayVec`/`smallstr` to avoid heap for typical sizes; measure the inline size tradeoff.
- `Cow<'_, str>` (or `Cow<'_, [T]>`) in parsing pipelines to avoid copying unchanged input.
- Write into buffers with `std::fmt::Write` (`write!(&mut String, ...)`) instead of `format!` when the destination is reused.
- Avoid `collect()` in hot paths; chain iterators or use `fold`/`for_each` with preallocated output.
- `boxed` trait objects allocate; hoist to setup, or use enums for a fixed set of variants.
- Arena allocation (`bumpalo`) for batch processing with a single lifetime; reset the arena per batch.
- Global allocator choice: `jemalloc`/`tikv-jemallocator` or `mimalloc` can help multi-threaded alloc-heavy workloads; measure RSS and latency — they are not automatic wins, especially for short-lived processes.
- `Vec::shrink_to_fit`/`into_boxed_slice` after final growth when memory is tight.
- Beware hidden allocations: `format!` in `Display` impls, `to_string()` in logs, `Path::to_path_buf`, and closures capturing owned `String`s.

```rust
let mut out = String::with_capacity(input.len() + 16);
write!(out, "{prefix}:{input}")?;
```

## CPU and Codegen

| Technique | When | Caveat |
|---|---|---|
| Iterator chains instead of indexing | loops over slices | usually enables bounds-check elision |
| `#[inline]` | tiny, cross-crate hot functions | can bloat; rely on LTO first |
| `#[inline(always)]` | proven hotspots only | hurts icache and compile time |
| `lto = "thin"`/`"fat"` | release binaries | build-time cost; fat maximizes cross-crate inlining |
| `codegen-units = 1` | release | slower builds |
| `target-cpu=native` | controlled deployment | illegal-instruction risk on heterogeneous fleets; prefer runtime dispatch |
| PGO/BOLT | high-value binaries | tooling-heavy; nightly `-Cprofile-generate` / BOLT on ELF |
| `#[cold]` and `#[inline(never)]` | error paths | keep hot path small |
| Branch hints | rarely needed | `std::hint::likely` is unstable; do not use on stable |

- Bounds checks: use `iter()`, `windows()`, `chunks()`, `split_at`, and `get` with explicit handling; keep `-C debug-assertions` off in release.
- Prefer `&[T]` parameters over `&Vec<T>` to accept more callers without conversion.
- Avoid `dyn` in inner loops; hoist dynamic dispatch to the outer layer.
- Use `#[repr(C)]`/`#[repr(align(N))]` only with a concrete reason (ABI, cache-line separation for atomics).
- `parking_lot` locks are faster than `std` and have no poisoning; measure contention before switching.

## Rayon and Data Parallelism

- `rayon` provides work-stealing `par_iter`, `join`, and `scope`; use it for CPU-bound data processing, not for I/O.
- `data.par_iter().map(f).collect::<Vec<_>>()` preserves order; `for_each`/`reduce` for unordered.
- Custom tasks: `rayon::join(|| a(), || b())` for divide-and-conquer; `scope` for borrowing local data.
- Do not block worker threads on I/O or locks; rayon's pool is sized to CPUs. Blocking a rayon thread stalls the whole pool.
- Nested parallelism with tokio: never call rayon inside async on every item; either `spawn_blocking` a rayon batch, or use `tokio::task::spawn_blocking` per batch, or bridge with `pollster`/`block_in_place` deliberately.
- Global pool configuration: `rayon::ThreadPoolBuilder::new().num_threads(n)`; build a dedicated pool when the library must not hijack the global one.
- False sharing: pad per-thread accumulators (`CachePadded` from crossbeam) for high-contention counters.
- Determinism: reduce with an associative operation; avoid floating-point nondeterminism when a stable result is required.

```rust
use rayon::prelude::*;
let sum: u64 = data.par_chunks(4096).map(|c| c.iter().map(|&x| x as u64).sum::<u64>()).sum();
```

## SIMD Basics

- Start with autovectorization: contiguous slices, simple loops, no data-dependent branches per element, and `-C target-feature` or `target-cpu` where safe.
- `std::simd` (portable SIMD) remains nightly-only in practice; do not put it in a stable crate without a gate. Verify upstream.
- Stable options: `std::arch` intrinsics behind `#[target_feature(enable = "avx2")] unsafe fn`, plus runtime detection with `is_x86_feature_detected!`/`is_aarch64_feature_detected!`.
- Cross-platform wrappers: `wide` (portable SIMD types) and `multiversion` (compiles feature-specialized versions and dispatches at runtime).
- Keep SIMD kernels isolated in a module with scalar fallbacks, tests comparing scalar vs SIMD outputs, and Miri-friendly scalar paths (Miri does not support many intrinsics).
- Alignment: unaligned loads (`loadu`) are fine on modern x86 but cost on some ARM; align when easy.
- Crypto and compression libraries already ship tuned SIMD; use them rather than hand-rolling.
- Measure with `perf stat` (IPC, cache misses) and check that vectorization actually happened (`cargo asm`, `llvm-mca`).

## Crypto and Secrets

| Need | Recommended | Notes |
|---|---|---|
| TLS | `rustls` (+ `aws-lc-rs` or `ring` provider) | pure-Rust, no OpenSSL linkage; `native-tls` when OS trust store integration is required |
| Symmetric AEAD | `aes-gcm`, `chacha20poly1305` (RustCrypto) | use well-reviewed, actively maintained crates; verify audit status upstream |
| Hashing | `sha2`, `blake3` | `blake3` for speed, `sha2` for compatibility |
| Password hashing | `argon2`, `password-hash` | Argon2id; store parameters with the hash |
| KDF | `hkdf`, `pbkdf2` | derive distinct keys per purpose |
| Randomness | `getrandom` (OS CSPRNG), `rand` for non-crypto | never seed crypto from `rand::thread_rng` state you control; use `OsRng` |
| Constant-time compare | `subtle` | never compare secrets with `==` |
| Secret storage | `secrecy`, `zeroize` | `SecretString`, zeroize on drop, avoid `Debug` leakage |
| JWT | `jsonwebtoken` | validate alg/aud/iss explicitly (see `./06-web-data.md`) |

- Do not roll your own crypto, padding, or protocol; compose audited primitives.
- RustCrypto crates are widely used but many carry "no formal audit" disclaimers; check the current audit status of each crate before high-assurance use and verify upstream.
- Constant-time behavior is not guaranteed by the type system: `subtle::ConstantTimeEq`, avoid branching on secrets, avoid secret-dependent indexing (table lookups), and avoid secrets in error messages/timing.
- Use `zeroize`/`Zeroizing` for keys and passwords; note that Rust may copy values — zeroize best-effort and do not rely on it for safety guarantees.
- Secrets in process: environment variables are visible in `/proc` for the same user and in crash dumps; prefer a secret manager fetched at startup, or workload identity. Never bake into images.
- Logging policy: never log tokens, keys, passwords, or PII; run a lint/review check for `Debug` on types containing secrets (derive a redacting `Debug` manually).
- Dependencies: pin crypto crates tightly, vendor or lock, and track advisories (see `./09-tooling-build.md`).
- Platform RNG failures: handle `getrandom` errors (early boot, restricted sandboxes) by failing closed, not by falling back to weak randomness.

## Observability with tracing

- `tracing` replaces `log` for structured, async-aware diagnostics; `tracing-subscriber` is the runtime side.
- Create spans at request/job boundaries: `#[instrument(skip(state), fields(user_id = %id))]`; keep span fields high-cardinality limited (ids are fine; unbounded values are not).
- Events carry the detail: `info!`, `debug!`, `warn!`, `error!` with structured fields (`error = ?err`, `latency_ms = elapsed.as_millis()`), not string interpolation.
- Subscriber stack: `registry().with(EnvFilter::from_default_env()).with(fmt::layer().json())`; add `console-subscriber` in dev for task stalls.
- Log levels: `error` = page-worthy; `warn` = degraded; `info` = lifecycle; `debug`/`trace` = development. Never ship `trace` in production defaults.
- JSON logging in production, pretty in development; include service name, version, trace/span ids.
- OpenTelemetry: `tracing-opentelemetry` + OTLP exporter; propagate context through HTTP/gRPC with `opentelemetry` propagators. Sample at the collector when possible; head sampling in-process for cost control.
- Avoid per-request `format!` in hot paths; `tracing` is cheap when the level is disabled, but field formatting still costs when enabled.
- Libraries depend on `tracing` (or `log` with a feature) and emit spans; applications configure filtering and exporters. Never install a global subscriber in a library.
- Flush telemetry on shutdown: `subscriber` guards + `opentelemetry::global::shutdown_tracer_provider` (verify current API).
- Correlation: inject/propagate `traceparent` (W3C) through clients and servers; include request id in error responses without leaking internals.

## Metrics

- Use the `metrics` facade plus an exporter (`metrics-exporter-prometheus`) or the OpenTelemetry metrics API; keep metric names stable, and use units in the name (`http_request_duration_seconds`).
- Counters for totals, gauges for current values, histograms for latency/size; avoid high-cardinality labels (user ids) on histograms.
- RED (rate, errors, duration) for services; USE (utilization, saturation, errors) for resources.
- Export scrape-friendly endpoints on a separate port or internal router, not the public listener.
- Instrument queues with depth and age; queued age is the leading indicator of overload.
- Define SLOs and alert on symptoms (latency, error rate), not causes (CPU).

## Checklist

- [ ] A release-like build is profiled before optimizing; baseline recorded.
- [ ] Perf budget (latency/throughput/memory/size) exists and regressions are caught.
- [ ] Allocations in hot paths measured; buffers reused; hidden `format!`/`to_string()` removed.
- [ ] Rayon used only for CPU work; no blocking of its pool; no nested oversubscription with tokio.
- [ ] SIMD kernels have scalar fallbacks, dispatch, and equivalence tests; Miri path exists.
- [ ] TLS, hashing, password hashing, and RNG come from maintained crates with tracked advisories.
- [ ] Secrets never logged, zeroized where practical, delivered by a secret manager.
- [ ] Tracing spans at boundaries; metrics for RED/USE; logs structured with levels.
- [ ] Telemetry flushed on graceful shutdown; no global subscriber installed by libraries.
