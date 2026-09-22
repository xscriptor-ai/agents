# Ecosystem 2026

Scope: the state of the Go toolchain and library ecosystem in the 1.22-1.26 window, migration guidance, and the senior review checklist. Version-specific claims are floors/ranges — verify current point releases upstream.

## Toolchain timeline

Go ships two releases per year (February/August) and supports the two most recent. A module's `go` directive is now a hard minimum, so the practical floor for most services is the oldest release still receiving security fixes.

| Release | Headline changes for production Go |
|---|---|
| 1.21 | `log/slog`, `min`/`max`/`clear`, `slices`/`maps`/`cmp`, `sync.OnceFunc`, toolchain directive, WASI preview 1 |
| 1.22 | per-iteration loop vars, `net/http` method+wildcard routing, `math/rand/v2`, range-over-int, PGO default support continued |
| 1.23 | range-over-func and `iter.Seq`/`Seq2`, `unique`, `structs`, `weak`, timer changes (unstopped timers collectable), `net/netip` additions |
| 1.24 | generic type aliases, tool directives (`go get -tool`), `os.Root`, `testing.T.Context`/`B.Loop`, weak references, `crypto/mlkem` (verify), improved allocation paths |
| 1.25 | `testing/synctest` stable, `http.CrossOriginProtection`, container-aware `GOMAXPROCS`, flight recorder in `runtime/trace`, `encoding/json/v2` experiment, `slog` additions |
| 1.26 | GC/toolchain evolution, `go fix` modernizers, leak/telemetry improvements — verify upstream |

Ecosystem consequences:

- `math/rand` is auto-seeded (1.20+); global `rand.Seed` is a no-op. Use `math/rand/v2` for non-crypto randomness and `crypto/rand` for anything security-related.
- `io/ioutil` has been gone since 1.16; `os`/`io` equivalents are the only acceptable imports.
- `encoding/json/v2` is still experimental in the 1.25/1.26 window under `GOEXPERIMENT=jsonv2`. Build on v1 APIs until the v2 API is declared stable; keep JSON handling behind small functions to ease the eventual switch ([./04-web-services.md](./04-web-services.md)).
- GC direction is lower-latency collection for small-heap services and better container awareness; `GOMEMLIMIT` remains the operator-facing control ([./07-performance-profiling.md](./07-performance-profiling.md)).
- `go fix` modernizers grow each release; run it on major upgrades and review the diff — it is also an excellent teaching tool for current idioms ([./03-project-layout-tooling.md](./03-project-layout-tooling.md)).

## Standard library direction

- **Iterators everywhere**: `slices`, `maps`, `strings`, `bytes` producer helpers make lazy pipelines first-class. Prefer them to ad-hoc slices when the consumer may stop early ([./01-language-core.md](./01-language-core.md)).
- **Testing**: `synctest` stabilized deterministic concurrency tests; `B.Loop` simplified benchmarks; `T.Context` standardized cancellation. Expect more in `testing` rather than third-party frameworks ([./06-testing.md](./06-testing.md)).
- **HTTP**: stdlib routing now covers method and path parameters; `CrossOriginProtection` addresses CSRF for cookie sessions. The stdlib is a serious default again ([./04-web-services.md](./04-web-services.md)).
- **Security**: `os.Root` removes whole classes of path traversal; ML-KEM and crypto updates follow the post-quantum migration; verify exact package availability per release ([./08-observability-security.md](./08-observability-security.md)).
- **Runtime**: container-aware CPU limits reduce the classic "GOMAXPROCS = host cores" pathology; unstopped timers no longer leak; execution tracing gained a flight recorder for rare events.
- **Compatibility**: `GODEBUG` settings encode per-release behavior changes; read them during upgrades. Never set broad `GODEBUG` overrides as a permanent workaround.

## Library landscape

Web and RPC:

| Purpose | Mainstream choice | Alternatives / notes |
|---|---|---|
| Router/middleware | `chi` (v5) | stdlib `ServeMux`, `echo` v4, `gin` v1 |
| RPC | `grpc-go` | `connectrpc.com/connect` (HTTP-friendly), Twirp |
| GraphQL | `gqlgen` | hand-rolled only for tiny surfaces |
| WebSocket | `github.com/coder/websocket` | `gorilla/websocket` (maintained again) |
| SSE | stdlib | no dependency needed |
| Validation | `go-playground/validator` v10 | hand-written validators often clearer |
| Sessions/auth | `golang.org/x/oauth2`, OIDC libs, `golang-jwt/jwt/v5` | do not hand-roll JWT validation |

Data and messaging:

| Purpose | Mainstream choice | Notes |
|---|---|---|
| Postgres driver | `pgx` v5 | `lib/pq` is maintenance-mode legacy |
| Query generation | `sqlc` | `ent` for graph-heavy domains, `gorm` for pragmatism |
| Migrations | `goose`, `golang-migrate` | Atlas adds declarative diff/lint |
| Cache/client | `go-redis` v9, `rueidis` | Valkey is the license-safe backend |
| Kafka | `franz-go` | `segmentio/kafka-go` also current |
| NATS | `nats.go` | built-in JetStream support |
| Object storage | cloud SDKs (AWS v2, GCS) | `minio-go` for S3-compatible |

Infrastructure and tooling:

