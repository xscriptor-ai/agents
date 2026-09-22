# Concurrency

Scope: goroutine lifecycle, channels, `select`, context, errgroup/semaphore, worker pools, the memory model, race detection, leak patterns, and how to test concurrent code deterministically.

## Ownership rules

Every goroutine needs three things before it is written:

1. **Owner** — a function/struct that starts and joins it.
2. **Stop condition** — context cancellation, channel close, or finite input.
3. **Join point** — `WaitGroup.Wait`, `errgroup.Wait`, or a done channel the caller reads.

If you cannot name all three, you are writing a leak. `go func()` inside a request handler, loop, or `init` without a join is a bug.

```go
var wg sync.WaitGroup
for _, job := range jobs {
	wg.Add(1)
	go func(job Job) {
		defer wg.Done()
		process(job)
	}(job)
}
wg.Wait()
```

Since Go 1.22 loop variables are per-iteration, so the explicit `job` parameter is no longer required for correctness; keep it when the module declares an older language version. Never capture the loop variable in a goroutine you do not join before the next iteration mutates state — see [./01-language-core.md](./01-language-core.md).

## Channels

- Channels are for **transferring ownership or signaling**; mutexes are for **protecting state**. Do not build shared-state containers out of channels.
- Closing signals "no more values", never "a value was consumed". Only the sender closes; closing from the receiver side panics on the next send.
- Receiving from a closed channel yields the zero value immediately; use the comma-ok form or `range` to distinguish.
- Sends on a closed channel panic; sends/receives on a nil channel block forever. Nil channels are useful only to disable a `select` case.
- Buffered channels decouple producer and consumer; they are not a queueing strategy. If buffer size encodes a policy (backpressure, batching), document it and bound it.
- Synchronous handoff (unbuffered) guarantees the receiver observed the value before the sender proceeds; use it when that guarantee matters.
- Do not use `len(ch)` for control flow; it is a snapshot with no happens-before guarantees.

```go
func generate(ctx context.Context, n int) <-chan int {
	out := make(chan int)
	go func() {
		defer close(out)
		for i := 0; i < n; i++ {
			select {
			case out <- i:
			case <-ctx.Done():
				return
			}
		}
	}()
	return out
}
```

## select

```go
select {
case v := <-in:
	handle(v)
case <-ticker.C:
	flush()
case <-ctx.Done():
	return ctx.Err()
default:
	// non-blocking: only when dropping is correct
}
```

- If several cases are ready, one is chosen uniformly at random; never rely on priority.
- A `default` turns the select into a poll; in a hot loop it becomes a busy-wait. Prefer blocking with cancellation.
- `select {}` blocks forever (deadlock detector fires); `for { select { case <-ctx.Done(): return } }` is the standard cancellable loop.
- `time.After` inside a loop allocates a timer per iteration that cannot be collected until it fires; use a `time.Timer` with `Reset`, or `context.WithTimeout` per operation.

## Context

```go
func (s *Service) Fetch(ctx context.Context, id string) (*Item, error) {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	resp, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch %s: %w", id, err)
	}
	defer resp.Body.Close()
	...
}
```

- First parameter, named `ctx`; never stored in a struct, never `nil` (`context.TODO()` at uncertain boundaries).
- Cancel functions must always be called, including on the error path; `defer cancel()` immediately after creation.
- `context.Cause(ctx)` (1.20+) returns the cancellation cause set by `WithCancelCause`; use `errors.Is` against it rather than guessing.
- `context.WithoutCancel` (1.21+) detaches values while keeping them (for fire-and-forget audit writes). `context.AfterFunc` runs cleanup when a context ends.
- Context values are for request-scoped data (request ID, auth principal, logger) crossing API boundaries — never for optional parameters or config. Typed, unexported keys only.
- Do not pass a context with a deadline that outlives the caller's; child deadlines shorten, never extend.
- Shutdown contexts and request contexts are different; the process-wide root context is canceled by signal handling in `main`, not by handlers. See [./04-web-services.md](./04-web-services.md).

## errgroup, semaphore, singleflight

`golang.org/x/sync` is part of the extended standard library and the default answer for structured concurrency.

```go
g, ctx := errgroup.WithContext(ctx)
g.SetLimit(8)
for _, u := range urls {
	g.Go(func() error {
		return fetch(ctx, u)
	})
}
if err := g.Wait(); err != nil {
	return fmt.Errorf("fetch batch: %w", err)
}
```

- `WithContext` cancels the derived context when any goroutine returns a non-nil error; `Wait` returns the first error. Returning early does not stop running goroutines — they must observe `ctx`.
- `SetLimit` bounds concurrency; `TryGo` returns false instead of blocking. Prefer these to hand-built worker pools unless you need pipelining.
- `semaphore.Weighted` is for weighted resources (memory, connections). Always `Release` with the same weight, normally via `defer` after a successful `Acquire`.
- `singleflight.Group` collapses concurrent identical work (cache stampedes, token refreshes). Use `DoChan` when callers need cancellation; forget entries on failure if retries must be possible.
- `sync.OnceFunc`, `sync.OnceValue`, `sync.OnceValues` (1.21+) memoize initialization with panic propagation. They are safe to copy after first use only if never copied before; treat like `Once`.
- `sync.Map` is for append-mostly caches with disjoint key sets, not a general map replacement. `atomic.Pointer[T]` and typed atomics (1.19+) beat `Mutex` for single-word state.

## Worker pools, pipelines, fan-in/out

