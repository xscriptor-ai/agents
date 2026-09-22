# Async and Concurrency

Scope: tokio runtime tuning, tasks, cancellation and cancellation safety, structured concurrency, channels, `select!`, backpressure, `Send`/`Sync` for futures, and async traits.

## Runtime Selection and Tuning

| Runtime | Use when | Notes |
|---|---|---|
| `#[tokio::main]` multi-thread | servers, CPU+IO mix | default worker threads = logical CPUs; good default |
| `#[tokio::main(flavor = "current_thread")]` | CLI tools, tests, single-threaded embedders | lower memory, deterministic polling order |
| `Runtime::new` manual | library owns runtime, custom config | build once, never per request |
| `spawn_blocking` pool | filesystem, CPU-bound, FFI, DNS via blocking libs | bounded; default cap 512 (verify upstream) |
| `LocalSet` | non-`Send` futures | single-thread only |
| Other (smol, async-std, embassy) | niche/embedded | see `./07-embedded.md` |

```rust
let rt = tokio::runtime::Builder::new_multi_thread()
    .worker_threads(4)
    .max_blocking_threads(64)
    .thread_name("app-worker")
    .enable_all()
    .build()?;
```

- Never call `block_on` inside async context. Use `spawn_blocking` or an async equivalent.
- Blocking syscalls on worker threads starve timers and IO. Audit `std::fs`, `std::net`, `std::process`, and synchronous DB drivers.
- `tokio::time::pause()` in tests makes time deterministic; requires `test-util`.
- Enable only needed features (`rt-multi-thread`, `net`, `time`, `sync`, `macros`) to reduce build time and binary size.
- Tokio Console (`console-subscriber`) is the tool for diagnosing task stalls and waker storms; keep it behind a dev feature.
- Graceful shutdown belongs to the application: a `CancellationToken` plus drained `JoinSet`/`TaskTracker`. See `./06-web-data.md` for HTTP wiring.

## Tasks

- `tokio::spawn` requires `F: Future + Send + 'static` and returns `JoinHandle<T>`. The future must own everything it uses.
- `JoinHandle` returns `Result<T, JoinError>`; `JoinError::is_panic()` distinguishes panic from cancellation.
- `JoinSet` manages a dynamic group: spawn, `join_next().await`, and abort remaining tasks on drop (verify exact behavior for your toolchain upstream).
- `TaskTracker` (tokio-util) plus `CancellationToken` is the canonical structured-concurrency pair.
- `AbortHandle`/`JoinHandle::abort` stops at the next await point; it does not run cleanup. Design for drop-based cleanup and cancellation tokens.
- Task-local state (`tokio::task_local!`) is per-task context that follows spawned work only if re-scoped inside `spawn`. Prefer passing an `Arc<Context>` explicitly.

```rust
let mut set = JoinSet::new();
for shard in shards {
    set.spawn(async move { process(shard).await });
}
while let Some(res) = set.join_next().await {
    match res { Ok(Ok(())) => {}, Ok(Err(e)) => error!(?e, "shard failed"), Err(je) => warn!(?je, "join failed") }
}
```

## Cancellation and Cancellation Safety

- Dropping a future cancels it. Cancellation happens at `.await` points; code between awaits runs to completion or not at all.
- A future is cancellation-safe if dropping it cannot lose data that was already committed from its perspective. `tokio::io::AsyncReadExt::read` is not safe to cancel midway if you must not lose bytes; `read_exact` is not; `AsyncWriteExt::write_all` is not.
- Cancellation-safety table (common ops):

| Operation | Safe to cancel? | Guidance |
|---|---|---|
| `TcpStream::connect` | yes | retry is free |
| `read`/`read_buf` | no | bytes may be lost; keep buffer/state |
| `read_exact`/`read_to_end` | no | wrap in a task or buffer |
| `write`/`write_all`/`flush` | no | partial writes |
| `sleep`/`timeout` | yes | no data |
| `mpsc::Sender::send` | no (may be cancelled after reserve) | use `reserve` explicitly if needed |
| `Semaphore::acquire` | no | permit may be acquired and dropped |
| `JoinHandle` | yes | abort semantics |
| `Receiver::recv` | yes (for mpsc), but messages may be unreceived | design idempotent handling |

- `select!` polls branches in random order by default; each unselected branch is dropped, so all branches must be cancellation-safe. Use `biased;` for priority, and always add a default path or `else` branch when needed.
- Wrap whole critical sequences in `tokio::spawn` if they must survive a `select!` loser drop.
- `CancellationToken` (tokio-util) composes: `child_token`, `cancelled().await`, `run_until_cancelled`. Cancel is idempotent and wakes all waiters.

```rust
tokio::select! {
    _ = token.cancelled() => return Ok(()),
    res = do_work(&mut state) => res?,
}
```

- `timeout(d, fut)` drops `fut` on expiry: only use around cancellation-safe futures; otherwise spawn it and await the handle with a timeout.
- Graceful shutdown sequence: stop accepting (drop listener) -> cancel token -> await tasks with a deadline -> run cleanup -> exit. Never `process::exit` before drains unless aborts are acceptable.

## Structured Concurrency

- Own every task: store handles, join them, and propagate errors. Fire-and-forget tasks are a leak and an observability hole.
- A supervision pattern: one coordinator owns a `JoinSet`, restarts or records failed children, and exposes a single completion future to the caller.
- Backpressure must be end-to-end: bounded channels + `Semaphore` + connection limits. Unbounded queues convert overload into OOM.
- Prefer scoped APIs (`JoinSet`, `TaskTracker`, `tokio::task::scope` when available/futures `scope`) so no task outlives its data.

