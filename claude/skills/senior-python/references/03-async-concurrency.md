# Async and Concurrency

asyncio, structured concurrency, cancellation and timeout semantics, anyio/trio, sync-async boundaries, queues and backpressure, and thread/process/free-threading guidance.

## Choosing a Model

| Workload | Model | Rationale |
|---|---|---|
| Many sockets, HTTP fan-out, WebSockets | asyncio + TaskGroup | Cheap concurrency, low memory per task |
| Blocking SDK/DB driver | `asyncio.to_thread` / anyio thread pool | Keeps the loop free; bounded pool |
| CPU-bound batch, image/ML work | Process pool | Bypasses GIL; pay pickling cost |
| Framework-portable libraries | anyio | Same code on asyncio and trio |
| Strict cancellation and nurseries | trio | Best-in-class structured concurrency |
| Shared-state CPU parallelism | Processes first | Free-threading only with benchmark proof |

Rules: an `async def` function does nothing until awaited or scheduled; the GIL still
serializes CPU-bound threads; and "async" never makes a slow query fast.

## Entry Points and Loop Hygiene

```python
import asyncio

async def main() -> None:
    await asyncio.sleep(0)

if __name__ == "__main__":
    asyncio.run(main())
```

- `asyncio.run` is the only entry point for scripts; use `asyncio.Runner` when running
  several coroutines with shared context/debug settings.
- Inside async code use `asyncio.get_running_loop()`; `get_event_loop()` in libraries is
  deprecated and tightened in newer CPython. Never create loops manually in application
  code.
- `asyncio.run` cannot be nested; frameworks already own a loop. Use
  `run_coroutine_threadsafe` only when crossing from a real thread.
- Enable debug in development: `asyncio.run(main(), debug=True)` or `PYTHONASYNCIODEBUG=1`;
  `-X dev` surfaces un-awaited coroutines and slow callbacks.
- `uvloop` is a drop-in policy on Linux/macOS and typically improves throughput; verify it
  supports your interpreter (including free-threaded builds) before enabling.

## Structured Concurrency

```python
import asyncio

async def fetch(url: str) -> str:
    await asyncio.sleep(0.01)
    return url

async def main() -> None:
    async with asyncio.TaskGroup() as tg:
        a = tg.create_task(fetch("a"))
        b = tg.create_task(fetch("b"))
    print(a.result(), b.result())
```

| Aspect | `TaskGroup` (3.11+) | `asyncio.gather` |
|---|---|---|
| Structure | Scoped; block cannot exit while tasks run | Free-floating futures |
| Failure | Cancels siblings, raises `ExceptionGroup` | Raises first (or returns all with `return_exceptions=True`) |
| Result access | Tasks created inside, read after block | Awaited return list |
| Partial failure | Explicit `except*` / subgroup | Easy to silently ignore |

- Prefer `TaskGroup`. Reach for `gather` only for simple all-or-nothing fan-out on 3.10.
- `gather(..., return_exceptions=True)` returns failures as values; if you use it, inspect
  every result. Otherwise use exceptions.
- Limit concurrency explicitly with semaphores; a TaskGroup over 10k URLs is an outage.

## Cancellation Semantics

- `asyncio.CancelledError` inherits from `BaseException`; `except Exception` will not catch
  it, but bare `except:` or `except BaseException:` will. Never swallow it.
- On cancellation, clean up in `finally`; re-raise after cleanup.
- `await` inside a cancelled task's `finally` may immediately re-cancel if the await itself
  is cancellable; wrap critical cleanup in `asyncio.shield(...)` or perform it in a
  separate task.
- `asyncio.shield(coro)` protects the inner awaitable but the outer await still raises
  `CancelledError`; keep a reference to the shielded task to retrieve its result later.
- Cancellation is cooperative: code that never awaits cannot be cancelled, and a task in
  `finally` blocks shutdown.
- `TaskGroup` cancels remaining tasks when one fails, then waits for them to finish before
  raising. Never assume the group exits early.

```python
async def flush() -> None:
    await asyncio.sleep(0.01)

async def worker() -> None:
    try:
        await asyncio.sleep(60)
    except asyncio.CancelledError:
        raise
    finally:
        await asyncio.shield(flush())
```

## Timeouts

