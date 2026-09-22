---
name: senior-go
description: 'Go reference pack (1.22-1.26): language core, concurrency, layout and
  tooling, web services, data, testing, profiling, observability, security. Covers
  generics, slices/maps helpers, iterators and range-over-func, error wrapping and
  errors.Join, defer semantics; goroutines, channels, context, errgroup, worker pools,
  leak patterns; cmd/internal layout, modules, go.work, golangci-lint, release; net/http
  routing, chi/echo/gin, gRPC, graceful shutdown; database/sql, pgx, sqlc, migrations;
  table-driven tests, fuzzing, benchmarks, Testcontainers; pprof, trace, GOGC/GOMEMLIMIT;
  slog, OpenTelemetry, Prometheus, crypto, supply chain. Use when writing, reviewing,
  debugging, or migrating non-trivial Go services and libraries, or when current idioms,
  decision tables, and pitfalls are needed.'
---

# Go

Reference pack for production Go in the 1.22-1.26 window. It assumes modern modules, generics, iterators, and `log/slog`, and treats the language as a systems and backend-services tool: explicit errors, owned goroutines, bounded resources, measurable performance. The depth lives in `references/`; load only the files the task needs.

## Version floors

State a floor per feature; never assume a newer toolchain than `go.mod` declares. Verify current point releases upstream.

| Feature | Minimum |
|---|---|
| Modules, `go.mod`/`go.sum` | 1.11+ |
| Generics, `fuzz`, workspaces (`go.work`), `go test -fuzz` | 1.18 |
| `errors.Join`, `context.WithCancelCause` | 1.20 |
| `log/slog`, `min`/`max`/`clear`, toolchain directive, loop-var preview | 1.21 |
| Per-iteration loop vars, `net/http` method+wildcard routing, `math/rand/v2` | 1.22 |
| `iter.Seq`, range-over-func, `unique`, `structs`/`weak` | 1.23 |
| Generic type aliases, `go get -tool` tool directives, `os.Root`, `testing.T.Context`, `b.Loop` | 1.24 |
| `testing/synctest` stable, `http.CrossOriginProtection`, container-aware `GOMAXPROCS` | 1.25 |
| Toolchain and GC evolution, `go fix` modernizers | 1.26 (verify upstream) |

## Non-negotiable core rules

1. **Formatting and vetting gate every change.** `gofmt -l` (or `goimports`) must be empty, and `go vet ./...` clean. CI additionally runs `staticcheck`/`golangci-lint`. [./03-project-layout-tooling.md](./references/03-project-layout-tooling.md)
2. **Every error is handled, wrapped, or deliberately ignored.** Wrap with context using `%w`; test with `errors.Is`/`errors.As`; combine with `errors.Join`. Never compare error strings. Library code returns errors; only `main` and goroutine roots may log-and-exit. [./01-language-core.md](./references/01-language-core.md)
3. **`context.Context` is the first parameter of anything that can block.** Pass it through; never store it in a struct; never pass `nil`; derive cancellation instead of inventing your own done channel. [./02-concurrency.md](./references/02-concurrency.md)
4. **No goroutine without an owner, a stop condition, and a join.** Use `errgroup`/`WaitGroup`, guarantee channel closure, and run the race detector (`go test -race`) in CI. Treat goroutine leaks as bugs. [./02-concurrency.md](./references/02-concurrency.md)
5. **Bound every resource.** HTTP server read/write/idle timeouts, request body limits, DB pool limits, per-call deadlines, channel buffer sizes. Unbounded fan-out and body reads are incidents waiting for load. [./04-web-services.md](./references/04-web-services.md), [./05-data.md](./references/05-data.md)
6. **Interfaces are small and consumer-defined.** Accept interfaces, return concrete types; do not define interfaces before a second implementation exists. Prefer generics for homogeneous containers/algorithms and interfaces for behavior. [./01-language-core.md](./references/01-language-core.md)
7. **Zero values are a design constraint.** Types should be usable at their zero value when practical; guard nil maps, nil channels, and embedded mutexes explicitly. [./01-language-core.md](./references/01-language-core.md)
8. **Tests are deterministic and fast by default.** Table-driven with subtests, `t.Parallel`, no sleeps, injected clocks; integration tests behind build tags or Testcontainers. Measured code is profiled before it is optimized. [./06-testing.md](./references/06-testing.md), [./07-performance-profiling.md](./references/07-performance-profiling.md)
9. **Observability and security are part of the design.** Structured `slog` with request correlation, metrics and traces from day one; secrets from the environment/secret manager, parameterized SQL only, validated input at every trust boundary. [./08-observability-security.md](./references/08-observability-security.md)
10. **Keep the dependency surface minimal and current.** Prefer the standard library and `golang.org/x/*`; run `govulncheck`; pin with modules and verify the checksum database. [./09-ecosystem-2026.md](./references/09-ecosystem-2026.md)

## Decision tables

### Concurrency primitive

| Need | Use | Avoid |
|---|---|---|
| Fire-and-forget with result collection | `errgroup.Group` | bare `go func()` |
| Bounded parallelism | `errgroup.SetLimit` / `semaphore.Weighted` | buffered channel hacks |
| Protect small shared state | `sync.Mutex` / `RWMutex` | `sync.Map` by default |
| Counters/flags | `sync/atomic` typed values | mutex around an int |
| One-time init | `sync.OnceFunc` / `sync.OnceValue` (1.21+) | `init()` side effects |
| Deduplicate concurrent work | `singleflight.Group` | home-grown maps |
| Streaming pipeline | channels + explicit close | shared slices with locks |

