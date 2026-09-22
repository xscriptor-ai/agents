# Performance

Profiling with cProfile/py-spy/scalene, memory analysis with tracemalloc/objgraph, allocation patterns, native extensions, caching layers, free-threaded performance, and benchmarking.

## Method

1. Define the metric: latency percentile, throughput, memory ceiling, or startup time.
2. Reproduce with a realistic workload and a stable environment; record a baseline.
3. Profile before changing code; attribute time and memory to lines/functions.
4. Fix the dominant cost, then re-measure against the baseline.
5. Guard the improvement with a benchmark or regression test; keep it in CI when stable.

Most "slow Python" is one of: blocking I/O, an N+1 query, accidental O(n^2), JSON
(de)serialization, or a hot loop that belongs in NumPy/Polars. Only after ruling those out
does micro-optimization make sense.

## Profiling Tools

| Tool | Type | Overhead | Best for |
|---|---|---|---|
| `cProfile` | Deterministic call profiler | High | Call counts, cumulative attribution, offline analysis |
| `py-spy` | Sampling profiler | Near zero | Production processes, hangs, C extensions, flame graphs |
| `scalene` | Sampling, CPU+GPU+memory | Low-medium | Finding memory allocations and CPU hotspots together |
| `perf` | Native sampling | Low | Native/C extension hotspots, kernel time |
| `memray` | Allocation tracker | Medium | Allocation flame graphs, leak hunting |
| `timeit` | Micro benchmark | n/a | Isolated expression/function timing |

### cProfile

```bash
python -m cProfile -o prof.out -m my_service
python -m pstats prof.out
```

```python
import cProfile
import pstats

with cProfile.Profile() as pr:
    run_workload()

pstats.Stats(pr).sort_stats("cumulative").print_stats(20)
```

- Sort by `cumulative` to find subsystems and `tottime` to find self-time hotspots.
- Overhead distorts I/O-heavy and threaded code; do not trust absolute times from cProfile.
- `--callers`/`--callees` in pstats shows who called the hotspot and from where.

### py-spy

```bash
py-spy top --pid 1234
py-spy dump --pid 1234
py-spy record -o profile.svg --pid 1234 --duration 30 --threads
py-spy record -o profile.svg -- python -m my_service
```

- Attach to running processes without code changes; ideal for production incidents.
- `dump` prints all thread stacks, the fastest way to diagnose a hang or deadlock.
- `--native` includes C extension frames; `--subprocesses` follows multiprocessing pools;
  `--idle` shows tasks waiting instead of only spinning.
- In containers, ptrace must be permitted (`SYS_PTRACE`, `--cap-add=SYS_PTRACE`, or
  `--security-opt seccomp=unconfined` in development only).

### scalene

```bash
scalene --html --outfile prof.html my_service.py
scalene --profile-all --cpu --memory my_service.py
```

- Separates Python versus native time and tracks memory growth sources, including lines that
  allocate most.
- `--profile-all` covers threads and subprocesses; overhead is higher than py-spy.
- Use it when you suspect copy-heavy code (`pandas`, JSON) driving both CPU and RSS.

## Memory Analysis

```python
import tracemalloc

tracemalloc.start(25)
run_workload()
for stat in tracemalloc.take_snapshot().statistics("lineno")[:10]:
    print(stat)
```

- Start early with `PYTHONTRACEMALLOC=25` to capture allocation tracebacks without code
  changes.
- Compare two snapshots (`snapshot2.compare_to(snapshot1, "lineno")`) to isolate growth
  during a specific operation.
- `objgraph.show_most_common_types()` and `show_growth()` find type-level growth;
  `gc.get_referrers`/`get_referents` trace cycles.
- `gc` tuning: raising `gc.threshold` cuts collection pauses but increases peak RSS; disable
  cyclic GC only around measured hot paths and always restore it.
- RSS growth with a flat Python heap points at C extensions, allocator fragmentation, or
  arenas. In containers, `MALLOC_ARENA_MAX=2` reduces glibc arena bloat; `jemalloc`/`tcmalloc`
  via `LD_PRELOAD` often lowers steady-state RSS.
- Use `weakref.WeakValueDictionary` for caches keyed by identity, and break reference
  cycles in objects with `__del__` or long-lived registries.
- Measure deep size with `pympler.asizeof`; `sys.getsizeof` misses referenced objects.

## Allocation and Data Patterns

- `__slots__` (or `@dataclass(slots=True)`) removes `__dict__` overhead: easily 30-50% less
  memory for attribute-heavy objects.
- Prefer generators and iterators for streaming transforms; a list comprehension materializes
  everything.
- Build strings with `"".join(parts)`; repeated `+=` is O(n^2) in the worst case and creates
  garbage.
- Numeric buffers: `array.array`, `numpy.ndarray`, `struct`, or `memoryview` instead of lists
  of Python objects (often 10x+ memory difference).
- Reuse objects in tight loops; avoid creating short-lived temporaries in comprehensions
  that run millions of times.
- `dict`/`set` membership instead of list scans; `collections.deque` for queue ends;
  `heapq` for top-k; `bisect` for sorted lookups.
