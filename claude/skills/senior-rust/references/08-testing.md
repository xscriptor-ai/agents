# Testing

Scope: unit/integration/doc tests, property testing, criterion benchmarks, cargo-nextest, Miri, loom, snapshot testing, fuzzing, coverage, and test doubles.

## Test Taxonomy

| Kind | Location | Compiles with crate? | Access | Use for |
|---|---|---|---|---|
| Unit | `src/**/tests.rs` under `#[cfg(test)] mod tests` | yes | private items | internal invariants, edge cases |
| Integration | `tests/*.rs` | links public API | public only | public contract, end-to-end of a crate |
| Doc test | `` ```rust `` in doc comments | compiled as separate crate | public, with `extern crate` | API examples that must keep compiling |
| Example | `examples/*.rs` | built by `cargo test`/`cargo build --examples` | public | usage demos, smoke binaries |
| Benchmark | `benches/*.rs` (criterion) | yes | varies | perf regression detection |
| Fuzz | `fuzz/fuzz_targets/*.rs` | separate, cargo-fuzz | varies | parsers, untrusted input, unsafe |
| Property | wherever | yes | varies | invariants over generated input |

- Unit tests may use private APIs; integration tests must not. If an integration test needs internals, extract a testable module or add a `#[doc(hidden)] pub` seam.
- `#[cfg(test)]` code is not compiled for doc tests or downstream users — do not depend on it from `pub` generics.
- Keep tests deterministic: no real clock/network/random; inject `Clock`, `Rng`, and clients.

## Writing Useful Tests

- Name tests after behavior: `rejects_expired_token`, not `test_validate_2`.
- One logical assertion per test where practical; use table tests for many cases.
- Test the contract, not the implementation: public API behavior, invariants, error variants, and boundary values (empty, max, off-by-one, unicode, zero-length).
- Assert on error *types/variants* and messages that are part of the contract; use `matches!` or `assert_matches` to avoid brittle formatting.
- Use `#[should_panic(expected = "...")]` only for genuinely panicking contracts (or remove the panic and return `Result` instead).
- `#[ignore]` marks tests that need external resources; run them explicitly in CI with `--ignored`.
- `#[cfg_attr(miri, ignore)]` for tests Miri cannot execute (FFI, filesystem unsupported ops).

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_empty_input_as_none() {
        assert_eq!(parse(""), None);
    }

    #[test]
    fn rejects_oversized_frame() {
        assert!(matches!(decode(&[0xFF; 64]), Err(DecodeError::TooLarge { .. })));
    }
}
```

## Doc Tests

- Doc tests are executed by `cargo test`; they are the best regression net for README-level examples.
- Attributes: `no_run` (compile but do not run), `ignore` (skip; avoid), `compile_fail` (must not compile), `should_panic`, `text`.
- Hidden setup lines start with `#` and are compiled but not rendered — use for `fn main`, imports, or unwraps.
- Mark non-runnable examples (`no_run`) when they need a server/DB; still compile them in CI.
- `cargo test --doc` isolates runtime; `rustdoc` linkcheck is not a thing — verify intra-doc links with `RUSTDOCFLAGS="-D warnings"` and `cargo doc`.
- Set `[lib] doctest = false` only when doctests are impossible (e.g., `no_std` crates); otherwise keep them on.
- Add `#![doc = include_str!("../README.md")]` to test README examples.

## Property Testing

- `proptest` (or `quickcheck`): generate inputs, shrink failures to minimal counterexamples.
- Define strategies near the type: `fn arb_email() -> impl Strategy<Value = Email>`; compose with `prop_map`, `prop_flat_map`.
- Assert properties, not examples: round-trip (`decode(encode(x)) == x`), idempotence, commutativity, invariants (`len() <= capacity`), and no-panic.
- Persist regressions: proptest writes failures to `proptest-regressions/`; commit those files.
- Bound the search space (`prop_filter` sparingly, `prop_assume` for preconditions) and set `PROPTEST_CASES` in CI for longer runs.
- Combine with fuzzing: proptest for structured inputs, cargo-fuzz for raw bytes and long campaigns.

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn roundtrip(input in any::<Vec<u8>>()) {
        let frame = encode(&input);
        prop_assert_eq!(decode(&frame).unwrap(), input);
    }
}
```

## Continuous Benchmarking (criterion)

- `criterion` measures wall time with statistical analysis: warmup, sample size, outliers, and change detection against a baseline.
- Always `black_box` inputs and outputs so the optimizer cannot elide work.
- Benchmark at the right granularity: micro (function), meso (request handling), and end-to-end (process) — only micro-benchmarks in-repo by default.
- `cargo bench` compares to the previous saved baseline; use `--save-baseline`/`--baseline` and store `target/criterion` in CI artifacts.
- `Throughput::Bytes`/`Elements` reports throughput instead of raw time for IO/parsing benchmarks.
- For instruction-count benchmarks (immune to CI noise), use `iai-callgrind` (Valgrind-based) — verify the current crate/function names upstream.
- Do not gate PRs on wall-time microbenchmarks without noise controls (dedicated runner, instruction counts, or median of many runs).
- `cargo-flamegraph` and `perf` for finding what to benchmark (see `./10-performance-security-observability.md`).

## cargo-nextest

- Nextest runs each test in its own process, defaulting to parallelism with per-test timeouts; output is clearer and faster than `cargo test` for large suites.
- Config `nextest.toml`: profiles (`default`, `ci`), retries for known-flaky tests (`retries = { backoff = "exponential", count = 2 }`), test groups for serial tests.
- `--partition count:1/4` splits suites across CI shards; `--profile ci` adds retries and strict output.
- `cargo nextest run --all-features --workspace`; doc tests still run via `cargo test --doc` (nextest does not run them).
- `cargo nextest list` for auditing; `--no-fail-fast` to see all failures.
- JUnit output: `--profile ci --message-format libtest-json` piped through `cargo-nextest` tooling or `nextest-rs` converters; many CIs accept nextest's native JUnit.

## Miri and Loom

- Miri catches UB in unsafe code and some logic errors (invalid values, leaks, races) by interpreting MIR. See `./05-unsafe-ffi.md` for flags and setup.
- Run Miri on unsafe modules with strict provenance; expect it to be 10-100x slower — keep the Miri test set focused.
- Loom model-checks concurrent code by exploring interleavings under a configurable bound (`LOOM_MAX_PREEMPTIONS`).
  - Gate code on `#[cfg(loom)] use loom::sync::{Mutex, Arc};` and mirror the types in a small `sync` module.
  - Test: `loom::model(|| { ... })`; exhaustively explores schedules for small thread counts.
  - Loom substitutes atomics and Arc; `loom::thread::spawn` instead of `std::thread`.
  - Loom does not model tokio task scheduling; test the synchronous primitives (locks, queues) under loom, then test task orchestration separately.
- Sanitizers (ASan/TSan on nightly or `-Zsanitizer`) complement Miri where FFI/unsupported ops block it.

## Snapshots

- `insta` for snapshot assertions: `assert_snapshot!`, `assert_debug_snapshot!`, `assert_json_snapshot!`.
- Workflow: run tests -> pending `.snap.new` files -> `cargo insta review` or `cargo insta accept`; commit `.snap` files.
- Use inline snapshots (`assert_snapshot!(value, @"...")`) for small, local expectations; file snapshots for larger output.
- Redact nondeterminism (timestamps, ids, paths) with `insta::with_settings!({filters => ...})` rather than post-processing.
- Snapshot tests are excellent for API responses, CLI output, error messages, and generated code; they are poor for behavior assertions (they fail on any formatting change).
- `expect-test` is the lighter alternative for inline expected strings.

## Fuzzing

- `cargo-fuzz` (libFuzzer) is the baseline: `cargo fuzz init`, `cargo fuzz add target`, `cargo fuzz run target`.
- Feed `&[u8]` through `arbitrary` to structured types where a grammar helps; keep a raw-bytes target for parser robustness.
- Corpus management: commit seed corpus, download OSS-Fuzz corpus in CI; crashes are written to `artifacts/` — turn each into a regression test.
- Run short fuzz jobs on PRs (time-boxed) and long campaigns nightly; use `-max_total_time=...`, `-rss_limit_mb`, `-jobs`/`-workers`.
- For integration with Rust test harnesses, `cargo afl`/`afl.rs` is an alternative; verify maintenance status upstream.
- Fuzz unsafe code under ASan (`cargo fuzz run` uses sanitizers by default on supported targets).

## Coverage

- `cargo-llvm-cov` is the current standard: `cargo llvm-cov --workspace --all-features --html`, producing source-based coverage.
- Branch coverage: `cargo llvm-cov --branch` on modern LLVM; line-only coverage can hide untested match arms.
- CI: upload `lcov`/`cobertura` artifacts; gate on coverage of changed lines rather than a global percentage.
- `grcov` is an older alternative; both are acceptable — pick one and keep it stable.
- Coverage of tests themselves is not useful; exclude test modules and generated files via `--ignore-filename-regex`.
- Coverage cannot prove correctness; combine with property tests and Miri for high-risk code.

## Test Doubles and Integration Fixtures

| Need | Tool |
|---|---|
| Mock traits | `mockall` (auto-mock with `#[automock]`), hand-written fakes |
| HTTP clients | `wiremock`, `httpmock`, `mockito` |
| HTTP servers | `axum` router + `tower::ServiceExt::oneshot` (no port needed) |
| Databases | `testcontainers`, `sqlx::test` (per-test DB), `pg_embed`/`libsql` for SQLite |
| Time | `tokio::time::pause`, injected `Clock` trait, `time` fakes |
| Randomness | seeded `rand::rngs::StdRng`, injected `Rng` |
| Filesystem | `tempfile::TempDir` |
| Env vars | `temp-env` or a config struct built in tests (never mutate process env in parallel tests) |

- Prefer hand-written fakes over generated mocks; they exercise behavior and stay readable.
- `sqlx::test` creates an isolated database per test when given a database URL; migrations applied automatically (verify behavior upstream).
- Testcontainers require Docker in CI; keep a fast unit suite that runs without Docker and a slower integration suite that can be skipped.
- Avoid global mutable state between tests; nextest's process-per-test makes leaks less likely but not harmless.

## Anti-Patterns

- Tests coupled to private implementation details; refactors break tests without behavior changes.
- `sleep` to synchronize: use channels, barriers, or paused time.
- Testing only happy paths and no error variants.
- Snapshot tests accepted blindly via `cargo insta accept` without review.
- Gating on flaky wall-clock microbenchmarks.
- Ignoring Miri/loom results because "it's probably fine".
- A single giant integration test that exercises everything and fails with no localization.
- Tests that require network access or a shared database instance.

## Checklist

- [ ] Public APIs have unit and integration coverage; error variants asserted.
- [ ] Doc examples compile and run (or are `no_run` with a reason).
- [ ] Properties tested with proptest for parsers/codecs/state machines.
- [ ] Benchmarks run in a stable environment and track regressions.
- [ ] cargo-nextest in CI with timeouts; flaky tests quarantined with retries, then fixed.
- [ ] Miri on unsafe modules; loom on lock/queue implementations.
- [ ] Fuzz targets for every untrusted-input parser; corpora committed.
- [ ] Coverage tracked per changed lines, not as a vanity metric.
- [ ] Integration fixtures are hermetic (containers/temp dirs), no shared external state.
