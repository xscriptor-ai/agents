# Observability and Security

Scope: structured logging with `slog`, OpenTelemetry traces/metrics/logs, Prometheus instrumentation, secret handling, applied crypto, input validation at trust boundaries, and supply-chain controls.

## Structured logging with slog

`log/slog` (1.21+) is the standard. Configure one handler at startup and pass `*slog.Logger` explicitly; do not use the global default in library code.

```go
handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
	Level: slog.LevelInfo,
})
logger := slog.New(handler)
slog.SetDefault(logger)

logger.InfoContext(ctx, "order created",
	slog.String("order_id", id),
	slog.Int("items", n),
	slog.Duration("latency", d),
)
```

- Levels: Debug for diagnostics, Info for business events, Warn for degraded-but-working, Error for failed operations needing action. Avoid Fatal (it calls `os.Exit`); let `main` decide.
- Use `LogAttrs`/typed attrs on hot paths to avoid `any` boxing; `Info("msg", "k", v)` is fine for cold paths.
- Groups (`logger.WithGroup("http")`) structure nested payloads; `logger.With(...)` creates request-scoped child loggers.
- Dynamic levels: `slog.LevelVar` lets a config endpoint or SIGHUP change verbosity at runtime (`handler.Level` behind `LevelVar`).
- Request correlation: put a request ID (and trace ID once OTel is wired) in context and attach it in a handler wrapper so every line carries it. Extract with a helper that tolerates a missing value.
- Redaction: secrets, tokens, passwords, PII must never reach logs. Add a `ReplaceAttr` hook that drops/renames sensitive keys, and never log raw request bodies.
- Log destinations are append-only streams: no multi-line stack traces in JSON fields without escaping; empty `error` values (`err=nil`) are noise.
- `slog` bridges: `slog.SetDefault` propagates to `log`; OTel's `otelslog` bridge sends records to the collector if you centralize there.

## OpenTelemetry

OTel is the vendor-neutral standard; the Go SDK plus OTLP exporter is the default pipeline.

```go
res, _ := resource.Merge(resource.Default(),
	resource.NewWithAttributes(semconv.SchemaURL,
		semconv.ServiceName("orders"),
		semconv.DeploymentEnvironmentName("prod"),
	))

tp := trace.NewTracerProvider(
	trace.WithBatcher(otlptracehttp.NewClient()),
	trace.WithResource(res),
	trace.WithSampler(trace.ParentBased(trace.TraceIDRatioBased(0.05))),
)
defer tp.Shutdown(ctx)
otel.SetTracerProvider(tp)
otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
	propagation.TraceContext{}, propagation.Baggage{},
))
```

- Traces: create spans with meaningful names (`GET /orders/{id}`, `db.query orders`) and attributes (semantic conventions); avoid `%v` user data in span names — it explodes cardinality.
- Propagation: W3C `traceparent`/`baggage` for HTTP; make sure every outbound client and inbound server is instrumented, or the trace breaks at service boundaries.
- Instrumentation: `otelhttp` for `http.Handler`/`http.Client`, `otelgrpc` interceptors, `otelsql`/pgx tracing, and manual spans around domain operations.
- Sampling: head-based (parent-based ratio) is cheap; tail-based sampling belongs in the collector when you need error/latency-biased retention. Never sample away all errors in a low-traffic service.
- Metrics: OTel metrics API for portable signals; export OTLP to the collector. Keep label sets bounded.
- Collector is the right aggregation point: application sends OTLP to a local sidecar/daemonset; the collector handles batching, retries, sampling, and vendor routing.
- Shutdown must flush: `Shutdown` with a timeout during graceful stop ([./04-web-services.md](./04-web-services.md)), or you lose the last spans.

## Prometheus

`prometheus/client_golang` remains the ecosystem standard for Go metrics; many teams run both OTel (traces/logs) and Prometheus (metrics) with a collector bridge.

```go
var (
	requests = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "HTTP requests processed.",
	}, []string{"method", "route", "status"})

	latency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Buckets: prometheus.DefBuckets,
	}, []string{"method", "route"})
)

func init() {
	prometheus.MustRegister(requests, latency)
}
```

