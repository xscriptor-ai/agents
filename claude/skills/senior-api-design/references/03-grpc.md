# gRPC

Protobuf service and message style, wire compatibility, streaming patterns, deadlines and
cancellation, the canonical error model, browser access via Connect/gRPC-Web, and HTTP gateways.

## Proto Style Guide

- **One service per file** for public APIs; group messages with the service that owns them.
- **Package naming**: reverse-DNS plus version, e.g. `package acme.orders.v1;`. The version
  lives in the package, so files can coexist during migration.
- **File names**: `lower_snake_case.proto`, one top-level entity family each
  (`order_service.proto`, `order_types.proto`).
- **Message names**: `PascalCase`; request/response types named after the RPC
  (`CreateOrderRequest`, `CreateOrderResponse`) and defined in the same file.
- **Field names**: `lower_snake_case`; field numbers are never reused.
- **Enums**: `PascalCase` type, `SCREAMING_SNAKE_CASE` values, a zero value of
  `<ENUM_NAME>_UNSPECIFIED`, and the type name prefix on every value to avoid C++ scope clashes.
- **Reserve for breaking changes**: `reserved 3, 5 to 8; reserved "old_field";` immediately when
  removing a field. Never remove without reserving.
- **Optional presence**: prefer explicit `optional` (proto3 field presence) for scalar fields
  where absence differs from zero. Wrap messages/oneofs only when needed.
- **googleapis types**: `google.protobuf.Timestamp` for instants, `Duration` for spans,
  `google.type.Money` for currency, `google.type.Date` for dates, `FieldMask` for partial
  updates, `google.rpc.Status` for rich errors. Do not hand-roll equivalents.
- **Editions**: protobuf editions (2023+) replace the `syntax` toggle with explicit features;
  adopt it when your toolchain supports it end to end, otherwise stay on proto3 (verify the
  current edition and tooling support upstream).
- **Comments become docs**: every service, RPC, message, field, and enum value gets a comment
  `//` that generators can surface to clients.

```protobuf
// Orders service (v1).
package acme.orders.v1;

import "google/protobuf/timestamp.proto";
import "google/type/money.proto";

service OrderService {
  // Creates an order; idempotent when idempotency_key is set.
  rpc CreateOrder(CreateOrderRequest) returns (CreateOrderResponse);
  // Streams orders as they are created.
  rpc WatchOrders(WatchOrdersRequest) returns (stream Order);
}

message Order {
  string id = 1;
  string customer_id = 2;
  google.type.Money total = 3;
  OrderStatus status = 4;
  google.protobuf.Timestamp created_at = 5;
}

enum OrderStatus {
  ORDER_STATUS_UNSPECIFIED = 0;
  ORDER_STATUS_PENDING = 1;
  ORDER_STATUS_PAID = 2;
}
```

**Anti-patterns**

- Changing a field's type or number ("it is only used internally") — both break the wire.
- Reusing a deleted field number for a new meaning.
- A single `api.proto` with every service and a `Common` package of unrelated messages.
- Using `int32` for money or `string` for timestamps.

## Compatibility Rules

The wire format is forever once shipped. Treat every published `v1` as immutable except for
additive changes.

| Change | Breaking? | Notes |
|---|---|---|
| Add a new field | No | Old readers ignore it; new readers see default |
| Add a new RPC | No | Servers may return UNIMPLEMENTED for old deployments |
| Add an enum value | Usually no | Old clients must tolerate unknown values; document it |
| Remove/rename a field | Yes | Reserve number and name |
| Change field type/number | Yes | Wire-incompatible |
| Move a field into/out of `oneof` | Yes | Changes presence and wire layout |
| Change `optional` to repeated (or vice versa) | Yes | Different wire types |
| Rename a package/message | Yes | Full name is part of the type URL for Any |
| Add to a `oneof` | Careful | Old clients treat unknown variant as unset; usually safe, verify |
| Delete an RPC/method | Yes | Deprecate first, monitor, then remove |