- `functools.lru_cache`/`cache` for pure functions; note that `cache` is unbounded.

## Vectorization and DataFrames

- NumPy turns per-element Python into C loops: replace explicit loops with array expressions,
  `np.where`, broadcasting, and reductions.
- Polars (lazy + streaming) usually beats pandas for large columnar transforms and uses all
  cores without GIL contention; check [data layer](./05-data-layer.md).
- Avoid `apply`, `iterrows`, and object dtype; they reintroduce Python-level loops.
- Chunk large Parquet/CSV reads; convert once to Arrow and compute in Arrow/Polars before
  moving to pandas or scikit-learn.
- Beware copies: pandas Copy-on-Write (default in 3.x) avoids some, but `astype`, `merge`,
  and `reset_index` still allocate. Profile with scalene.

## Native Extensions

| Tool | Use | Trade-off |
|---|---|---|
| NumPy/Polars | Numeric and tabular hot paths | No new language; limited to vectorizable work |
| Cython | Typed hot loops, C library interop | `.pyx` build step; discipline required |
| mypyc | Compile existing typed modules | Restricted dynamic features; used by mypy itself |
| Rust + PyO3 + maturin | New extension modules, memory safety | Rust toolchain and a release wheel matrix |
| `ctypes`/`cffi` | Bind existing C libraries | `cffi` is easier to maintain; `ctypes` needs no build |

- Move only measured hotspots; cross the native boundary once per batch, not per element.
- Release the GIL inside long native calls (`nogil` in Cython, `Python::allow_threads` in
  PyO3) so threads can run concurrently.
- Keep a pure-Python fallback where possible; build wheels for every supported platform or
  users will compile from source (see [tooling](./07-tooling-packaging.md)).
- mypyc is attractive when the hot code is already strictly typed; expect build and import
  overhead and validate behavior with the full test suite.

## Caching Layers

- Layers, fastest to slowest: in-process memoization (`functools`, `cachetools`), local
  low-latency store (Valkey/Redis), HTTP/CDN, database materialized views.
- Memoize pure functions only; invalidate or version keys for anything mutable.
- Unbounded `functools.cache` on high-cardinality inputs is a memory leak; use `lru_cache`
  with a size or an eviction-aware cache.
- Measure hit rate: a cache below roughly 50% hit rate frequently costs more than it saves
  in memory and invalidation complexity.
- Precompute at startup for immutable configuration; do not recompute per request.
- Remember per-process caches multiply by worker count and are not invalidated across
  replicas.

## Free-Threaded and JIT Performance

- Free-threaded builds (3.13 experimental, 3.14 officially supported) trade single-thread
  throughput for multi-core scaling; per-object locking and biased-reference removal cost
  single-thread speed. Benchmark the actual workload.
- Gains require CPU-bound, thread-parallel work and GIL-independent native extensions; I/O
  code sees little difference.
- The experimental JIT (3.13+) shows modest, workload-dependent gains; treat as research, not
  a production lever. Always verify upstream status and measure.
- When comparing builds, include startup time, memory, and tail latency, not just peak
  throughput. See [language core](./01-language-core.md).

## Benchmarking

```python
def test_parse(benchmark) -> None:
    assert benchmark(parse, "1") == 1
```

- pytest-benchmark for micro benchmarks: run with `--benchmark-autosave`, compare across
  commits with `--benchmark-compare`, fail on regressions with a threshold.
- asv for long-term tracking across commits and machines with regression detection and HTML
  reports; useful for libraries.
- Hygiene: warm up, run multiple rounds, report median/percentiles (not one number), pin
  CPU frequency where possible, isolate from other work.
- CI runners are noisy; treat differences under roughly 10-20% as noise unless using
  dedicated hardware. Never block a PR on a micro benchmark that has not demonstrated
  stability.
- Benchmark the same input shapes/sizes as production; micro benchmarks on tiny inputs
  rarely predict real behavior.

## Anti-Patterns

- Optimizing by intuition or rewriting in C/Rust before profiling.
- Timing single runs with `time.time()` and calling it a benchmark.
- Benchmarking with assertions disabled or debug builds enabled inconsistently.
- Caching everything, with no eviction or invalidation, then debugging memory growth.
- Ignoring I/O and database round-trips while micro-optimizing pure Python.
- Using `eval`/`exec` as a performance trick.
- Assuming `async` is faster for CPU work; it is not.
- Keeping a hot data structure as a list when a set/dict would make it O(1).

## Checklist

- [ ] Performance target defined (p50/p99 latency, throughput, RSS, startup).
- [ ] Baseline recorded with a reproducible workload.
- [ ] Profile captured with py-spy/scalene/cProfile and the hotspot identified.
- [ ] I/O, queries, and serialization ruled out before micro-optimization.
- [ ] Memory measured with tracemalloc/objgraph; leaks and fragmentation addressed.
- [ ] Native extensions only for measured hotspots, with coarse boundaries.
- [ ] Cache hit rate and eviction strategy known.
- [ ] Benchmark committed and stable; regressions gated or tracked.
