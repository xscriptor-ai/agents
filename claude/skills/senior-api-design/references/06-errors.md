# Errors, Retries, Idempotency, and Rate Limits

RFC 9457 problem details, error taxonomy, validation error shapes, retry semantics and budgets,
idempotency keys, and rate-limit signaling.

## Problem Details (RFC 9457)

Use `application/problem+json` (or `application/problem+xml` when applicable) for every error
response. RFC 9457 obsoletes RFC 7807 and keeps the same five members.

| Member | Type | Meaning |
|---|---|---|
| `type` | URI | Stable identifier for the error class; documentation link by convention |
| `title` | string | Short, human-readable summary; stable per `type` |
| `status` | integer | HTTP status code (repeated in the body for logs/queues that lose headers) |
| `detail` | string | Human-readable explanation of this occurrence |
| `instance` | URI | Identifier for this occurrence (often the request id path) |
| extensions | any | `code`, `errors[]`, `request_id`, `retry_after`, docs links |

```json
{
  "type": "https://api.acme.com/problems/validation-error",
  "title": "Request validation failed",
  "status": 422,
  "detail": "One or more fields are invalid.",
  "instance": "/requests/req_01J8Z",
  "code": "VALIDATION_ERROR",
  "request_id": "req_01J8Z",
  "errors": [
    {
      "pointer": "/items/0/quantity",
      "code": "OUT_OF_RANGE",
      "detail": "Must be between 1 and 999."
    }
  ]
}
```

Rules:

- **`type` is stable and dereferenceable.** Serve a short HTML page at that URI explaining the
  error, causes, and remedies. For generic cases, `about:blank` is allowed, but a real URI is
  better for consumers.
- **`title` is constant per `type`; `detail` varies per occurrence.** Do not put dynamic data
  in `title`, and do not leak internals in `detail`.
- **Always include a machine-readable `code`.** Clients should switch on `code`, not on
  `detail` strings or HTTP status alone.
- **Correlation**: include `request_id` and, when tracing, a `traceparent`-compatible id.
  Return the same id in the `X-Request-Id` response header.
- **Content negotiation**: honor `Accept`; fall back to JSON problem details when the client
  sends `Accept: */*`. Do not return HTML errors to API clients.
- **Errors are part of the contract**: document every `type`/`code` per operation in OpenAPI
  (see [contracts](./08-contracts-openapi.md)) and keep codes stable
  (see [versioning](./04-versioning-compat.md)).
- **Never include stack traces, SQL, internal hostnames, or secret material.** Log those
  server-side with the same `request_id`.

## Error Taxonomy

Keep a small, stable set. Most domains need fewer than 30 codes.

| Category | HTTP | Example codes | Client action |
|---|---|---|---|
| Malformed request | 400 | `MALFORMED_JSON`, `INVALID_QUERY_PARAM` | Fix request; do not retry |
| Validation | 422 | `VALIDATION_ERROR`, `OUT_OF_RANGE`, `INVALID_ENUM` | Fix fields; do not retry |
| Authentication | 401 | `AUTHENTICATION_REQUIRED`, `TOKEN_EXPIRED`, `TOKEN_INVALID` | Refresh or re-auth once |
| Authorization | 403 | `PERMISSION_DENIED`, `SCOPE_REQUIRED`, `TENANT_MISMATCH` | Do not retry; show operator |
| Missing resource | 404/410 | `RESOURCE_NOT_FOUND`, `RESOURCE_GONE` | Do not retry; fix identifier |
| Conflict | 409/412 | `DUPLICATE_RESOURCE`, `STATE_CONFLICT`, `PRECONDITION_FAILED` | Re-read, merge, retry conditionally |
| Not allowed method/type | 405/415/406 | `METHOD_NOT_ALLOWED`, `UNSUPPORTED_MEDIA_TYPE` | Fix client |
| Rate/quota | 429 | `RATE_LIMITED`, `QUOTA_EXCEEDED` | Backoff with jitter; respect `Retry-After` |
| Dependency failure | 502/503/504 | `UPSTREAM_UNAVAILABLE`, `TIMEOUT`, `MAINTENANCE` | Retry idempotent requests with budget |
| Internal | 500 | `INTERNAL_ERROR` | Retry cautiously; report with request id |

Validation error detail array (choose one shape and keep it):

```json
{
  "errors": [
    {"pointer": "/email", "code": "FORMAT", "detail": "Must be a valid email address."},
    {"pointer": "/items/2/sku", "code": "UNKNOWN_SKU", "detail": "SKU not found."}
  ]
}
```

- Use **JSON Pointer** (RFC 6901) for request-body locations and document whether query
  parameter errors use a different convention.
- **Report all field errors at once**, not only the first; form UX and client retries depend on
  it.
- Cap the number of reported errors (for example 50) to bound response size.
- Do not use `detail` to carry structured data; add a dedicated extension when clients must
  parse it.

**Anti-patterns**

- Per-endpoint error shapes, or `{"error": "..."}` strings.
- Exposing internal exception class names.
- Returning 200 with `{"success": false}`; use the status code.
- Changing `code` values between releases; consumers branch on them.

## Retry Semantics

Retries are a client responsibility, but the server must publish enough information to make
them safe.

- **Classify failures**: retry only on transient conditions (429, 502, 503, 504, connection
  resets, deadline exceeded on idempotent calls). Never auto-retry 400/401/403/404/409/422/500
  (500 may be retried once with a budget, but treat repeated 500s as a bug).
- **Idempotency first**: only retry POSTs/PATCHes when the request carries an idempotency key or
  is naturally idempotent. See below.
- **Exponential backoff with full jitter**:

```text
delay = min(cap, base * 2^attempt)
sleep = random_uniform(0, delay)        # full jitter
```

Typical: `base` 100-500 ms, `cap` 10-30 s, 3-5 attempts, total budget under the caller's own
timeout. Respect `Retry-After` when present; it overrides computed delays.
- **Retry budgets**: cap retries as a fraction of total traffic (for example 10%) to prevent
  retry storms during incidents. Prefer client-side rate limiters that shed retries when the
  budget is exhausted.
- **Circuit breakers** per dependency with half-open probes, and load shedding at the edge
  before queues saturate.
- **The server can ask for retries safely** with `503` + `Retry-After` + problem details; do not
  return 200 with a "try again" body.
- **Never retry non-idempotent operations** without a key, including internal service calls;
  the gRPC `ABORTED`/`UNAVAILABLE` guidance is the same pattern (see [gRPC](./03-grpc.md)).
- **Hedging** (sending a second request before the first returns) is only safe for idempotent
  reads and needs strict per-attempt budgets; otherwise it doubles write load.

## Idempotency Keys

For unsafe methods, the server, not the client, guarantees "at most one side effect per key".

- **Header**: `Idempotency-Key: <client-generated UUID>` (an idempotency-key header is being
  standardized; verify the current IETF draft/RFC status before claiming conformance).
- **Scope**: key is unique per `(principal, route, key)`. The same key from two accounts must not
  collide. Hash the key before storage if it may contain sensitive data.
- **Request fingerprint**: hash the canonical body plus relevant headers. On replay with a
  different fingerprint, return `422` or `409` with `code: IDEMPOTENCY_KEY_REUSED` — never
  execute the new body under the old key.
- **Concurrency**: two in-flight requests with the same key should yield a deterministic
  outcome: either one executes and the other waits and replays, or the second gets `409`/`425
  Too Early` with retry guidance. Document which.
- **Replay response**: return the original status and body (minus volatile data), and mark it
  (for example `Idempotency-Replayed: true`) so clients and logs can distinguish.
- **TTL**: store records for a documented window (common: 24 h to 30 days). After expiry, the
  same key may execute again; document that and choose a TTL longer than your retry horizon.
- **Storage**: a unique constraint on `(principal, route, key)` plus a row lock or advisory lock
  beats read-then-write races. The record should store status, response body (bounded), and
  headers needed for replay.
- **Failure handling**: only store a completed result. If the first attempt fails mid-flight,
  delete or mark the record so a retry can proceed, or store a terminal failure and replay it
  consistently.

```text
POST /payments
Idempotency-Key: 0f8fad5b-d9cb-469f-a165-70867728950e

-> 201 Created (first call)
-> 201 Created, Idempotency-Replayed: true (retry with same body)
-> 409 Conflict, code: IDEMPOTENCY_KEY_REUSED (same key, different body)
```

## Rate Limiting and Quota Signaling

Distinguish **rate limits** (requests per time window) from **quotas** (usage allowances per
period) and **concurrency limits** (in-flight work). Signal all three clearly.

| Signal | Where | Notes |
|---|---|---|
| `429 Too Many Requests` | Response status | With problem details body (`type` = rate-limited) |
| `Retry-After` | Header | Seconds or HTTP date; required on 429 and useful on 503 |
| `RateLimit-Limit` / `RateLimit-Remaining` / `RateLimit-Reset` | Headers | IETF rate-limit header fields (verify current RFC status); include on success and failure |
| `RateLimit` (structured) | Header | Single structured field with policies; check current spec before adopting |
| `X-RateLimit-*` | Headers | Legacy/de facto; do not use for new APIs |
| `503` + `Retry-After` | Response | Quota exhausted for the billing period, or planned maintenance |

- **Limit by the right subject**: API key, OAuth client, user, tenant, and IP (edge only). Per-IP
  alone breaks shared NATs and punishes proxies; combine with identity limits.
- **Multiple windows**: burst (per second) plus sustained (per hour/day). Document both.
- **Return 429 before shedding silently**; a dropped connection is impossible to debug.
- **Include enough context in the body**: which limit, the window, the reset time, and a docs
  link. Extensions such as `retry_after` and `limit`/`remaining`/`reset` in problem details.
- **Counters must be shared** across instances (Redis/Valkey or a gateway) or limits multiply
  by replica count.
- **Header consistency**: always send remaining/reset on 2xx so well-behaved clients can slow
  down proactively; do not only signal at failure.
- **Billing quotas** deserve a distinct `code` (`QUOTA_EXCEEDED`) and a different remediation
  (upgrade plan) than a transient burst limit.
- **Webhooks and async jobs** carry the same limits; document per-event delivery limits
  (see [events](./09-events-webhooks.md)).

**Anti-patterns**

- 503 with no `Retry-After` for a known maintenance window.
- Returning `X-RateLimit-*` on some endpoints only.
- Applying a global IP limit that punishes an entire customer's NAT egress.
- Silently dropping requests at the load balancer without a response body.

## Checklist

- [ ] All errors use RFC 9457 problem details with the same media type.
- [ ] Every error has a stable `code`, a stable `type` URI, and a `request_id`.
- [ ] Validation errors report all fields with JSON Pointer locations.
- [ ] Error taxonomy is documented per operation and versioned with change control.
- [ ] No stack traces or internals leak; logs correlate by request id.
- [ ] Retries use exponential backoff with jitter, budgets, and `Retry-After` respect.
- [ ] Idempotency keys are implemented for unsafe methods with fingerprint and TTL semantics.
- [ ] Rate/quota limits are published and signaled on success and failure.
- [ ] Distinguish rate limit, quota, and maintenance in status and codes.