- **`buf breaking` (or equivalent) in CI** compares against the published baseline and fails on
  breaking changes. Store the baseline (Buf Schema Registry or a git tag) and pin it.
- **Unknown fields are preserved**: do not rely on them for security decisions, but do not
  strip them in proxies (gRPC/HTTP transcoding handles this).
- **JSON mapping is part of the contract** for gateway users: field names snake_case by
  default, `json_name` overrides, enums as strings, `int64`/`uint64` as strings. Changing a
  field breaks generated JSON clients too.

## Streaming Patterns

| Pattern | Signature | Use when | Beware |
|---|---|---|---|
| Unary | `rpc F(Req) returns (Resp)` | CRUD, short operations | Default; prefer it |
| Server streaming | returns `stream Resp` | Subscriptions, large result sets, tailing | Client must drain or cancel; flow control |
| Client streaming | `rpc F(stream Req) returns (Resp)` | Uploads, batched ingestion | Server must bound memory; partial failure semantics |
| Bidirectional | `rpc F(stream Req) returns (stream Resp)` | Sessions, real-time negotiation | Ordering, heartbeats, half-close handling |

- **Message size**: keep individual messages small (well under the 4 MB default receive limit;
  many deployments configure 1-4 MB). Stream large payloads in chunks rather than raising limits
  blindly.
- **Flow control is per-stream** (HTTP/2 windows). A slow consumer applies backpressure to the
  sender; do not buffer unboundedly in the handler.
- **Client-streaming semantics**: define what happens on malformed mid-stream messages
  (abort the stream vs skip) and how the server acknowledges progress.
- **Server-streaming lists**: streaming is not a substitute for pagination. For finite result
  sets, a paginated unary RPC is more retryable and cacheable; use streaming for live feeds.
- **Bidirectional protocols**: define a message envelope with a `oneof` for types, a
  client-initiated heartbeat or keepalive, and explicit half-close rules.
- **Idempotency**: streams are retried from the beginning at the connection level; include a
  resume token or client sequence numbers if resumability matters (see
  [errors](./06-errors.md)).

## Deadlines and Cancellation

- **Every call sets a deadline.** Servers should reject or clamp absurd deadlines; clients
  should never rely on infinite waits. Propagate the remaining deadline to downstream calls so
  the whole chain fails at the same time.
- **Cancellation propagates** through context: when a client disconnects, the server context is
  cancelled; handlers must stop work and release resources (database queries, locks, upstream
  calls).
- **Do not swallow cancellation**: treat it as control flow and clean up in deferred/finally
  handlers (see the language packs for idioms).
- **Retry budgets**: retries multiply load during incidents. Configure retries with exponential
  backoff plus jitter, cap attempts, and only for idempotent methods or explicitly retryable
  codes. In client-side config, use the service config retry policy or `retryOn` equivalents;
  hedging is rarely appropriate and needs idempotency.
- **Keepalives**: configure server `keepalive` enforcement and client ping intervals
  deliberately; aggressive pings get connections closed by `GOAWAY` (`too_many_pings`).
- **Lame-duck/graceful shutdown**: send `GOAWAY`, stop accepting new streams, drain existing
  ones up to a grace period.

## Error Model

Use the canonical `google.rpc.Status` shape with a code, message, and typed details. Do not
invent per-service error codes as the only signal; attach them as `ErrorInfo` details.

