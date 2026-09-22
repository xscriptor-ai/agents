# Pagination, Sorting, and Filtering

Cursor vs offset, cursor design and keyset queries, sorting contracts, sparse fieldsets,
filtering grammars, batching, consistency, and limits.

## Choosing a Pagination Model

| Model | Request | Stability under writes | Random access | Performance | Use when |
|---|---|---|---|---|---|
| Offset/limit | `?offset=100&limit=50` | Poor: items shift, duplicates/skips | Yes | Degrades with depth (`OFFSET` scans) | Small admin tables, static data, page numbers required |
| Page/per_page | `?page=3&per_page=50` | Poor (offset in disguise) | Yes | Same as offset | UI with page numbers, bounded totals |
| Cursor | `?cursor=eyJ...` | Good: anchored to last item | No | Index-friendly keyset | Feeds, exports, API-to-API, social timelines |
| Keyset (explicit) | `?after_id=123&limit=50` | Good | No | Best with composite index | Public APIs where opaque cursor annoys debuggers |
| Snapshot | `?snapshot=ts&cursor=...` | Perfect (frozen view) | No | Needs MVCC/PITR support | Reconciliation, billing close, audit exports |

Default recommendation: **cursor/keyset for anything ordered and growing; offset only for small
admin surfaces with stable ordering and capped depth**.

**Anti-patterns**

- Offset pagination on a hot table with millions of rows and a UI "next" button.
- Returning an unbounded list when the client does not ask for pagination.
- Inconsistent page sizes across endpoints, or no documented maximum.

## Cursor Design

A cursor encodes the position in a total order. It must be opaque, stable, and tamper-evident
if it influences filtering.

- **Payload**: the sort key values of the last item plus a tiebreaker (`created_at` + `id`),
  base64url-encoded. Optionally include a query fingerprint and expiry.
- **Sign or encrypt** cursors when clients could otherwise skip authorization scopes or forge
  filters (for example a cursor scoped to a tenant). HMAC is sufficient for integrity; encrypt
  if the payload leaks sensitive ordering data.
- **Opaque to clients**: document "treat as a token; do not parse or construct".
- **Single direction per request**: forbid `after` + `before` together; document that reversing
  direction requires re-sorting.
- **Cursor expiry**: optional, but if cursors expire, return a clear `400 INVALID_CURSOR` with a
  code the client can branch on, and document restart semantics.
- **Never put offsets inside cursors**; that reintroduces drift.

```json
{
  "data": [{"id": "ord_01J", "created_at": "2026-01-02T03:04:05Z"}],
  "pagination": {
    "next_cursor": "eyJjcmVhdGVkX2F0IjoiMjAyNi0wMS0wMlQwMzowNDowNVoiLCJpZCI6Im9yZF8wMUoifQ",
    "has_more": true
  }
}
```

Keyset query shape for `ORDER BY created_at DESC, id DESC`:

```sql
SELECT id, created_at, total
FROM orders
WHERE tenant_id = $1
  AND (created_at, id) < ($2, $3)
ORDER BY created_at DESC, id DESC
LIMIT $4;
```

- The composite index must match the sort: `(tenant_id, created_at DESC, id DESC)`.
- Row-value comparison `(a, b) < (?, ?)` works in modern PostgreSQL/MySQL; verify support and
  plan shape in your engine. For engines without row values, expand to
  `a < ? OR (a = ? AND b < ?)`.
- Keyset requires a **total order**. Add the primary key as the final tiebreaker everywhere,
  including when clients sort by a non-unique field.

## Sorting

- **Parameter style**: `?sort=-created_at,name` (leading `-` for descending) or repeated
  `?sort=created_at:desc`. Pick one and document it; expose it in OpenAPI as an array or a
  pattern-validated string.
- **Whitelist sortable fields.** Never interpolate client input into `ORDER BY`; map public
  names to columns and reject unknown fields with a 400 problem-details error.
- **Append a deterministic tiebreaker** (`id`) to every sort so pages do not overlap.
- **Default sort is part of the contract.** Document it, and keep it stable; changing the
  default order is a breaking change for pagination cursors and for consumers assuming
  recency.
- **Collation and null ordering**: document case sensitivity and where nulls sort; these differ
  across databases and are observable client behavior.
- **Expensive sorts** (unindexed columns) should be rejected or documented as slow; consider
  materialized views or search indexes for relevance ordering.

**Anti-patterns**

- `ORDER BY` built from `req.query.sort` without a whitelist.
- Non-deterministic order (`ORDER BY created_at` alone) with cursor pagination.
- Sorting by relevance without documenting the scoring or how ties break.

## Sparse Fieldsets and Expansion

Let clients fetch what they need without a combinatorial set of endpoints.

| Feature | Parameter | Notes |
|---|---|---|
| Sparse fieldsets | `?fields=id,total,status` or `fields[orders]=...` | Whitelist per resource; always include `id` |
| Expansion | `?expand=customer,items` | Cap depth and count; document allowed expansions |
| Exclusion | `?exclude=internal_notes` | Simpler for admin surfaces; still whitelist |
| Embedded vs linked | `?include=items` (JSON:API style) | Prefer explicit `include` over magic auto-expansion |

- Nested field selection (`fields=id,customer(id,name)`) is powerful but adds parser and
  authorization complexity; only adopt if your framework supports it, and validate depth.
