---
name: senior-rust
description: 'Rust reference pack (editions 2021/2024, 2026 stable toolchains): ownership
  and lifetimes, traits and generics, async/tokio and structured concurrency, error
  handling, unsafe/FFI, axum and the data layer, embedded no_std, testing, build tooling,
  performance, security, and observability. Use when writing, reviewing, debugging,
  or architecting non-trivial Rust: borrow-checker fights, async cancellation, unsound
  or unaudited unsafe, C/pyo3/wasm interop, web services with axum or actix, sqlx/diesel
  schemas and migrations, cargo workspaces and feature flags, cross-compilation and
  supply chain, profiling and benchmarking, or firmware on embedded-hal and embassy.'
---

# Rust

Reference pack for senior Rust work: language core, type system, async, errors, unsafe/FFI, web/data, embedded, testing, build, and performance/security/observability. Depth lives in `references/`; this file is the map.

## Baseline (2026)

- Editions 2021 and 2024 are the supported targets; new crates should start on edition 2024 unless a dependency forces otherwise. Verify upstream for exact toolchain behavior.
- Useful floors: async fn in traits / RPITIT (1.75+), async closures and edition 2024 (1.85+), `LazyLock` (1.80+), `pin!` (1.68+), workspace lints (1.74+), `&raw` pointers (1.82+), MSRV-aware resolver v3 with edition 2024.
- Pin the toolchain in `rust-toolchain.toml`, declare `rust-version`, and test the MSRV in CI.
- The ecosystem moves; every version range in this pack is a floor or "verify upstream", never a promise.

## Non-Negotiable Core Rules

1. No `unwrap()`/`expect()` on external input or I/O in production paths. Libraries expose typed errors; applications use `anyhow` internally and convert at boundaries. See `./references/04-error-handling.md`.
2. Every `unsafe` block has a `// SAFETY:` invariant, a safe wrapper, and Miri coverage. Never `unsafe` to appease the borrow checker. See `./references/05-unsafe-ffi.md`.
3. No blocking calls or held lock guards across `.await`. Cancellation of every `select!`/`timeout` branch is understood and documented. See `./references/03-async-concurrency.md`.
4. Every spawned task has an owner, a join path, and error handling; shutdown is token-driven and drains with a deadline.
5. Cargo features are additive; mutually exclusive features are a design bug. Public APIs never expose `anyhow::Error`.
6. Measurements precede optimization: profile a release-like build, record a baseline, guard with benchmarks.
7. CI runs `cargo fmt --check`, `cargo clippy --all-targets --all-features -D warnings`, tests, and dependency/license/advisory checks; releases build `--locked`.
8. Secrets are never logged, never committed, and never embedded in `Debug` output; TLS/crypto/RNG come from maintained crates with tracked advisories.

## Decision Tables

### Error Type by Position

| Position | Use | Do not use |
|---|---|---|
| Public library API | `thiserror` enum / hand-written `Error` | `anyhow`, `String` |
| Binary internals | `anyhow::Result` + `.context()` | custom enum per function |
| Boundary conversion | `From`/`map_err` preserving source | `map_err(|_| …)` |
| Erased trait object boundary | `Box<dyn Error + Send + Sync>` | generic error params everywhere |

### Async Concurrency Primitive

| Need | Primitive |
|---|---|
| Background work with result | `JoinSet` / spawned task with owned handle |
| Request/response between tasks | `oneshot` |
| Ordered work queue with backpressure | bounded `mpsc` |
| Latest state broadcast | `watch` |
| Every event to every subscriber | `broadcast` (handle lag explicitly) |
| Concurrency limit | `Semaphore`, `tower` concurrency layer |
| Cancellation/shutdown | `CancellationToken` + `TaskTracker` |

### Unsafe Justification

| Situation | Verdict |
|---|---|
| FFI to C/pyo3/wasm | justified; isolate and document |
| Performance-proven hot loop | justified with benchmark and scalar fallback |
| Defeating the borrow checker | redesign; use interior mutability or ownership transfer |
| "Compiler is annoying" | never |
| Crypto/SIMD intrinsics | use vetted crates or `std::arch` with runtime dispatch |

### Web and Data Defaults

| Choice | Default | Switch when |
|---|---|---|
| HTTP framework | axum (tower/hyper ecosystem) | team/legacy is actix-web |
| Database | sqlx (compile-time checked SQL) | entity modeling -> sea-orm; typed query builder -> diesel + diesel-async |
| Config | typed struct + figment/config layered env | single source -> plain env |
| Auth | middleware authenticates, services authorize | gateway terminates auth |

## Reference Index

