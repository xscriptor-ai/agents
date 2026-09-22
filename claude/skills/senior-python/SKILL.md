---
name: senior-python
description: 'Python 3.12-3.14 reference pack: language core, typing, async and concurrency,
  web frameworks, data layer, testing, tooling and packaging, performance, security
  and observability, deployment. Use when writing, reviewing, debugging, upgrading,
  or shipping non-trivial Python: designing typed APIs with PEP 695 generics, fixing
  asyncio cancellation and structured concurrency, tuning SQLAlchemy 2.0 async sessions
  or Django async ORM, validating runtime data with pydantic v2, hardening FastAPI
  or Litestar services, choosing uv/ruff/hatch tooling, profiling hot paths, packaging
  and publishing distributions, or deploying containers and serverless workers. Use
  when migrating pre-3.12 idioms or troubleshooting free-threaded builds. Optional
  pack: consumers degrade gracefully when it is absent.'
---

# Python

Production Python for senior engineers, current through CPython 3.14. The pack assumes
CPython on Linux/macOS containers or serverless, `pyproject.toml`-based projects, and a
type checker plus linter in CI. It is deliberately opinionated where the ecosystem has
converged and flags where it has not.

## Domain Overview

- **Runtime** — target Python 3.12-3.14. 3.12 is the practical floor for new code
  (PEP 695 generics, per-interpreter GIL groundwork); 3.13 adds free-threading and the
  experimental JIT; 3.14 stabilizes deferred annotations and free-threaded support.
- **Concurrency** — one event loop per process for I/O, threads or processes for CPU,
  structured concurrency (`asyncio.TaskGroup`, anyio, trio) as the default model.
- **Typing** — static types are the primary interface contract; pydantic v2 is the
  runtime validation layer and does not replace static analysis.
- **Ecosystem** — uv for environments and locking, ruff for lint/format, pytest for
  tests, FastAPI/Litestar/Django for HTTP, SQLAlchemy 2.0 or Django ORM for data.
- **Pitfalls** — blocking calls inside async code, unmanaged task lifetimes, mutable
  defaults, implicit `Any`, unpinned lockfiles, and unsafe deserialization remain the
  top recurring defects in review.

## Core Rules (non-negotiable)

1. **Declare the runtime floor** in `pyproject.toml` (`requires-python`) and test the
   oldest and newest supported minor versions in CI.
2. **Public functions and data structures are typed.** Strict checker settings on the
   package; `Any` requires a written reason in a comment or a `cast` at the boundary.
3. **Never block the event loop.** File I/O, DNS, DB drivers, `requests`, `time.sleep`,
   and CPU-bound work must move to async clients, `asyncio.to_thread`, or a process pool.
4. **Own every task.** Create background work with `TaskGroup`, anyio task groups, or an
   explicit set you cancel and await on shutdown. Fire-and-forget tasks are bugs.
5. **Cancellation is control flow.** Never swallow `asyncio.CancelledError`; clean up in
   `finally` or `asyncio.shield` and re-raise.
6. **One lockfile, one resolution.** Commit `uv.lock` (or equivalent) and install from it
   in CI and images; never resolve at deploy time.
7. **Validate at the boundary, trust inside.** Parse external input with pydantic v2 or
   dataclasses at the edge; internal code uses plain typed objects.
8. **Migrations are code.** Schema changes ship with an Alembic/Django migration,
   reviewed for lock duration and reversibility.
9. **No unsafe deserialization.** `pickle`, `marshal`, and `yaml.load` on untrusted input
   are prohibited; use JSON or `yaml.safe_load`.
10. **Benchmark before optimizing.** Profile with py-spy/cProfile/scalene; publish numbers
    with a reproducible benchmark, not intuition.

## Decision Tables

### Runtime target

| Situation | Choice | Notes |
|---|---|---|
| New service, stable libraries | 3.13 or 3.14 | Free-threading off unless profiled and needed |
| Library consumed broadly | 3.10+ floor, test 3.10-3.14 | Verify dependency floors first |
| Legacy service on 3.9/3.10 | Upgrade to 3.12 first | 3.9 is EOL; removals in 3.13 break old deps |
| Heavy CPU parallelism | Processes (or 3.14 free-threaded after benchmarking) | Free-threaded single-thread cost is real |
| Long-lived numeric/ML stacks | Pin the interpreter the framework supports | Verify upstream wheel availability |

### Toolchain

| Need | First choice | Alternatives |
|---|---|---|
| Env + lock + run scripts | uv | pdm, poetry |
| Lint + format | ruff | flake8+black (legacy repos only) |
| Build backend | hatchling | setuptools (legacy), flit, pdm-backend |
| Test runner | pytest | unittest (stdlib interop) |
| Type checker | pyright (strict) | mypy (strict), ty (verify upstream) |
| Pre-commit | ruff + ruff-format hooks | full pre-commit suite |

### Concurrency model