A worker pool bounds resource use; a pipeline composes stages. Cancellation must travel downstream, and every stage must close its output.

```go
func runPool(ctx context.Context, in <-chan Job, workers int) <-chan Result {
	out := make(chan Result)
	var wg sync.WaitGroup
	for range workers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for job := range in {
				select {
				case out <- process(job):
				case <-ctx.Done():
					return
				}
			}
		}()
	}
	go func() {
		wg.Wait()
		close(out)
	}()
	return out
}
```

Fan-in: a single collector goroutine plus a `WaitGroup` closing the merged channel. Fan-out: N goroutines reading the same input channel (channels distribute each value to exactly one reader, which is a load-balancing primitive).

Anti-patterns: unbounded `go` per item; result channels with no reader after early cancellation; pipelines that never close intermediate channels; `WaitGroup.Add` called after `Wait` can start.

## Memory model and race detection

Guarantees you can rely on:

- Goroutine start happens-before the first statement of the new goroutine.
- A channel send happens-before the corresponding receive completes; `close` happens-before a receive of the zero value.
- `Mutex.Unlock` happens-before a subsequent `Lock`; `RWMutex` read locks provide the same for writers.
- Atomic operations on the same location are sequentially consistent per the Go memory model.
- Anything else shared needs synchronization. "It worked locally" is not a happens-before edge.

Race detector:

```bash
go test -race ./...
go build -race -o bin/app-race ./cmd/app
```

- Detects racy accesses that actually occur in the run; it is not a proof of absence.
- Treat every report as a real bug: add synchronization or redesign ownership.
- CI should run `-race` for unit tests and at least one integration path; the detector needs cgo enabled on most platforms, so keep a race-enabled CI job separate from pure static builds.
- `GORACE="halt_on_error=1"` makes CI fail fast.

## Leak patterns

| Pattern | Symptom | Fix |
|---|---|---|
| Send with no guaranteed receiver | goroutine parked on channel forever | select on `ctx.Done()`; buffered result when the contract allows drop |
| `context.WithCancel` cancel not called | context tree and child goroutines persist | always `defer cancel()` |
| Ticker/time.After in a loop | timer heap growth, delayed wakeups | `time.NewTicker` + `defer Stop`; reuse timers |
| Worker pool never signaled to stop | workers idle forever after work | close input or cancel context; join workers |
| HTTP response body not closed | connection stuck in pool, leak report | `defer resp.Body.Close()` plus drain |
| `WaitGroup.Add` inside spawned goroutine | `Wait` returns early or panics | `Add` before `go` |
| Blocked logger/metrics sink | whole pipeline stalls | bounded async sinks with drop policy |
| Context value carrying a client | request lifetime pins transport/resources | keep clients in structs with explicit lifecycle |

Diagnostics: `go tool pprof` goroutine profile, `runtime.NumGoroutine` deltas in tests, and `GOEXPERIMENT`/runtime leak detection when available (verify upstream for the current toolchain). See [./07-performance-profiling.md](./07-performance-profiling.md).

## Testing concurrent code

- `testing/synctest` (stable in 1.25+) runs a goroutine inside a "bubble" with a fake clock: `synctest.Test(t, func(t *testing.T) { ... synctest.Wait() ... })`. Use it to test timeouts, debounce, retries, and leak behavior deterministically.
- `go.uber.org/goleak` catches leaked goroutines: `goleak.VerifyTestMain(m)` in `TestMain`, or `defer goleak.VerifyNone(t)()` in focused tests.
- Use `t.Context()` (1.24+) for per-test cancellation and `context.WithTimeout` in tests to fail fast instead of hanging CI.
- Replace channels with `synctest.Wait()` where possible; when not, synchronize with channels rather than sleeps.
- Run `go test -race -count=100` on concurrency-sensitive packages; add `-shuffle=on` to catch interleaving assumptions.
- Assert on observable outcomes (counts, errors) rather than internal scheduling.
- See [./06-testing.md](./06-testing.md) for fuzz/benchmark hygiene and Testcontainers integration.

## Anti-patterns

- Goroutines started in `init()` or package-level variables.
- A `sync.Mutex` protecting an entire struct while methods call each other (reentrancy deadlock).
- `RWMutex` used for write-heavy state; prefer `Mutex` or atomics.
- Channels used to signal completion where `WaitGroup`/`errgroup` expresses it directly.
- Background goroutine writing to a map read by request handlers.
- `time.Sleep` as synchronization; polling loops without backoff.
- Unbounded fan-out from request handlers ("goroutine per item").
- Forgetting `resp.Body.Close()` or `rows.Close()` in concurrent code paths.
- Canceling a context to "stop" work while downstream code ignores `ctx`.
- Using `runtime.GOMAXPROCS(1)` or `LockOSThread` as a substitute for correct synchronization.

## Review checklist

- [ ] Every goroutine has owner, stop condition, and join.
- [ ] Channels are closed exactly once, by the sender, and only when no more sends are possible.
- [ ] `select` cases include cancellation and never use `default` to avoid handling backpressure.
- [ ] Context is first argument, canceled on all paths, never stored, never nil.
- [ ] Bounded concurrency via `errgroup.SetLimit`/`semaphore` for external calls.
- [ ] `go test -race` passes; leak checks run on packages that spawn long-lived goroutines.
- [ ] Shared state has an explicit happens-before edge (channel, mutex, or atomic).
- [ ] Timers/tickers stopped; no `time.After` in loops.
- [ ] Concurrent tests are deterministic, not sleep-based.
