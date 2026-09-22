# Error Handling

Scope: `Result`/`Option` idioms, `thiserror` versus `anyhow` policy, error context and chains, panic and `unwrap`/`expect` discipline, and conversion at architectural boundaries.

## The Error Decision Table

| Situation | Representation |
|---|---|
| Library public API | custom enum, `thiserror` or hand-written `Error` impl |
| Binary/application internals | `anyhow::Result<T>` (context-rich, type-erased) |
| Binary top level (`main`) | `anyhow::Result<()>` or `ExitCode` |
| Boundary between layers | convert library error into app error (`From`/`map_err`) |
| Recoverable, expected absence | `Option<T>` |
| Infallible by construction | plain `T`, not `Result` |
| Erased trait-object boundary | `Box<dyn Error + Send + Sync + 'static>` |
| FFI/panic boundary | no error type; status code / `catch_unwind` (see `./05-unsafe-ffi.md`) |

Policy in one line: **libraries use typed errors; applications use `anyhow`; every conversion at a boundary preserves the cause**.

## Result and Option Idioms

- `?` propagates and converts via `From` when the function's error type can be built from the inner error.
- `ok_or_else(|| ...)` maps `Option` to `Result` without allocating on the happy path; `ok_or` is fine for non-allocating errors.
- `transpose()` converts `Result<Option<T>, E>` and back; useful with fallible fetch-or-none APIs.
- `map_err` adds context or maps to a domain error; avoid `map_err(|_| MyError::Unknown)` which drops the cause.
- `Result::and_then` chains fallible steps without nesting; `inspect`/`inspect_err` (Rust 1.76+, verify upstream) for logging without altering the value.
- `try` blocks remain unstable on stable Rust; do not design APIs that need them.
- `main` can return `Result<(), E: Debug>`; for custom exit codes return `ExitCode` from `std::process`.

```rust
fn load(path: &Path) -> anyhow::Result<Config> {
    let text = std::fs::read_to_string(path)
        .with_context(|| format!("reading config {}", path.display()))?;
    let cfg = toml::from_str(&text)
        .with_context(|| format!("parsing config {}", path.display()))?;
    Ok(cfg)
}
```

## thiserror vs anyhow

| Aspect | `thiserror` | `anyhow` |
|---|---|---|
| Purpose | define error types | consume/erase errors |
| Location | library crates | binaries, app internals, tests |
| Downcastable | yes, pattern-match variants | yes via chain/downcast, but discouraged for control flow |
| Context | fields + `#[source]` | `.context()` / `.with_context()` |
| Public API | recommended | forbidden: leaks opaque type, breaks versioning and matching |
| Conversion boilerplate | `#[from]` generates | not applicable |

- Never expose `anyhow::Error` from a published crate. It changes type identity with versions and provides no stable contract.
- Library error enums: one variant per actionable failure mode, plus a catch-all `#[error(transparent)] Other(#[from] ...)` only where genuinely opaque.
- Derive `Debug`; implement `Display` via `thiserror` messages that are lowercase, no trailing period, and name the operation and subject.
- Mark constructors and source fields with `#[from]`, `#[source]`, or `#[error(transparent)]` correctly: `transparent` excludes the source from being printed twice.
- `anyhow!("...")` / `bail!(...)` for ad-hoc failures inside binaries; still attach chains to boundary errors.

```rust
#[derive(Debug, thiserror::Error)]
pub enum AuthError {
    #[error("invalid credentials for {user}")]
    Invalid { user: String },
    #[error("token expired")]
    Expired,
    #[error(transparent)]
    Store(#[from] StoreError),
}
```

## Error Context and Chains

- Context answers "what was the program doing" at the error, not just "what failed". Include the operation and the resource id/path, never secrets.
- Build context lazily (`with_context(|| ...)`) so the allocation is skipped on success.
- Print full chains: `{:#}` for anyhow prints the whole chain on one line; `{:?}` prints source chain plus backtrace when enabled.
- `std::backtrace::Backtrace` is stable (1.65+); `anyhow` captures a backtrace when `RUST_BACKTRACE=1` (or `full`) is set at compile/run time. Verify behavior for your toolchain.
- Do not log and return the same error at every level; log once at the boundary where it is handled, with the chain intact.
- Preserve typed errors for programmatic handling (e.g., HTTP 404 vs 500); use `downcast_ref` only at the edge.

## Panic Policy