- GraphQL solves this natively with field selection; do not bolt field selection onto a
  GraphQL endpoint via query parameters.
- **Default representations must stay modest**: unbounded nested includes per list item are a
  performance trap (N+1 over rows, giant payloads). Cap expansions and paginate sub-collections.

## Filtering Grammar

Complexity grows fast; choose the simplest grammar that covers the contract and document it
precisely.

| Grammar | Example | Strengths | Weaknesses |
|---|---|---|---|
| Equality params | `?status=paid&customer_id=42` | Simple, cacheable, index-friendly | No ranges/OR |
| Operator suffix | `?created_at_gte=...&total_lt=...` | Readable, easy to validate | Many params, naming conventions |
| Repeated with operator | `?status=paid&status=pending` (implicit OR) | Simple OR for enums | Ambiguous with AND across fields |
| Structured/bracketed | `?filter[status][in]=paid,pending` | Expressive, parseable | Verbose, framework support varies |
| Expression grammar | `?filter=status eq "paid" and total gt 100` | Very expressive | Parsing, injection risk, index-unfriendly |
| RSQL/FIQL | `?filter=status==paid;total>100` | Compact, tooling exists | Niche, needs escaping rules |
| OData `$filter` | `?$filter=Status eq 'paid'` | Standardized | Heavy; partial support; SQL injection risk if translated naively |

- **Semantics must be explicit**: AND across different fields; for repeated values on one field,
  state whether it is OR or last-wins. Never leave it to the framework default.
- **Translate to parameterized queries only.** An expression grammar that concatenates SQL is
  the classic injection path; parse to an AST and map to SQLAlchemy/Kysely/query builders.
- **Index alignment**: only allow filtering on indexed/allowlisted fields, or implement
  full-text/search-engine-backed filtering for free text. `LIKE '%term%'` on a large table is a
  denial-of-service.
- **Unknown filter fields** should be rejected (400 with a machine-readable code listing allowed
  fields) rather than silently ignored — silent ignores produce wrong data with no signal.
- **`filter` on nested relations** is usually best served by dedicated endpoints or search
  indices; deep joins through list endpoints blow up query plans.
- **Response metadata**: include the applied filters and sort in the response envelope if
  clients need to confirm interpretation.

## Batching and Prefetch

| Need | Pattern | Notes |
|---|---|---|
| Fetch N known resources | `?ids=a,b,c` (cap count) | Returns found items; document missing-id behavior |
| Heterogeneous reads | `POST /batch` sub-requests | One round trip; per-item statuses |
| GraphQL batching | DataLoader per request | Never batch across requests/users |
| gRPC | Batch RPC with repeated ids | Cap size; same semantics as REST |
| Client cache priming | ETag-based conditional multi-get | See [REST caching](./01-rest.md) |

- **Document missing ids**: return a map keyed by requested id, a list with nulls, or 404 if
  any are missing. Pick one and keep it consistent.
- **Cap batch size** and return 400 (not truncation) when exceeded.
- **Batching is not a substitute for pagination**; it is for known-id lookups only.

## Consistency and Limits

- **Read-your-writes**: after a mutation, a subsequent list read may lag on replicas. Accept a
  consistency token (write LSN/timestamp) or route the session to the primary for a window.
  Document the guarantee per endpoint.
- **Cursor consistency**: cursors anchor to a sort key, so concurrent inserts do not shift
  pages. Deletes can still remove an item you have not yet read; that is expected, document it.
- **Snapshot exports**: for "give me everything as of T", run an async job against a snapshot
  (repeatable-read transaction, read replica with PITR, or warehouse export) and hand back a
  result URL (see [events/webhooks](./09-events-webhooks.md) for completion notification).
- **Limits table** (publish it):

| Limit | Typical | Enforcement |
|---|---|---|
| Default page size | 20-50 | Applied when client omits pagination |
| Max page size | 100-1000 | 400 or clamp; document which |
| Max offset | 1k-10k | Reject deeper offsets with a cursor hint |
| Max `ids` per batch | 100-1000 | 400 |
| Max expansions | 3-5 | 400 |
| Max filter predicates | 10-20 | 400 |
| Query timeout | 1-30 s | Abort and return 503/timeout error |

**Anti-patterns**

- Returning `total_count` with an expensive unbounded count on every list request.
- Using `has_more` computed by fetching `limit + 1` but then exposing the extra item.
- Mixing cursor and offset parameters on one endpoint.
- Ignoring unknown query parameters so typos silently change result sets.

## Checklist

- [ ] Pagination model chosen per endpoint and documented (cursor default for ordered lists).
- [ ] Sort keys deterministic, whitelisted, index-aligned; default sort documented.
- [ ] Cursors opaque, signed/encrypted when they carry scope, and single-direction.
- [ ] Sparse fieldsets/expansions whitelisted, capped, and default-modest.
- [ ] Filter grammar documented with AND/OR semantics and unknown-field rejection.
- [ ] Filters translate to parameterized queries; no string concatenation.
- [ ] Batch size, page size, offset depth, and timeout limits are published and enforced.
- [ ] Missing-id semantics for multi-get are defined.
- [ ] Consistency guarantees (read-your-writes, snapshot exports) are stated.
- [ ] `has_more`/`next_cursor` semantics tested at boundaries (empty page, last page, exact
      multiple of page size).