| Type | Use for | Watch out |
|---|---|---|
| Counter | monotonically increasing events | never reset; use `_total` suffix |
| Gauge | current value (connections, queue depth) | can go up and down; don't fake a counter |
| Histogram | latency/size distributions | bucket choice drives accuracy; `_bucket`/`_sum`/`_count` |
| Summary | quantiles without aggregation across instances | client-side quantiles are not aggregatable — prefer histograms |
| Native histograms | high-resolution, low cardinality | support varies; verify upstream |

- Cardinality is the number one operational risk: label values come from a bounded set (`route` template, status class, not raw URL or user ID). Never label with unbounded IDs.
- Use the default registry only if you control the process; custom registries are cleaner for libraries. `promhttp.Handler()` mounts `/metrics`.
- Export the standard runtime collectors (goroutine count, GC, memory) plus `process_*`; these catch leaks and GC issues.
- Avoid the Pushgateway except for batch jobs; it breaks counter semantics and stale-marking.
- Instrument at the boundary (middleware/interceptor) and at dependency edges (DB, cache, queue) with the same label vocabulary.
- See [./07-performance-profiling.md](./07-performance-profiling.md) for GC/alloc metrics that belong on a dashboard.

## Correlation

- One ID to bind them all: accept `traceparent` (W3C) and a human-readable request ID; log both; put the trace ID in error responses for support.
- Logs at boundaries: inbound request (after auth, never the body), outbound call with target and latency, state transitions, and errors with operation + wrapped context.
- Do not double-log: middleware logs completion; handlers log business events; no `fmt.Println` anywhere.
- Metrics answer "how much/how many", traces answer "where", logs answer "what exactly". Do not try to get traces from logs or vice versa.

## Secrets

- Source: environment injected by the platform secret manager, or a secrets API (Vault, cloud KMS/Secrets Manager). Files are acceptable when mounted read-only and permissioned (`0400`).
- Never in: source, `go.mod`/sum, Docker images, build args, CI logs, committed `.env`, test fixtures, or error messages.
- Read once at startup into a dedicated config type; pass explicitly; do not read env vars at request time.
- Rotation must not require code changes: support two active credentials (current + previous) during rollout, and reload on signal where the secret manager allows.
- Redaction: central slog `ReplaceAttr`; scrub URLs (query params carry tokens), headers, and stack traces before external reporting.
- Scanning: `gitleaks`/`trufflehog` in pre-commit and CI; `govulncheck` for code; secret scanning of container layers in CI.
- Least privilege: one credential per service and environment; database users scoped to the schema and operations actually used.

## Crypto in Go

- Randomness: `crypto/rand` for anything security-related. `math/rand` (and `math/rand/v2`) is not cryptographic; using it for tokens is a vulnerability.
- Symmetric encryption: AES-GCM (`crypto/aes` + `crypto/cipher`) or ChaCha20-Poly1305 (`golang.org/x/crypto/chacha20poly1305`). Always unique nonces; never reuse a nonce with the same key. Prefer an AEAD with associated data for context binding.
- Signatures: Ed25519 for new designs (`crypto/ed25519`), ECDSA P-256 for ecosystem compatibility, RSA only where required. Verify with `crypto/x509`.
- Password storage: Argon2id (`golang.org/x/crypto/argon2`), bcrypt, or scrypt with tuned cost; store parameters and salt with the hash; migrate on successful login. Never hash with MD5/SHA1/SHA256 alone.
- HMAC: `crypto/hmac` with `sha256`/`sha512`; compare with `hmac.Equal` or `crypto/subtle.ConstantTimeCompare`.
- Deprecated/banned: MD5, SHA1 for signatures, DES/3DES, RC4, ECB mode, custom crypto, `crypto/cipher` stream ciphers without authentication.
- TLS: `MinVersion: tls.VersionTLS12` (prefer 1.3), proper certificate verification, `RootCAs` from system pools, client certificates for mTLS. Never `InsecureSkipVerify: true` outside local tests.
- JWT: validate signature **and** `alg` (reject `none`/algorithm confusion), `iss`, `aud`, `exp`/`nbf` with small leeway. Use a maintained library (`github.com/golang-jwt/jwt/v5`) and pin the expected algorithm explicitly.
- Key management: keys from KMS/secret manager, per-environment, versioned; support rotation; encrypt-then-sign only for specific protocols that require it.