| Context | Policy |
|---|---|
| Library code | never panic on user input; return `Result` |
| `main`/startup (bad config) | panic acceptable: fail fast, no partial service |
| Tests | panics are assertions |
| FFI boundary | catch (`catch_unwind`) or document unwind across `extern "C"` as forbidden |
| Task/thread worker | catch at task boundary, log, keep supervisor alive |
| Holding a lock | avoid panics; a panic poisons `std::sync::Mutex` |
| `panic = "abort"` builds | process dies; use only if crash-only design is intentional |

- `panic!`, `assert!`, `assert_eq!`, `unreachable!`, `todo!`, `unimplemented!`, slicing/indexing, integer overflow (debug), `.unwrap()`, `.expect()`, division by zero, and `RefCell` double-borrow all panic.
- Do not use `catch_unwind` for control flow or expected errors; it is for quarantine/supervision, and requires the boundary to be `UnwindSafe` or wrapped in `AssertUnwindSafe`.
- Edition 2024/`extern "C-unwind"` and `"C"` unwind behavior differ; pick the ABI deliberately when panics may propagate. Verify upstream for your targets.
- Log panics: install a panic hook that records the message, location, and backtrace (tracing or `human-panic` for CLIs).

## unwrap/expect Discipline

- `expect("reason")` is allowed when the invariant is local and provable: literals parsed at startup, states just checked, `Mutex::lock` when a poisoned lock should crash anyway.
- `.unwrap()` without a message is banned by policy in production code. Enforce with clippy lints:

```toml
# clippy.toml / Cargo lints
[workspace.lints.clippy]
unwrap_used = "deny"
expect_used = "warn"
panic = "warn"
indexing_slicing = "warn"
```

- Allow locally where justified: `#[allow(clippy::unwrap_used, reason = "compile-time regex")]` (lint reason attributes supported on modern Rust; verify upstream).
- Never `unwrap()` on: parsing external input, environment variables, file/network operations, `JoinHandle` in production without logging, `Mutex` in libraries, or `SystemTime` arithmetic.
- Prefer `let else`, `?`, `unwrap_or_default`, or explicit match over `is_some()` + `unwrap()` (a fragile double lookup).
- Treat `Option::unwrap` in tests as acceptable; tests should fail loudly.

## Conversion at Boundaries

- Convert at the edge: each layer owns its error type; adapt with `From` implementations or a single `map_err` at the call site.
- HTTP boundary: map domain errors to `IntoResponse`/`StatusCode` centrally (one `impl IntoResponse for AppError`), not per handler.
- DB boundary: distinguish constraint violation, not-found, and connectivity at the repository layer; expose domain variants upward.
- gRPC/IPC boundary: map to `tonic::Status` codes with messages safe for clients; log the full chain internally.
- Task boundary: `JoinError` -> application error; include the task name.
- Serialization boundary: `serde_json::Error` with line/column goes into context; do not expose raw parser messages to end users.

```rust
impl axum::response::IntoResponse for AppError {
    fn into_response(self) -> axum::response::Response {
        let status = match &self {
            AppError::NotFound(_) => StatusCode::NOT_FOUND,
            AppError::Validation(_) => StatusCode::UNPROCESSABLE_ENTITY,
            _ => StatusCode::INTERNAL_SERVER_ERROR,
        };
        if status.is_server_error() { tracing::error!(error = ?self, "request failed"); }
        (status, status.canonical_reason().unwrap_or("error")).into_response()
    }
}
```

## Anti-Patterns

- String-only errors: `Result<T, String>` loses structure, source, and downcasting.
- `map_err(|_| ...)` discarding the cause.
- Logging an error and also returning it, causing duplicate logs (or none at the top).
- `unwrap()` in request paths; one malformed input crashes a worker.
- Catch-all enum variant that swallows every error type (`Other(String)`).
- Using panics for validation; returning a `Result` is the contract.
- `expect("this should never happen")` without naming the invariant.
- Treating `Option` and `Result` interchangeably by smuggling `None` as an error with no context.

## Checklist

- [ ] Libraries expose typed errors; applications use `anyhow` internally.
- [ ] Every `?` conversion has a `From` impl or explicit `map_err` with context.
- [ ] Error messages name the operation and subject, contain no secrets, and are lowercase.
- [ ] No `unwrap()` in production paths; `expect` messages state invariants.
- [ ] Panics are impossible on parsed user input; FFI boundaries never unwind.
- [ ] One place per boundary maps errors to wire formats and logs once.
- [ ] `RUST_BACKTRACE`/chain printing is available in staging and production logs.
- [ ] Clippy `unwrap_used`/`panic` lints enabled with documented allowances.