## Channels

| Channel | Producers | Consumers | Semantics | Use |
|---|---|---|---|---|
| `mpsc` | many | one | ordered queue, bounded/unbounded | work queues, actor inboxes |
| `oneshot` | one | one | single value | request/response, task results |
| `broadcast` | many | many | every receiver sees every message (lagging drops oldest) | events, shutdown fan-out |
| `watch` | one | many | latest value only | config updates, state snapshots |
| `Notify` | many | many | wake-up signal, no payload | condition-style coordination |
| `Semaphore` | n/a | n/a | permit pool | concurrency limits |

- Always prefer bounded `mpsc` for work queues. `send().await` applies backpressure; `try_send` surfaces `Full` for load shedding.
- `broadcast::Receiver` treats lag as `RecvError::Lagged(n)`; decide whether to resync or fail. Default capacity must be sized for burst rate, not steady state.
- `watch` requires `T: Clone` and stores one value; good for "current config" and shutdown flags, bad for event streams.
- Cross-process coordination needs an external broker (NATS, Redis streams, Kafka); in-process channels do not survive restart.
- Avoid sharing `Arc<Mutex<HashMap>>` as a "channel"; a task owning the map plus an mpsc inbox removes lock contention and makes ownership obvious.

## Send/Sync for Futures and Tasks

- A future is `Send` iff all values held across `.await` points are `Send`. The compiler points at the offending binding.
- Typical offenders: `Rc`, `RefCell`, `MutexGuard`, non-`Send` trait objects, `*const T`, and `&T` where `T: !Sync`.
- Holding a `std::sync::MutexGuard` across `.await` produces a non-`Send` future and potential deadlocks. Scope the guard before awaiting, or use `tokio::sync::Mutex` when the section genuinely awaits.
- Spawning non-`Send` work requires `LocalSet` on a current-thread runtime.
- `Send` bounds propagate: an `async fn` generic over `T` may only be `Send` if `T: Send`; add bounds at the public boundary, not everywhere.
- Beware `async` blocks capturing `&mut self` across awaits; split the method or move owned state in.

```rust
// BAD: guard held across await (non-Send, deadlock risk)
let guard = self.inner.lock().unwrap();
some_async_call().await;
drop(guard);

// GOOD
{ let mut g = self.inner.lock().unwrap(); g.update(); }
some_async_call().await;
```

## Blocking, Timeouts, and Retries

- `spawn_blocking` for anything that can take >100us of CPU or uses blocking IO. Its pool is bounded; a saturated pool queues.
- CPU-bound parallelism should be a rayon pool, not many blocking tasks (see `./10-performance-security-observability.md`).
- Timeouts everywhere at boundaries: connect, request handling, DB queries, shutdown. Track remaining deadline (`tokio::time::Instant`) through retries.
- Retries: exponential backoff with jitter (`backoff`, `tower::retry`, or hand-rolled). Only retry idempotent operations; propagate the original error after N attempts.
- Circuit breakers (`tower` middleware or a custom state machine) prevent retry storms.

## Async Traits (AFIT and dyn)

- AFIT: `async fn` in traits is stable (Rust 1.75+, verify upstream) and lowers to RPITIT. It is not `dyn`-compatible by default.
- Making async traits `dyn`-compatible:
  1. `#[async_trait]` (crate `async-trait`) boxes every method future — allocation per call, works on all targets, supports `dyn`.
  2. Return-position `impl Future` plus manual `Pin<Box<dyn Future>>` signatures.
  3. `trait-variant` generates a `Send`-bounded twin via a macro.
- `async fn` in a public trait is fine for static dispatch; add `Send` bounds at the trait or impl level when tasks spawn the returned future.
- Async closures (`async || {}`, `AsyncFn`/`AsyncFnMut`/`AsyncFnOnce`) are stable in edition 2024 (Rust 1.85+, verify upstream); they simplify callback APIs that spawn.
- Cancellation safety of returned futures is part of the contract; document it for each trait method.

```rust
#[async_trait::async_trait]
pub trait Fetcher: Send + Sync {
    async fn fetch(&self, id: u64) -> Result<Vec<u8>, FetchError>;
}
```

## Anti-Patterns

- Blocking calls in async context (`std::fs`, `std::thread::sleep`, synchronous HTTP/DB clients).
- `tokio::spawn` with a detached handle and no error logging; failures vanish.
- Unbounded channels hiding overload.
- `select!` over cancellation-unsafe branches (partial reads/writes).
- Locking an async mutex for short CPU-only sections (use `std` mutex, no await).
- Runtime per request (`Runtime::new` in a handler).
- Using `tokio::time::sleep` to "fix" races instead of proper synchronization.
- Spawning inside loops without a semaphore or join tracking.

## Checklist

- [ ] Every spawned task has an owner, a join path, and error handling.
- [ ] Cancellation behavior is understood for each `select!`/`timeout` branch.
- [ ] Shutdown is token-driven and drains with a deadline.
- [ ] All queues are bounded; overload behavior (block vs shed) is explicit.
- [ ] No blocking calls or lock guards across `.await`.
- [ ] `Send`/`Sync` bounds appear where tasks require them; no gratuitous `'static` boxing.
- [ ] Timeouts and retries with jitter are applied at every external boundary.