| Workload | Model | Mechanism |
|---|---|---|
| Network I/O fan-out | asyncio structured | `TaskGroup`, `asyncio.timeout` |
| Blocking SDK / DB driver | thread offload | `asyncio.to_thread`, anyio `to_thread` |
| CPU-bound batch | process pool | `ProcessPoolExecutor`, `spawn`/`forkserver` |
| Mixed framework portability | anyio | Works on asyncio and trio backends |
| Shared-state CPU parallelism | processes first | Free-threading only with profiled gains |

### Web framework

| Situation | Choice | Notes |
|---|---|---|
| Typed JSON API, async first | FastAPI | Mature DI, huge ecosystem |
| Typed API, built-in validation/DI/rate limits | Litestar | Strong performance and plugin model |
| Minimal ASGI services | Starlette | Framework internals, small surface |
| Existing Django product | Django 5.x | Async views/ORM where it pays; do not rewrite |
| WSGI-only legacy | Keep WSGI, isolate async workers | Migrate endpoints incrementally |

### Data access

| Situation | Choice | Notes |
|---|---|---|
| Async SQL service | SQLAlchemy 2.0 async | `async_sessionmaker`, explicit eager loads |
| Existing Django models | Django ORM | `select_related`/`prefetch_related`; async variants |
| Columnar analytics, single node | Polars | Lazy + streaming; lower memory than pandas |
| pandas ecosystem / notebooks | pandas 3.x | Copy-on-Write is the default semantics |
| Cache / ephemeral state | Valkey or Redis client library | Always set TTLs and jitter |

## Reference Index

Load only what the task needs. All paths are relative to this file.

| # | Reference | Scope | Load when |
|---|---|---|---|
| 01 | [references/01-language-core.md](references/01-language-core.md) | 3.12-3.14 syntax and semantics: PEP 695, pattern matching, exception groups, f-strings/t-strings, dataclasses vs attrs vs pydantic, free-threading/JIT, removals | Writing new language-level code, upgrading the interpreter, deciding dataclass tooling |
| 02 | [references/02-typing.md](references/02-typing.md) | Strict mypy/pyright, Protocols, PEP 695/696, TypedDict/Unpack, overloads, Self, assert_never, LiteralString, typing_extensions, pydantic v2 validation | Designing typed APIs, fixing checker errors, choosing runtime validation |
| 03 | [references/03-async-concurrency.md](references/03-async-concurrency.md) | asyncio, TaskGroup, cancellation, timeouts, anyio/trio, sync-async boundaries, queues/semaphores/backpressure, threads/processes/free-threading | Debugging hangs, cancellation bugs, choosing a concurrency model |
| 04 | [references/04-web-frameworks.md](references/04-web-frameworks.md) | FastAPI lifespan/DI/WebSockets/testing, Litestar, Starlette, Django 5.x async views/ORM, WSGI vs ASGI, middleware, errors, rate limits | Building or reviewing HTTP services and their tests |
| 05 | [references/05-data-layer.md](references/05-data-layer.md) | SQLAlchemy 2.0 async sessions and transactions, Alembic, pydantic-settings, Django ORM, pandas 3/Polars, caching, pooling, migrations | Schema changes, session bugs, N+1s, caching design |
| 06 | [references/06-testing.md](references/06-testing.md) | pytest layout/config, fixtures, parametrize, async tests, hypothesis, mocking boundaries, Testcontainers, coverage, snapshots, CI parallelism | Writing tests, fixing flaky suites, speeding CI |
| 07 | [references/07-tooling-packaging.md](references/07-tooling-packaging.md) | uv/ruff/hatch/pdm, complete pyproject, lockfiles, src layout, versioning, PyPI publishing, wheels/sdists, monorepos, pre-commit, CI | Project setup, dependency policies, releases and publishing |
| 08 | [references/08-performance.md](references/08-performance.md) | cProfile/py-spy/scalene, tracemalloc/objgraph, allocation patterns, Cython/maturin-pyo3, caching layers, free-threaded perf, pytest-benchmark/asv | Profiling, memory growth, native extension work, benchmarking |
| 09 | [references/09-security-observability.md](references/09-security-observability.md) | Deserialization/injection/secrets, argon2/bcrypt, structlog/loguru, OpenTelemetry, metrics, health checks, error tracking | Security review, logging/metrics design, incident tooling |
| 10 | [references/10-deployment-runtime.md](references/10-deployment-runtime.md) | Containers (slim/distroless), uvicorn/granian/gunicorn, graceful shutdown, probes, limits, serverless, Celery/ARQ/Dramatiq, checklist | Containerizing, sizing workers, shipping to k8s or serverless |

## Loading

- **Installed agent** — `skill({ name: "python" })` in OpenCode; Claude Code reads
  `<skills-dir>/python/SKILL.md`.
- **Orchestrator** — read this file, then inject only the references the task needs.
- **Not installed** — proceed with embedded guidance, state the degraded mode, and do not
  invent pack-only content.
- **Consumers** — reference this pack as `load skill senior-python (optional)`.

## Port

- **Port id** — `skill://senior/python` (version in `metadata.port-version`).
- **Kind** — read-only reference pack; no side effects, no tools required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "python" })` in OpenCode; Claude Code reads `<skills-dir>/python/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers reference it as `load skill senior-python (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major.