| Purpose | Mainstream choice | Notes |
|---|---|---|
| Logging | `log/slog` | zap/zerolog for legacy perf-critical paths |
| Traces/metrics | OpenTelemetry SDK, `client_golang` | collector pipeline |
| HTTP client | stdlib + small retry helper | `go-retryablehttp`, `resty` for convenience |
| Retry/backoff | `cenkalti/backoff`, `avast/retry-go` | hand-rolled jitter also fine |
| CLI | `cobra`, `urfave/cli`, `kong` | stdlib `flag` for small tools |
| Config | `env` parsing + `koanf` | Viper is heavy; 12-factor env first |
| DI | manual constructors | `wire` (codegen) or `fx` for large apps |
| Testing | `testify`, `go-cmp`, `testcontainers-go`, `goleak` | prefer stdlib where sufficient |
| Mocks | `go.uber.org/mock`, `mockery` | hand-written fakes often best |
| Concurrency | `golang.org/x/sync` | semaphore, errgroup, singleflight |
| Errors | stdlib (`%w`, `errors.Join`) | `pkg/errors` deprecated |

Selection rules: prefer stdlib and `golang.org/x/*`; one library per concern per repo; check maintenance activity (commits within the last year, responsive issues, tagged releases); read the license; count transitive dependencies before adding.

## Migration notes

- **From `pkg/errors`**: replace `Wrap`/`Wrapf` with `fmt.Errorf("%w")`, `Cause` with `errors.Is`/`As`, `MultiError` with `errors.Join`.
- **From `lib/pq`**: move to `pgx` v5 (native or `stdlib` adapter). Watch `$1` placeholder compatibility (both support it) and `pq` type specifics.
- **From `nhooyr.io/websocket`**: the project moved to `github.com/coder/websocket`; import path is the only change.
- **From dep/vendor-only**: modules with `go.mod`; vendor remains supported but is a deliberate policy.
- **Loop variables**: code with a `go` directive below 1.22 keeps the old capture semantics. Upgrading the directive silently changes behavior — audit goroutine closures and `&loopVar` uses.
- **`math/rand`**: replace `rand.Seed` calls (no-ops) and migrate hot paths to `math/rand/v2`; never use either for tokens.
- **`GODEBUG`**: each toolchain documents behavior changes; after upgrades, test with defaults first, set overrides only with an issue tracking removal.
- **Build tags**: `// +build` is gone; use `//go:build`.
- **`io/ioutil`**, `bytes.Title`, `strings.Title`, and old `net/...` helpers are deprecated or removed; `go fix` and staticcheck flag them.
- **Containers**: rebuild images with the current toolchain; verify `GOMAXPROCS` behavior under CPU quotas and set `GOMEMLIMIT` for memory limits ([./07-performance-profiling.md](./07-performance-profiling.md)).

## Upgrade checklist

- [ ] Read the release notes and `GODEBUG` history for every skipped version.
- [ ] Bump the `go` directive in a dedicated PR; run `go fix`/`go vet`/staticcheck and review.
- [ ] Run `go test -race ./...`, integration tests, and a load test before rollout.
- [ ] Rebuild all Docker images and CI tool pins with the new toolchain.
- [ ] Re-measure p99 latency, allocations, and GC after the upgrade; publish a profile diff.
- [ ] Revisit `tool`/`tools.go` versions and regenerate code.
- [ ] Re-run `govulncheck` and update the SBOM.

## Senior review checklist

Language and API:

- [ ] Errors wrapped with operation context; callers branch with `errors.Is`/`As`.
- [ ] Context first parameter, canceled on all paths, never stored.
- [ ] Generics used only where they reduce real duplication; interfaces small and consumer-defined.
- [ ] Public API documented; zero values sane; no typed-nil interface returns.
- [ ] No goroutine without owner/stop/join; bounded concurrency for external calls.

Architecture and tooling:

- [ ] Package layout reflects actual boundaries; no `util` dumping ground.
- [ ] Module floors and toolchain pinning deliberate; `go mod tidy -diff` clean; tools pinned.
- [ ] CI runs format, vet, staticcheck/lint, race tests, govulncheck; generated code verified.
- [ ] Build tags and cross-compilation matrix covered by CI.

Services and data:

- [ ] Server/client timeouts, body limits, graceful shutdown, connection reuse.
- [ ] Queries parameterized, pooled, context-bound; migrations reversible and lock-aware.
- [ ] Caches bounded, versioned, jittered, and non-authoritative.
- [ ] Structs tested at memory boundaries: fakes where practical, real engines for semantics.

Operations:

- [ ] Structured logs with correlation; redaction; no secrets in logs or errors.
- [ ] Traces/metrics exported with bounded cardinality and shutdown flush.
- [ ] `GOMEMLIMIT` set below container limit; pools and queues monitored.
- [ ] Supply chain: SBOM, signatures, pinned actions, minimal dependencies.
- [ ] Runbooks for the failure modes this service actually has (pool exhaustion, dependency outage, queue backlog).

## Common pitfalls, one line each

- Typed nil in an interface, checked with `== nil`.
- `%v` on an error where `%w` was needed, breaking `errors.Is`.
- Goroutine leak via an unread result channel.
- `time.After` in a loop.
- `WriteTimeout` killing SSE and long downloads.
- `SELECT *` into structs; schema drift at runtime.
- Unbounded label values in metrics.
- `math/rand` for tokens; `InsecureSkipVerify` in a service client.
- Unbounded request bodies and header sizes.
- Caching authorization decisions without invalidation.
- `go.mod` `go` directive bumped without testing capture semantics.
- `replace` directives relied on for published behavior.
- Linters and generators pinned to `@latest`.
- Golden files regenerated without review.
- Profiling guessed instead of measured.