## Input validation at trust boundaries

Every byte from a network, file, or queue is untrusted. Validate once at the boundary, convert to domain types, then trust internally.

| Threat | Defense |
|---|---|
| SQL injection | parameterized queries only; identifier allowlists ([./05-data.md](./05-data.md)) |
| Command injection | `exec.CommandContext` with argument slices; never a shell; allowlist binaries |
| Path traversal | `filepath.Clean` + prefix check, or `os.Root` (1.24+) for constrained file access |
| SSRF | allowlist schemes/hosts/ports; block link-local/metadata IPs; disable redirects or re-validate each hop |
| XXE / XML bombs | `encoding/xml` with `Decoder` settings; prefer JSON; cap entity/decode sizes |
| Decompression bombs | `io.LimitReader` around gzip/zlib with a hard cap |
| Template injection | `html/template` for HTML output; never `text/template` with user data into HTML |
| JSON depth/size abuse | `MaxBytesReader`, decode depth/size limits, streaming decode |
| HTML/JS injection | contextual escaping (`html/template`), strict CSP, no `template.HTML` on user input |
| Log injection | structured logging; escape newlines; never concatenate raw input into log messages |
| Deserialization | no `gob`/`encoding/gob` across trust boundaries; validate protobuf/JSON explicitly |
| File uploads | size caps, content sniffing, store outside webroot, random names, virus scan where applicable |
| Race-based TOCTOU | operate on handles, not re-resolved paths; `os.Root` mitigates |
| Unbounded work | limits on regex complexity, iteration counts, page sizes, and request fan-out |

Validation rules:

- Validate type, length, range, format, and cross-field consistency; reject rather than sanitize silently.
- Use explicit allowlists. Do not rely on blocklists or "escape everything" as a strategy.
- Reject unknown fields on internal APIs; bounds-check integers before conversion (overflow is silently wrapping).
- Return 4xx for client errors without echoing internal state; log details server-side with the request ID.
- Encode output for its destination: JSON encoder for JSON, `html/template` for HTML, parameterized statements for SQL.

## Supply chain

- `govulncheck ./...` in CI and before release — it reports only vulnerabilities reachable from your code.
- Keep modules on the checksum database (`GOSUMDB=sum.golang.org` default). `GOFLAGS=-mod=readonly`; verify with `go mod verify`.
- Review dependency additions: `go mod why`, license, maintenance status, release cadence, and transitive weight. Prefer `golang.org/x/*` and stdlib.
- Generate an SBOM (`syft`) per release and attach it; sign artifacts and images with `cosign`; publish checksums.
- Renovate/Dependabot for version updates with `go test` gates; group stdlib-adjacent updates.
- CI hardening: pin action versions by SHA, least-privilege tokens, no long-lived cloud credentials (OIDC), protect the module proxy from cache poisoning by using the public checksum DB.
- Do not `GONOSUMDB=*` or `GOFLAGS=-insecure` to "make it work"; fix the credentials.

## Hardening checklist

- [ ] pprof/debug endpoints bound to localhost/admin port; not exposed by ingress.
- [ ] Server timeouts and body/header limits set ([./04-web-services.md](./04-web-services.md)).
- [ ] Structured logs with request/trace correlation; redaction hook active; no secrets or bodies logged.
- [ ] OTel provider configured with resource attributes, propagation, flushing on shutdown.
- [ ] Prometheus metrics bounded in cardinality; runtime/GC collectors exported.
- [ ] Secrets injected, rotated, and never committed; scanners in CI.
- [ ] `crypto/rand` for tokens; AEADs with unique nonces; quotas on password hashing cost.
- [ ] All queries parameterized; paths/commands/URLs validated at the boundary.
- [ ] govulncheck, SBOM, signed artifacts, pinned CI actions and tool versions.
- [ ] Error responses generic; panics recovered and logged with context; no stack traces to clients.