```python
async def get(url: str) -> bytes:
    async with asyncio.timeout(5):
        await asyncio.sleep(0.1)
        return b"ok"
```

- `asyncio.timeout` (3.11+) is the modern API; it cancels the enclosed work and raises
  `TimeoutError`. `asyncio.timeout_at` takes a deadline; `handle.reschedule()` adjusts an
  active timeout.
- `asyncio.wait_for` is legacy: it cancels the task but cannot guarantee the task is done
  when it returns. Prefer `timeout`.
- Stack timeouts per layer (connect, read, request) rather than one giant outer timeout;
  HTTP clients have their own timeout configuration.
- A timeout that must not interrupt a critical section should be placed outside a
  `CancelScope(shield=True)` / `shield` boundary, not inside.

## Tasks Must Be Owned

The event loop keeps only weak references to tasks; a dropped `create_task` can be garbage
collected mid-flight.

```python
_background: set[asyncio.Task[None]] = set()

def spawn(coro) -> None:
    task = asyncio.create_task(coro)
    _background.add(task)
    task.add_done_callback(_background.discard)

async def shutdown() -> None:
    for task in list(_background):
        task.cancel()
    await asyncio.gather(*_background, return_exceptions=True)
```

- Track every background task; on shutdown cancel and await with a grace period.
- Name tasks (`create_task(coro, name="...")`) so `all_tasks()` output is readable.
- Eager task factory (`asyncio.eager_task_factory`, 3.12+) starts coroutines synchronously
  and can cut latency for cache hits; enable per-event-loop only after benchmarking.
- `asyncio.get_event_loop_policy().set_task_factory` affects all tasks; keep application-wide
  changes deliberate.

## anyio and trio

```python
import anyio

async def worker(name: str) -> None:
    await anyio.sleep(0.01)

async def main() -> None:
    async with anyio.create_task_group() as tg:
        tg.start_soon(worker, "a")
        tg.start_soon(worker, "b")

anyio.run(main)
```

- anyio gives one API over asyncio and trio: `create_task_group`, `CancelScope` (with
  `.cancel()`, `shield=True`, `deadline`), `fail_after`, `move_on_after`, `to_thread.run_sync`,
  `from_thread.run`, `CapacityLimiter`, `MemoryObjectStream`.
- Use anyio when writing libraries intended to run on both backends or when you want cancel
  scopes without asyncio's `TaskGroup` differences.
- trio (`open_nursery`, `CancelScope`, `trio.to_thread.run_sync`) is the reference
  implementation of structured concurrency; choose it when cancellability and deterministic
  teardown matter more than ecosystem breadth.
- Test anyio code with the `anyio` pytest plugin:

```python
import pytest

@pytest.fixture(params=["asyncio", "trio"])
def anyio_backend(request):
    return request.param

@pytest.mark.anyio
async def test_concurrent() -> None:
    async with anyio.create_task_group() as tg:
        tg.start_soon(anyio.sleep, 0)
```

## Sync and Async Boundaries

| From | To | Use |
|---|---|---|
| async | blocking function | `await asyncio.to_thread(fn, *args)` |
| async | blocking function, bounded pool | `loop.run_in_executor(executor, fn, *args)` |
| async | subprocess | `asyncio.create_subprocess_exec` |
| sync | coroutine, loop running elsewhere | `asyncio.run_coroutine_threadsafe(coro, loop)` |
| async | CPU-bound | `ProcessPoolExecutor` or a worker queue |

- `asyncio.to_thread` propagates `contextvars`; raw `run_in_executor` does not. Use
  `to_thread` unless you need a dedicated executor.
- Never call `asyncio.run`, `loop.run_until_complete`, or `time.sleep` inside a running
  loop. `nest_asyncio` is a hack that hides design errors.
