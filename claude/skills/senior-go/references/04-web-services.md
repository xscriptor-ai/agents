# Web Services

Scope: `net/http` routing and middleware, framework selection, JSON and streaming transports, gRPC, graceful shutdown, server/client timeouts, and request hardening.

## Routing with net/http (1.22+)

The standard `ServeMux` supports method and wildcard patterns, removing the main reason to adopt a router for straightforward APIs.

```go
mux := http.NewServeMux()
mux.HandleFunc("GET /healthz", health)
mux.HandleFunc("GET /v1/orders/{id}", getOrder)
mux.HandleFunc("POST /v1/orders", createOrder)
mux.HandleFunc("GET /v1/files/{path...}", serveFile)

func getOrder(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	...
}
```

- Pattern grammar: `METHOD /path/{name}` and `{name...}` for trailing segments; a pattern without a method matches all methods.
- Precedence is by specificity: literal segments beat wildcards, and `{$}` matches only the exact path (distinguishing `/x` from `/x/`). Panics at registration time on conflicts — a good thing.
- `PathValue` returns `""` for missing names; validate before use.
- Middleware is plain `func(http.Handler) http.Handler`; chain in `main`, order matters (recovery outermost, then request ID, logging, auth, rate limit, handler).

```go
func recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				slog.ErrorContext(r.Context(), "panic", "err", rec,
					"stack", string(debug.Stack()))
				http.Error(w, "internal error", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}
```

## Framework decision table

| Situation | Choice | Rationale |
|---|---|---|
| Straightforward JSON API, no deps | stdlib `net/http` + 1.22 routing | smallest audit surface, zero upgrade treadmill |
| Need middleware ecosystem, sub-routers, URL params today | `chi` | thin, stdlib-compatible `http.Handler` |
| Large team wants built-in binding/validation | `echo` or `gin` | be consistent org-wide; do not mix routers across services |
| Typed service-to-service RPC | `grpc-go` (or Connect) | protobuf contract, streaming, codegen |
| GraphQL | `gqlgen` | schema-first codegen |
| Realtime browser updates | SSE; WebSocket only when bidirectional | SSE survives proxies, uses plain HTTP |

The framework is a small part of the service. Ports/adapters around the router keep handlers testable and make framework swaps rare. Avoid `context` in framework-specific types leaking into domain code.

## Middleware mechanics

- Wrap `http.ResponseWriter` carefully: hiding `http.Flusher`, `http.Hijacker`, `io.ReaderFrom`, or `Unwrap()` breaks SSE, WebSockets, and `io.Copy` fast paths. Use `http.NewResponseController(w)` (1.20+) to reach deadlines/flush/hijack through wrappers.
- Panic recovery must run outermost so no request escapes unlogged; log with request ID and stack, then return a generic body.
- Request ID: accept inbound `X-Request-ID` only after validation, else generate; put it in `context` and in `slog` via a handler attribute ([./08-observability-security.md](./08-observability-security.md)).
- Auth middleware should attach an immutable principal to context and fail closed. Never trust headers alone from the public internet.
- CSRF: for cookie-based browser sessions, use SameSite cookies plus token validation; Go 1.25+ offers `http.CrossOriginProtection` (verify upstream) as origin-based defense.
- Rate limiting belongs in middleware with bounded memory (token bucket per key) or at the gateway; an unbounded `map[string]*limiter` is a memory leak.
- CORS: explicit allowlists; wildcard plus credentials is invalid and dangerous.

## JSON handling

```go
type createReq struct {
	Name string `json:"name"`
}

func createOrder(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()

	var req createReq
	if err := dec.Decode(&req); err != nil {
		writeProblem(w, http.StatusBadRequest, "invalid json", err)
		return
	}
	if dec.More() {
		writeProblem(w, http.StatusBadRequest, "trailing data", nil)
		return
	}
	...
}
```

- `DisallowUnknownFields` for first-party clients; leave it off for forward compatibility with third parties, and always reject trailing data for single-object endpoints.
- Bound bodies everywhere (`MaxBytesReader`), and set `Content-Type: application/json` on responses.
- Prefer `json.Decoder` streaming for large payloads; decode timestamps as `time.Time` with RFC 3339 conventions, not strings.
- Error responses: stable machine-readable shape (`{"error":{"code":"...","message":"..."}}`), no internal error text; log the detailed error server-side.
- `encoding/json/v2` is under experiment in recent toolchains (`GOEXPERIMENT=jsonv2`); do not depend on it in production until stable — verify upstream. `json.RawMessage` and `json.Number` remain the escape hatches.
- Avoid `map[string]any` for domain data; define structs for contracts and validate them explicitly.

## Streaming: SSE and WebSockets

SSE for one-way server push:

```go
w.Header().Set("Content-Type", "text/event-stream")
w.Header().Set("Cache-Control", "no-cache")
rc := http.NewResponseController(w)
for ev := range events {
	if _, err := fmt.Fprintf(w, "data: %s\n\n", ev); err != nil {
		return
	}
	if err := rc.Flush(); err != nil {
		return
	}
}
```

- SSE needs a write deadline strategy: `WriteTimeout` on the server kills long streams, so set `WriteTimeout: 0` and use `ResponseController.SetWriteDeadline` per write or heartbeat.
- Send periodic comments (`: ping`) to keep intermediaries from closing idle connections; watch for client disconnects via `r.Context().Done()`.

WebSockets:

- Prefer `github.com/coder/websocket` (maintained successor to `nhooyr.io/websocket`) for context-aware APIs and simpler concurrency rules; `github.com/gorilla/websocket` is maintained again and widely deployed. Verify current status upstream; see [./09-ecosystem-2026.md](./09-ecosystem-2026.md).
- Enforce `SetReadLimit`, origin checks (`OriginPatterns`/`CheckOrigin`), and ping/pong deadlines. Exactly one concurrent reader and one writer per connection; serialize writes.
- Treat WebSocket messages as untrusted input: validate size, schema, and rate. Close with proper codes on auth expiry.

## gRPC

- Define `.proto` contracts, generate with `buf` (linting/breaking-change detection) and `protoc-gen-go`/`protoc-gen-go-grpc`. Generated code is committed per [./03-project-layout-tooling.md](./03-project-layout-tooling.md).
- Server options: `grpc.MaxRecvMsgSize`/`MaxSendMsgSize` bounded, keepalive enforcement (`keepalive.EnforcementPolicy`) to reject abusive clients, and health service (`grpc_health_v1`) plus reflection for tooling.
- Interceptors mirror HTTP middleware: recovery, logging, auth, metrics, and **deadline propagation** (the client's deadline is in the incoming context; respect it).
- Map domain errors to `codes.NotFound`/`InvalidArgument`/`Internal`; never leak internal messages. `status.Error`/`status.FromError`.
- Plaintext vs TLS: use `credentials.NewTLS` or mTLS inside the cluster; `insecure` only on loopback/dev.
- Connect (`connectrpc.com/connect`) is a strong alternative when you want HTTP/JSON compatibility and gRPC semantics without the gRPC transport stack; evaluate before committing.
- Client-side: set per-call timeouts (`context.WithTimeout`), retry only idempotent methods with backoff and jitter, and configure the resolver/balancer (`round_robin` for headless services).

## Graceful shutdown

```go
ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
defer stop()

srv := &http.Server{
	Addr:              ":8080",
	Handler:           mux,
	ReadHeaderTimeout: 5 * time.Second,
	ReadTimeout:       30 * time.Second,
	WriteTimeout:      30 * time.Second,
	IdleTimeout:       120 * time.Second,
	MaxHeaderBytes:    1 << 20,
}

go func() {
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		slog.Error("serve", "err", err)
		stop()
	}
}()

<-ctx.Done()
stop()

shutdownCtx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
defer cancel()
if err := srv.Shutdown(shutdownCtx); err != nil {
	slog.Error("shutdown", "err", err)
}
```

- `Shutdown` stops listeners, closes idle connections, and waits for active requests until the context expires; then `Close` can force-terminate.
- Drain order: stop accepting, finish in-flight requests, stop background workers, flush telemetry, close DB pools. `srv.RegisterOnShutdown` and `sync.WaitGroup` for worker drain.
- Kubernetes: readiness fails first (pod removed from endpoints), liveness stays up while draining; `terminationGracePeriodSeconds` must exceed the shutdown deadline.

## Timeouts and limits

Server:

| Setting | Purpose | Guidance |
|---|---|---|
| `ReadHeaderTimeout` | Slowloris protection | always set; a few seconds |
| `ReadTimeout` | Whole request including body | set; raise for uploads via `ResponseController.SetReadDeadline` |
| `WriteTimeout` | Whole response | set for typical APIs; disable for SSE/streaming and use per-write deadlines |
| `IdleTimeout` | Keep-alive reuse | > load balancer idle timeout |
| `MaxHeaderBytes` | Header bomb defense | default 1 MB; lower if proxies bound it |
| `http.MaxBytesReader` | Body size | per endpoint |
| handler context timeout | Dependency budget | shorter than client deadline |

Client hardening:

```go
client := &http.Client{
	Timeout: 10 * time.Second,
	Transport: &http.Transport{
		MaxIdleConns:        100,
		MaxIdleConnsPerHost: 10,
		IdleConnTimeout:     90 * time.Second,
	},
}
```

- Never use `http.DefaultClient` in production: no timeout, shared mutable state, easy to hijack via `http.DefaultTransport` tweaks from a dependency.
- Always close and drain response bodies (`io.Copy(io.Discard, resp.Body)` before `Close` when reusing the connection is desired).
- Retries: only idempotent calls, capped attempts, exponential backoff with jitter, and respect `Retry-After`. Do not retry on context cancellation.
- SSRF: do not fetch user-supplied URLs without allowlisting hosts/schemes and blocking link-local/metadata ranges ([./08-observability-security.md](./08-observability-security.md)).

## Anti-patterns

- Business logic in handlers; handlers should decode, validate, call a service, and encode.
- `http.Error` with internal error strings; stack traces in responses.
- Missing timeouts on either side; `WriteTimeout` set while serving SSE.
- Global mutable `http.DefaultClient`/`DefaultServeMux` shared across packages.
- Reading unbounded bodies or ignoring `r.Context()` cancellation in long queries.
- CORS wildcard with credentials, permissive WebSocket origins, unvalidated `Host`/`X-Forwarded-*` headers.
- Retry loops without backoff or idempotency; logging every request twice (middleware plus handler).
- Health endpoints that check downstream dependencies deeply and flap under partial outages.

## Review checklist

- [ ] Routing uses method patterns with explicit validation of `PathValue`.
- [ ] Middleware order documented; recovery outermost; response wrapper preserves interfaces via `ResponseController`.
- [ ] All server timeouts set and compatible with streaming endpoints.
- [ ] Body size, header size, and per-handler context deadlines bounded.
- [ ] Structured error responses with stable codes; internal details only in logs.
- [ ] Graceful shutdown drains HTTP, workers, and pools within the platform grace period.
- [ ] Client has timeout, pooled transport, retry policy, and body handling.
- [ ] Transports (SSE/WebSocket/gRPC) enforce limits, heartbeats, and auth.
