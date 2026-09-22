# REST

Resource modeling, method and status-code semantics, representations, idempotency, concurrency control, caching, and bulk operations for HTTP/JSON APIs.

## Resource Modeling

Model the domain, not the database. A resource is a named thing with state and identity; the
database schema is an implementation detail that may expose several resources.

- **Nouns, plural, lower-case, hyphenated**: `/orders`, `/shipping-labels`, `/users/{id}/sessions`.
- **Identifiers stay opaque**: never expose incrementing integers as the only id (enumeration);
  use a UUIDv7, ULID, or a prefixed opaque id such as `ord_01J...`. Clients must treat ids as
  strings.
- **Nesting encodes containment, not convenience**: at most one or two levels where the child
  cannot exist without the parent (`/users/{id}/sessions`). For deep graphs, use top-level
  resources with filters (`/orders?customer_id=...`) and document the relation.
- **Singleton resources** for things that exist once per scope: `/me`, `/settings`, `/cart`.
- **State transitions** that are not CRUD should be sub-resources that model the event:
  `POST /orders/{id}/cancellation`, `POST /orders/{id}/refunds`, or an explicit state patch
  `PATCH /orders/{id} {"status": "cancelled"}` when transitions are simple and documented.
  Custom action verbs (`POST /orders/{id}/cancel`) are an accepted escape hatch, but make them
  idempotent-safe and document return semantics.
- **Collections are queried, not designed ad hoc**: every collection supports pagination
  (see [pagination and filtering](./05-pagination-filtering.md)) and has a documented default
  and maximum page size.
- **Do not mirror tables**: `order_items` exposed as a top-level collection invites clients to
  build joins the API never intended to support.
- **Name the URL for the resource the response represents.** If `POST /payments` returns a
  payment, the response is the payment, not an envelope with `payment` plus `receipt`.

### Representation conventions

| Decision | Recommendation | Notes |
|---|---|---|
| Field naming | One casing everywhere (`snake_case` or `camelCase`) | Document it; do not translate per endpoint |
| Dates/times | RFC 3339 UTC strings (`2026-01-02T03:04:05Z`) | Never local time; accept `+00:00` |
| Money | Minor units integer + ISO 4217 code (`{"amount": 1099, "currency": "USD"}`) | Never floats |
| Enums | Upper `SNAKE_CASE` strings, additive only | Unknown values must not break clients |
| Empty vs missing | Omit unset fields unless the client asked for them | `null` means explicit absence |
| Booleans | Positive names (`is_active`, not `is_not_active`) | Avoid tri-state confusion |
| IDs in responses | Always include the canonical resource id and a `self` link if linking is used | HATEOAS optional |

## Methods and Status Codes

| Method | Meaning | Safe | Idempotent | Typical success |
|---|---|---|---|---|
| GET | Read resource/collection | yes | yes | 200 |
| HEAD | Same as GET without body | yes | yes | 200 |
| OPTIONS | Capabilities / CORS preflight | yes | yes | 204 |
| POST | Create or submit; non-idempotent by default | no | no | 201 (+ `Location`) |
| PUT | Replace the resource at a known URI | no | yes | 200/201/204 |
| PATCH | Partial update | no | no (unless conditional) | 200/204 |
| DELETE | Remove | no | yes | 204/202 |

Status code rules that prevent most review cycles:

- **201 + `Location`** on create. If the server does not know the final id yet, return 202 with
  a status resource instead.
- **202 Accepted** for operations that will complete asynchronously; return a job resource URL
  and let clients poll or subscribe (see [events and webhooks](./09-events-webhooks.md)).
- **204 No Content** for successful mutations with nothing to say. Do not return 200 with `{}`.
- **400 vs 422**: 400 for malformed syntax (unparseable JSON, bad query string), 422 for
  well-formed but semantically invalid input (unknown enum value, failing business rule).
- **401 vs 403**: 401 means the credential is missing, invalid, or expired; 403 means the
  credential is valid but lacks access. Never use 404 to hide 403 unless the resource existence
  itself is sensitive.
- **404 vs 410**: 410 Gone for resources that existed and were intentionally removed; include a
  link to the replacement when possible.
- **405** with an `Allow` header for wrong method; **415** for unsupported media type;
  **406** when acceptable representation cannot be produced.
- **409 Conflict** for state conflicts (duplicate unique key, illegal transition). **412
  Precondition Failed** for failed conditional requests (`If-Match`).
- **428 Precondition Required** when the server refuses unconditional writes, forcing `If-Match`.
- **429** for rate limits with `Retry-After` (see [errors](./06-errors.md)).
- **503** with `Retry-After` for planned maintenance or dependency exhaustion; do not return 500
  for something you know is temporary.

**Anti-patterns**

- Returning 200 for errors or a different 200 shape per endpoint.
- `POST /getOrder` or other RPC verbs in paths when a resource model exists.
- 500 for validation failures because an exception escaped.
- Different status codes for the same failure across endpoints.

## Idempotency

Retries are inevitable (network, timeouts, load balancers). Safe methods and PUT/DELETE are
idempotent by definition; POST needs an explicit key.

- Clients send `Idempotency-Key: <uuid>` (a header name now also standardized in the
  idempotency-key IETF draft; verify the current RFC status). Server behavior:
  1. Look up the key scoped to the authenticated principal + route.
  2. If seen with an identical request fingerprint, replay the stored response (status, headers,
     body) and mark it as a replay.
  3. If seen with a different payload, return 422/409 — never silently overwrite.
  4. If a concurrent request with the same key is in flight, return **409** or **425 Too Early**
     and let the client retry; some APIs block briefly and return the same result.
- Store keys with a TTL (commonly 24 hours to 30 days depending on domain) and prune
  aggressively. Never store full request bodies unless required; store a hash plus response.