### HTTP service stack

| Requirement | Choose | Notes |
|---|---|---|
| Plain JSON API, max control | `net/http` + 1.22 routing | fewest deps, easiest audit |
| Idiomatic middleware ecosystem | chi | thin wrapper over stdlib |
| Batteries-included, large team | echo or gin | pick one per org, don't mix |
| Service-to-service typed RPC | gRPC (`grpc-go`) or Connect | protobuf schema is the contract |
| Realtime browser push | SSE first, WebSocket (`coder/websocket`) when bidirectional | [./04-web-services.md](./references/04-web-services.md) |

### Data access

| Situation | Choose |
|---|---|
| Simple CRUD, hand-written SQL | `database/sql` + `pgx/stdlib` or pgx native |
| SQL-heavy service, type safety | `sqlc` (codegen from SQL) |
| Postgres-specific features | `pgx` v5 native interface |
| Full ORM | `ent` or `gorm` — justify the abstraction cost |
| Cache | Valkey/Redis via `go-redis` or `rueidis`; `singleflight` for stampedes |

### Package placement

| Content | Location |
|---|---|
| Executables (`main` packages) | `cmd/<binary>/` |
| Private implementation | `internal/...` (import-restricted by the toolchain) |
| Intended public API of a library | module root or `pkg/` — only if truly reusable |
| Generated code | next to its source, clearly marked, regenerated in CI |

## Common failure modes (quick scan)

- Goroutine leak: send on a channel nobody reads after the caller left; missing `ctx` check; ticker never stopped.
- `context` stored in a struct or `context.Background()` used inside a request path, breaking cancellation.
- Wrap chains broken by `%v` (loses `errors.Is`) or by re-creating errors with `fmt.Errorf("%s")`.
- Ignored `rows.Close()`/`resp.Body.Close()`, exhausting pools and connections.
- Unbounded request bodies, header sizes, or fan-out; one slow dependency takes down the process.
- `time.Sleep` or polling loops instead of `synctest`, injected clocks, or channels for synchronization.
- Copying structs containing `sync.Mutex`, or taking `&rangeVar` without knowing the loop-var semantics of the module's Go version.
- `init()` performing I/O or registration that makes testing and ordering impossible.
- Dependencies added for one function; orphaned modules left in `go.mod`.

## Reference index

| # | Reference | Scope | Load when |
|---|---|---|---|
| 01 | [01-language-core.md](./references/01-language-core.md) | Generics, slices/maps/cmp helpers, iterators and range-over-func, error wrapping and `errors.Join`, defer/panic semantics, struct tags, embedding, zero values, footguns | Writing or reviewing ordinary Go code; API/error design; unclear language semantics |
| 02 | [02-concurrency.md](./references/02-concurrency.md) | Goroutines, channels, `select`, context, errgroup, semaphore, pools, pipelines, memory model, race detector, leak patterns, concurrent testing | Any code with `go`, channels, locks, timeouts, or background workers |
| 03 | [03-project-layout-tooling.md](./references/03-project-layout-tooling.md) | cmd/internal/pkg layout, modules, go.work, toolchain, tool directives, gopls, linters, govulncheck, generate, build tags, cross-compilation, release | Bootstrapping or restructuring a repo; module/CI/tooling decisions; build and release issues |
| 04 | [04-web-services.md](./references/04-web-services.md) | `net/http` routing, middleware, chi/echo/gin, JSON, SSE/WebSocket, gRPC, graceful shutdown, timeouts, client hardening | Building or reviewing HTTP/gRPC services or clients; framework selection |
| 05 | [05-data.md](./references/05-data.md) | `database/sql`, pgx, sqlc, migrations, transactions, caching, pools, DB testing | SQL, transactions, migrations, caching, pool tuning or DB test strategy |
| 06 | [06-testing.md](./references/06-testing.md) | Table-driven tests, subtests, fuzzing, benchmarks, testify, golden files, httptest, Testcontainers, synctest/goleak | Writing tests, fixing flakiness, adding fuzz/bench targets, choosing test infra |
| 07 | [07-performance-profiling.md](./references/07-performance-profiling.md) | pprof (CPU/heap/block/mutex), trace, escape analysis, allocations, GOGC/GOMEMLIMIT, sync.Pool, benchmark hygiene | A performance question exists; optimizing CPU, memory, latency, or GC |
| 08 | [08-observability-security.md](./references/08-observability-security.md) | slog, OpenTelemetry, Prometheus, secrets, crypto, validation, supply chain, hardening checklist | Adding logs/metrics/traces; handling secrets or user input; security review |
| 09 | [09-ecosystem-2026.md](./references/09-ecosystem-2026.md) | Toolchain timeline, stdlib direction, library landscape, migration notes, senior review checklist | Choosing libraries; upgrading Go versions; final senior review pass |

## Port

- **Port id** — `skill://senior/go` (version in `metadata.port-version`).
- **Kind** — read-only reference pack; no side effects, no scripts, no tools required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "go" })` in OpenCode; Claude Code reads `<skills-dir>/go/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then inject only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers reference it as `load skill senior-go (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major.