| Code | Number | Retryable? | Maps to HTTP | Meaning |
|---|---|---|---|---|
| OK | 0 | — | 200 | Success |
| CANCELLED | 1 | No | 499 | Caller cancelled |
| UNKNOWN | 2 | No | 500 | Unknown server error |
| INVALID_ARGUMENT | 3 | No | 400 | Bad request fields |
| DEADLINE_EXCEEDED | 4 | Maybe | 504 | Deadline passed; safe only if idempotent |
| NOT_FOUND | 5 | No | 404 | Missing resource |
| ALREADY_EXISTS | 6 | No | 409 | Create conflict |
| PERMISSION_DENIED | 7 | No | 403 | Authenticated, not allowed |
| RESOURCE_EXHAUSTED | 8 | Maybe | 429 | Quota/rate limit; `RetryInfo` detail |
| FAILED_PRECONDITION | 9 | No | 400/412 | State prevents the operation |
| ABORTED | 10 | Yes | 409 | Concurrency conflict; retry the transaction |
| OUT_OF_RANGE | 11 | No | 400 | Value outside valid range |
| UNIMPLEMENTED | 12 | No | 501 | Method not supported by this server |
| INTERNAL | 13 | Maybe | 500 | Invariant broken |
| UNAVAILABLE | 14 | Yes | 503 | Transient; retry with backoff |
| DATA_LOSS | 15 | No | 500 | Corruption |
| UNAUTHENTICATED | 16 | No | 401 | Missing/invalid credentials |

- Attach `google.rpc.ErrorInfo` (`reason`, `domain`, `metadata`) for machine-readable causes,
  `BadRequest` for field violations, `QuotaFailure`/`RetryInfo` for limits, `DebugInfo` for
  trace correlation, `PreconditionFailure` for state conflicts.
- **Never leak internals in `message`**; use it for a human-readable summary and put structured
  data in details.
- **Idempotency**: provide an idempotency key field on mutating requests; server deduplicates
  and returns the original result (see [errors](./06-errors.md)).
- **Rich error coverage in tests**: assert codes, not just failures; clients switch on codes.

```
service ConfigService {
  rpc SetConfig(SetConfigRequest) returns (SetConfigResponse);
}

message SetConfigRequest {
  string key = 1;
  string value = 2;
  // Optional: deduplicate retries of this request.
  string idempotency_key = 3;
}
```

## Browser Access: Connect, gRPC-Web, and Gateways

Browsers cannot speak raw gRPC over HTTP/2 with trailers. Choose one:

| Option | How it works | Trade-offs |
|---|---|---|
| Connect (Buf) | Connect protocol client/server, also speaks gRPC and gRPC-Web | No proxy needed for same-origin; verify ecosystem support in your stack |
| gRPC-Web | Envoy or similar proxy translates to gRPC | Requires edge proxy; limited streaming (server-streaming only) |
| HTTP/JSON gateway | grpc-gateway / Envoy transcoding from `google.api.http` annotations | Broadest compatibility; JSON semantics differ (int64 as string) |
| REST facade | Separate hand-written REST service | Duplicate surface; usually avoid |

- **CORS must allow the gRPC-Web/Connect headers**: `content-type`, `x-grpc-web`,
  `x-user-agent`, `connect-protocol-version`, `grpc-timeout`, plus `grpc-status`/`grpc-message`
  in `Access-Control-Expose-Headers`.
- **Auth from browsers**: short-lived bearer tokens via headers; cookies need
  credentialed CORS and CSRF protection; do not put API keys in browser code.
- **grpc-gateway annotations** keep one contract for both HTTP and gRPC; generate the gateway
  from the same `.proto` and include it in compatibility checks. Custom HTTP methods/verbs
  need explicit annotations and a documented mapping.

**Anti-patterns**

- Exposing raw gRPC to the internet without a TLS-terminating proxy and per-RPC auth.
- Hand-maintaining a separate REST API that shadows the gRPC contract.
- Relying on client-side retries without server-side idempotency.

## Checklist

- [ ] Style: versioned package, reserved fields, googleapis types, comments everywhere.
- [ ] Breaking-change detection (`buf breaking` or equivalent) runs in CI against a pinned
      baseline.
- [ ] Streaming shapes match the workload; sizes bounded; backpressure understood.
- [ ] Deadlines set and propagated; cancellation cleans up; retries have budgets and backoff.
- [ ] Errors use canonical codes plus `ErrorInfo`/`BadRequest`/`RetryInfo` details.
- [ ] Mutating RPCs accept an idempotency key.
- [ ] Browser access uses Connect/gRPC-Web/gateway with CORS and auth configured.
- [ ] Graceful shutdown and keepalive settings are tested under load.