- Generate the key **before** the first attempt and reuse it across retries with the same body.
- Document which endpoints accept keys and whether keys are scoped per account or per route.

```
POST /payments
Idempotency-Key: 8f14e45f-ea0d-4d2b-9f2e-1c9a7b3d5e10
Content-Type: application/json

{"amount": 1099, "currency": "USD", "source": "pm_123"}
```

**Anti-patterns**

- Treating POST as idempotent "because it usually is".
- Replaying with a 200 when the original returned 500, hiding the failure.
- Keying only on the key value, so two tenants can collide.

## Concurrency Control (Optimistic Locking)

Use ETags for lost-update prevention on read-modify-write flows.

1. `GET /orders/123` returns `ETag: "7"` (or a hash of the representation).
2. Client sends the update with `If-Match: "7"`.
3. Server compares; mismatch returns **412 Precondition Failed** with the current resource so
   the client can reapply.
4. `If-None-Match: *` on PUT creates only if absent (201) and returns 412 if it exists.

- Keep ETag generation cheap and deterministic for a representation; weak ETags (`W/"..."`) are
  acceptable when byte equality is not guaranteed.
- Do not rely on `Last-Modified` for concurrency: second granularity causes lost updates.
- For collections, ETags help caching but do not protect list-level edits; per-item ETags do.
- Document conflict payloads: return the current state plus the fields that conflict when the
  domain allows a merge.

**Anti-patterns**

- `If-Match` checked against the *new* body instead of the stored version.
- Returning 409 and 412 interchangeably; pick 412 for conditional-header failures.
- ETags that change on every response due to timestamps or request ids.

## Caching Semantics

| Header | Purpose | Notes |
|---|---|---|
| `Cache-Control: public, max-age=60, stale-while-revalidate=30` | Freshness and revalidation window | Use `private` for per-user data |
| `Cache-Control: no-store` | Sensitive responses | Tokens, PII |
| `ETag` + `If-None-Match` | Validation | 304 saves bandwidth |
| `Vary` | Cache key dimensions | `Vary: Authorization, Accept-Language`; missing `Vary` is a data-leak bug |
| `Age` | Time in shared cache | Useful in debugging |
| `Surrogate-Control` | CDN-specific TTL | Keep origin and CDN TTLs aligned |

- GETs should be cacheable unless they are per-user and marked `private, no-store`. Authenticated
  responses served through shared caches must vary on credentials.
- `304 Not Modified` on validation with `If-None-Match`/`If-Modified-Since`; never return 200
  with the full body just because you did not implement validation.
- Invalidation: prefer short TTLs plus versioned URLs (`/v1/...?v=hash`) over aggressive purge
  logic in the origin.
- POST responses are cacheable only with explicit `Cache-Control` and a `Content-Location`.

**Anti-patterns**

- Caching `Authorization`-dependent responses publicly.
- `Vary: *` (kills cache efficiency) or no `Vary` with content negotiation.
- Returning `Set-Cookie` on cacheable responses.

## Bulk and Batch Operations

| Pattern | Shape | Use when |
|---|---|---|
| Multi-id read | `GET /orders?ids=a,b,c` or repeated `id` params | Small, bounded sets (cap the count) |
| Batch endpoint | `POST /batch` with an array of sub-requests | Heterogeneous operations, one round trip |
| Bulk create/update | `POST /orders:batchCreate` or an array body | Homogeneous high-volume writes |
| Async job | `POST /exports` -> 202 + job resource | Large or slow work; result URL when done |
| Long-running mutation | `POST` returns operation resource (`Operation` pattern) | Anything over a few seconds |

- **Bounded sizes**: cap items per request (for example 100-1000) and reject oversize requests
  with 400 rather than truncating silently.
- **Partial success**: choose and document one semantic. Either all-or-nothing (single
  transaction, fail fast) or per-item results with `200` and a mixed status array, or a batch
  status of `207 Multi-Status` where clients understand it. Do not mix semantics by endpoint.
- **Ordering**: state whether batch items are processed in order and whether earlier failures
  stop the batch. Consumers depend on this during retries.
- **Atomicity**: if all-or-nothing, say so; if not, return enough information to resume
  (`index`, `id`, `error` per item).
- **Idempotency**: batch endpoints need an idempotency key for the whole request and per-item
  keys when items can be retried independently.

```json
{
  "results": [
    {"index": 0, "status": 201, "id": "ord_01J"},
    {"index": 1, "status": 422, "error": {"code": "INVALID_CURRENCY", "detail": "XYZ unsupported"}}
  ]
}
```

**Anti-patterns**

- Unbounded batch endpoints that let one request exhaust the database.
- Returning only the failures without indexes, forcing consumers to diff.
- Accepting batches over GET when the URL exceeds practical limits (8 KB+); use POST with a
  query-like body only when semantics are read-only, and document it.

## Review Checklist

- [ ] Resources are nouns, ids are opaque, nesting is shallow and justified.
- [ ] Methods and status codes follow the table above; errors never return 200.
- [ ] Create returns 201 + `Location`; async work returns 202 + job resource.
- [ ] POST mutations accept `Idempotency-Key` with documented replay semantics.
- [ ] Read-modify-write supports `If-Match` (412 on conflict) and 428 where required.
- [ ] Cache headers are correct per resource; `Vary` covers auth and negotiation.
- [ ] List endpoints are paginated with bounded sizes and a stable order.
- [ ] Bulk endpoints are size-capped, transactional semantics are documented, and results are
      addressable.
- [ ] Every error body conforms to the shared problem-details shape
      (see [errors](./06-errors.md)).
- [ ] The published OpenAPI spec matches the implementation
      (see [contracts](./08-contracts-openapi.md)).