- Synchronous DB drivers (psycopg2, MySQLdb, most ORMs' sync sessions) must be offloaded.
  Async drivers are preferable where mature.
- Offloading does not create capacity: a thread pool has finite workers, and a thread
  holding the GIL on CPU work still stalls the process. For CPU, use processes.
- Blocking detection: `PYTHONASYNCIODEBUG=1`, `loop.set_debug(True)`,
  `loop.slow_callback_duration`, plus a runtime blocker (for example `blockbuster`) in
  tests to fail on accidental blocking calls.

## Queues, Semaphores, Backpressure

```python
import asyncio

queue: asyncio.Queue[str] = asyncio.Queue(maxsize=100)

async def produce(items: list[str]) -> None:
    for item in items:
        await queue.put(item)  # blocks when full: backpressure
    await queue.put("__stop__")

async def consume() -> None:
    while True:
        item = await queue.get()
        try:
            if item == "__stop__":
                return
            await asyncio.sleep(0.001)
        finally:
            queue.task_done()
```

- Bound every queue. Unbounded queues convert overload into memory growth and OOM.
- `put_nowait` raises `QueueFull`; decide whether to drop, shed load, or apply backpressure.
- Cap fan-out with `asyncio.Semaphore`/`BoundedSemaphore`; share the limiter with the
  connection pool size so you do not queue inside the pool.
- For streams, use `asyncio.StreamReader`/writer or async iterators with explicit window
  limits; SSE/WebSocket producers must also respect slow-consumer limits.
- `asyncio.Event`, `Lock`, `Condition` are not thread-safe; never share them with threads.
- Graceful shutdown: stop accepting work, drain the queue with a deadline, cancel the rest.

## Threads, Processes, Free-Threading

| Tool | Use | Caveats |
|---|---|---|
| `threading` | I/O-bound work with blocking APIs | GIL serializes CPU; not cancellable |
| `ThreadPoolExecutor` | Bounded offload from asyncio | Default worker count may oversubscribe |
| `ProcessPoolExecutor` | CPU-bound parallelism | Pickling, startup cost, memory duplication |
| `multiprocessing.shared_memory` | Large arrays across processes | Manual lifetime; no automatic cleanup |
| Free-threaded CPython 3.14 | CPU threads without GIL | Extension readiness; single-thread slowdown |

- Start methods: `spawn` is safest and required on macOS/Windows; `fork` in a
  multi-threaded process can deadlock (locks held by threads that do not exist in the
  child). Newer CPython deprecates `fork` here and moves the Linux default toward
  `forkserver` — verify upstream and set the method explicitly.
- Use `ProcessPoolExecutor(max_workers=os.process_cpu_count())` (fall back to
  `os.cpu_count()`) and send picklable data; workers cannot share ORM sessions or clients.
- For free-threaded builds, benchmark both single-thread and multi-thread throughput;
  enable only when your native extensions declare GIL-independence. See
  [language core](./01-language-core.md).
- `concurrent.futures` tasks are not cancellable once running; cancel only affects queued
  futures.

## Debugging Async Systems

- `PYTHONASYNCIODEBUG=1 python -X dev app.py` catches un-awaited coroutines and slow
  callbacks.
- "Task was destroyed but it is pending" means a task reference was lost or shutdown did not
  await tasks.
- `asyncio.all_tasks()` and `task.get_name()`/`get_stack()` dump what is stuck.
- Hangs are usually: a lock never released, a queue awaiting without a producer, a shielded
  forever task, or a thread pool exhausted by blocking work.
- Load-test concurrency boundaries, not just throughput: measure p99 under saturation to
  find pool starvation.

## Anti-Patterns

- `time.sleep`, `requests`, `open()`, or a sync DB driver inside `async def`.
- Fire-and-forget `create_task` without a reference or shutdown strategy.
- `except Exception: pass` hiding `CancelledError` side effects or task failures.
- `gather(..., return_exceptions=True)` with results ignored.
- Unbounded queues, unbounded fan-out, unbounded thread pools.
- Long CPU work in a coroutine "because it is fast".
- Blocking locks (`threading.Lock`) acquired inside async code.
- Using `asyncio.get_event_loop()` to create a loop in library code.

## Checklist

- [ ] One documented loop entry point; no nested `asyncio.run`.
- [ ] Structured concurrency (`TaskGroup`/anyio) used for fan-out.
- [ ] Every task tracked, named, and awaited on shutdown.
- [ ] Cancellation re-raised; cleanup uses `shield` where required.
- [ ] Timeouts on all network and external calls, layered per hop.
- [ ] Blocking calls offloaded through `to_thread` or a process pool.
- [ ] Queues bounded; semaphores limit concurrency to pool capacity.
- [ ] Debug mode or blocker enabled in tests; p99 measured under saturation.