| File | Scope | Load when |
|---|---|---|
| `./references/01-language-core.md` | Ownership/borrowing/lifetime model, smart pointers, enums, pattern matching, closures, iterators, borrow-checker fixes | Any ownership or lifetime error; choosing `Rc`/`Arc`/`RefCell`/locks; designing data flow |
| `./references/02-type-system-traits.md` | Traits, associated types, generics vs `dyn`, blanket impls, marker traits, newtypes, conversions, operator traits, `Error` integration | Designing APIs/traits, resolving coherence/object-safety issues, adding conversions |
| `./references/03-async-concurrency.md` | Tokio runtime tuning, tasks, cancellation safety, structured concurrency, channels, `select!`, backpressure, `Send`/`Sync`, async traits | Writing async code, debugging hangs/stalls, cancellation or shutdown work, async trait design |
| `./references/04-error-handling.md` | `Result`/`Option` idioms, thiserror vs anyhow, context chains, panic policy, `unwrap` discipline, boundary conversion | Defining errors, mapping HTTP/DB/task errors, eliminating panics or unwraps |
| `./references/05-unsafe-ffi.md` | Soundness rules, raw pointers/provenance, `Pin`, safe abstractions, Miri, C ABI/bindgen, pyo3/wasm-bindgen, unsafe audit | Writing/reviewing unsafe, FFI or interop, pinned/self-referential types, Miri CI |
| `./references/06-web-data.md` | axum vs actix, tower middleware, serde, sqlx/diesel/sea-orm, migrations, config, auth, graceful shutdown | Building or reviewing HTTP services, DB schemas/queries/migrations, config and auth |
| `./references/07-embedded.md` | `no_std`, embedded-hal, embassy async, defmt/probe-rs, memory budgets, target config | Firmware, HAL drivers, bare-metal targets, embedded CI and debugging |
| `./references/08-testing.md` | Unit/integration/doc tests, proptest, criterion, cargo-nextest, Miri, loom, snapshots, fuzzing, coverage, mocks | Adding test infrastructure, flaky/racy bugs, unsafe test strategy, benchmark setup |
| `./references/09-tooling-build.md` | Workspaces, feature flags/unification, profiles, task runners, rustfmt/clippy, cross-compilation, MSRV, release and supply chain | Setting up or fixing builds, features, CI, cross targets, publishing, dependency policy |
| `./references/10-performance-security-observability.md` | Profiling, allocation reduction, rayon, SIMD, crypto/secrets, tracing, metrics | Optimizing hot paths, memory/latency budgets, adding instrumentation or hardening |

## Load Order

- Language or design question: start at `./references/01-language-core.md` or `./references/02-type-system-traits.md`.
- Async service work: `./references/03-async-concurrency.md` then `./references/06-web-data.md`.
- Correctness/robustness pass: `./references/04-error-handling.md` then `./references/08-testing.md`.
- Native interop or firmware: `./references/05-unsafe-ffi.md` or `./references/07-embedded.md`.
- Root-causing build/CI or perf: `./references/09-tooling-build.md` then `./references/10-performance-security-observability.md`.
- Load only what the task needs; do not inject the whole pack into context.

## Review Workflow

For a non-trivial Rust change, this is the default pass order:

1. Model the data and ownership first; most "Rust is hard" issues are design issues (see `./references/01-language-core.md`).
2. Define errors and boundaries before implementation (`./references/04-error-handling.md`, `./references/02-type-system-traits.md`).
3. Decide sync vs async and the concurrency primitives (`./references/03-async-concurrency.md`).
4. Keep unsafe/FFI isolated and covered by Miri (`./references/05-unsafe-ffi.md`).
5. Wire the framework/data layer with explicit timeouts and shutdown (`./references/06-web-data.md`).
6. Add tests at the same time as the code (`./references/08-testing.md`).
7. Run fmt, clippy, tests, and dependency checks before review (`./references/09-tooling-build.md`).
8. Instrument from day one and profile before optimizing (`./references/10-performance-security-observability.md`).

## Port

- **Port id** — `skill://senior/rust` (version in `metadata.port-version`, currently `2.0.0`).
- **Kind** — read-only reference pack; no side effects, no tools required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "rust" })` in OpenCode; Claude Code reads `<skills-dir>/rust/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers reference it as `load skill senior-rust (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major.

## Contract

- References are numbered `01`-`10`; keep them mutually consistent and cross-linked with relative paths.
- Version claims are floors or qualified with "verify upstream"; never present invented exact versions as fact.
- Anti-patterns and checklists close every reference; treat unchecked boxes as review findings.
