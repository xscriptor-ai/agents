---
name: senior-api-design
description: 'API design reference pack, current for 2026: REST resource modeling
  and HTTP semantics, GraphQL schema design and federation, gRPC/protobuf and streaming,
  versioning and compatibility, pagination and filtering, RFC 9457 problem details,
  OAuth 2.1/OIDC/mTLS security, OpenAPI 3.1 contracts and codegen, and events and
  webhooks. Use when designing, reviewing, versioning, or documenting HTTP, GraphQL,
  gRPC, or event-driven interfaces: choosing a style for a new surface, fixing status
  codes or error shapes, adding cursor pagination or filtering, standardizing idempotency
  keys and retry semantics, hardening OAuth scopes, tokens, and tenancy, authoring
  or linting OpenAPI/AsyncAPI, running contract tests, or evolving a public API without
  breaking consumers. Optional pack: consumers degrade gracefully when it is absent.'
---

# API Design

Design and evolution of interfaces that other teams and services consume: HTTP/REST, GraphQL,
gRPC, and event-driven. The pack is opinionated where the industry has converged (problem
details, cursor pagination, OAuth 2.1, OpenAPI 3.1) and flags the rest as decisions to make
explicitly. It covers the contract, not the framework internals; language-specific guidance
lives in the language packs.

## Domain Overview

- **One contract, many styles.** HTTP/JSON, GraphQL, gRPC, and events are complementary, not
  competing: pick per surface and document why. Mixing styles inside one surface is the most
  common source of accidental complexity.
- **The contract is a product.** Schemas, examples, error codes, and deprecation policy ship
  with the service. A consumer should never need to read your source or a ticket to integrate.
- **Compatibility is additive.** Design changes so old clients keep working, and gate breaking
  changes behind a version plus a sunset process with telemetry.
- **Errors and pagination are API design, not implementation details.** They are the two
  surfaces consumers touch most after the happy path.
- **Security is part of the interface.** Token scopes, audiences, idempotency keys, and rate
  limits are contract-level decisions, not middlebox configuration.
- **Verify upstream.** Version floors below are ranges; confirm current support in the official
  spec/repository before pinning.

## Core Rules (non-negotiable)

1. **Design the contract before the implementation.** Decide resources/operations, errors,
   pagination, idempotency, and versioning in a reviewable artifact (OpenAPI, SDL, `.proto`,
   AsyncAPI) first. Codegen from the contract, never the reverse.
2. **Resources are nouns; HTTP methods are verbs.** No action verbs in paths; model state
   transitions as sub-resources or documented custom methods when they do not fit CRUD.
3. **Use status codes semantically.** Do not return 200 with an error body. Distinguish 401 vs
   403, 404 vs 410, 409 vs 412, 422 vs 400, 429 vs 503.
4. **Every error uses one shape.** RFC 9457 problem details with a stable, machine-readable
   `code`, a human `detail`, and a correlation id. Never leak stack traces or SQL.
5. **All list endpoints are paginated.** Bounded page size with a hard maximum, deterministic
   total order including a tiebreaker, and an opaque cursor for anything ordered.
6. **Mutating retries require idempotency.** `Idempotency-Key` on unsafe POSTs, `If-Match` for
   optimistic concurrency, and stable client-generated request ids for events.
7. **Adding is safe; changing is not.** New optional fields/enums/methods are additive; removing,
   renaming, retyping, or tightening validation is breaking and needs a version + sunset.
8. **Authenticate and authorize at the contract level.** Declare schemes, scopes, and audiences
   in the spec; enforce least privilege per operation; never trust client-supplied tenant ids.
9. **Rate limit and document it.** Publish limits and return `429` with retry guidance; do not
   silently drop or throttle in the load balancer only.
10. **Deliver events at least once; consumers deduplicate.** Webhooks and brokers retry, so every
    consumer is idempotent by `event id`, and every producer uses an outbox.
11. **The spec is tested.** Contract tests, schema linting, and breaking-change detection run in
    CI on every change.
12. **Deprecate loudly and long.** Deprecation and Sunset headers, changelog entries, usage
    telemetry, brownouts, and a published removal date.

## Decision Tables

### Surface style

| Situation | First choice | Notes |
|---|---|---|
| Public/partner CRUD, cacheable reads, broad tooling | REST + JSON | OpenAPI 3.1 contract; problem details errors |
| Product graph, mobile BFF, client-shaped reads | GraphQL | Start federation only when >1 team owns types |
| Internal service-to-service, low latency, streaming | gRPC | Protobuf; deadlines and the canonical error model |
| Async workflows, integration fan-out, audit streams | Events + webhooks | CloudEvents envelope; outbox; AsyncAPI docs |
| One-off binary transfer or media streaming | HTTP range/object store URLs | Do not tunnel bytes through RPC frameworks |
| Mixed: public REST + internal gRPC + webhooks | Layer by audience | One contract per audience, shared domain types |

### Versioning strategy

| Strategy | Use when | Cost |
|---|---|---|
| Additive evolution (no version) | Default for private and most public APIs | Requires discipline and CI diffing |
| URL path `/v2` | Breaking public contract, discoverability matters | Duplicate docs/routes; migration fatigue |
| Media type / `Accept` versioning | Content negotiation already central | Invisible in logs; caching complexity |
| Header `API-Version` (date-based) | Many small breaking changes (Stripe-style) | Clients must pin; defaults shift |
| Proto package `v2` | gRPC breaking changes | New package, old still served |
| New event type/version field | Async breaking payload changes | Consumers subscribe to both during migration |

### Pagination

| Situation | Choose | Avoid |
|---|---|---|
| Ordered feed, cursor-stable, API-to-API | Opaque cursor / keyset | Deep `OFFSET` |
| Admin UI with page numbers and totals | Bounded offset + capped count | Unbounded `COUNT(*)` on hot tables |
| Small, static, client-held set | Return all with `ETag` caching | Pretending to paginate |
| GraphQL list | Relay connection (`edges`/`pageInfo`) | Bare arrays without pagination |
| Export/batch | Async job + result URL | Sync page loops for millions of rows |

### Error and retry signaling

| Signal | Status | Client action |
|---|---|---|
| Validation failure (shape/type) | 400 / 422 | Fix request; do not retry |
| Auth missing/expired | 401 | Refresh or re-authenticate once |
| Authenticated but not allowed | 403 | Do not retry; surface to operator |
| Missing resource | 404 (410 if gone) | Do not retry |
| State conflict / lost update | 409 / 412 | Re-read, merge, retry with `If-Match` |
| Rate limited | 429 + `Retry-After`/rate headers | Backoff with jitter; respect quota |
| Dependency unavailable | 502/503 + `Retry-After` | Retry idempotent requests with budget |
| Timeout / transient network | 504 / client error | Retry with backoff + idempotency key |

### Auth mechanism

| Consumer | Mechanism | Notes |
|---|---|---|
| Browser SPA / mobile user | OIDC + OAuth 2.1 authorization code + PKCE | Never store refresh tokens in a browser; BFF preferred |
| Service or daemon | OAuth 2.1 client credentials, mTLS/private_key_jwt | Prefer mTLS or DPoP sender-constrained tokens |
| Partner integration | OAuth 2.1 + scopes, optional mTLS | Audiences and scopes declared in the spec |
| Simple server-to-server, scoped | API key + per-key rate limits | Rotatable, hashed at rest, never in URLs/logs |
| Legacy client that cannot do OAuth | Gateway/edge session or signed requests | Treat as migration debt with a sunset date |

## Reference Index

Load only what the task needs. All paths are relative to this file.

| # | Reference | Scope | Load when |
|---|---|---|---|
| 01 | [references/01-rest.md](references/01-rest.md) | Resource modeling, methods and status codes, representations, idempotency keys, ETag/If-Match concurrency, HTTP caching, bulk and batch operations | Designing or reviewing any HTTP/JSON surface, fixing status codes, adding concurrency or caching |
| 02 | [references/02-graphql.md](references/02-graphql.md) | Schema design, nullability, Relay connections, federation composition, persisted queries, depth/cost limits, auth, DataLoader | Designing SDL, splitting a graph, defending against expensive queries, fixing N+1 |
| 03 | [references/03-grpc.md](references/03-grpc.md) | Proto style guide, compatibility, streaming patterns, deadlines and cancellation, canonical error model, Connect and gRPC-Web, HTTP gateway | Writing `.proto` files, choosing a streaming shape, browser/edge access, error retries |
| 04 | [references/04-versioning-compat.md](references/04-versioning-compat.md) | Versioning strategies, additive change rules per style, deprecation and Sunset headers, sunset process, breaking-change detection, compatibility testing | Evolving a live API, planning a v2/removal, wiring schema-diff CI gates |
| 05 | [references/05-pagination-filtering.md](references/05-pagination-filtering.md) | Cursor vs offset vs keyset, cursor design, sorting, sparse fieldsets, filtering grammar, batching, consistency and limits | Adding list endpoints, fixing unstable pages, designing query parameters |
| 06 | [references/06-errors.md](references/06-errors.md) | RFC 9457 problem details, error taxonomy, validation errors, retry semantics and budgets, idempotency keys, rate-limit signaling | Standardizing error responses, designing retries, implementing idempotency or limits |
| 07 | [references/07-auth.md](references/07-auth.md) | OAuth 2.1, OIDC, scopes and audiences, token lifetimes and revocation, DPoP, mTLS, API keys, rate limiting, tenancy | Choosing auth per consumer, hardcoding scopes/lifetimes, multi-tenant isolation |
| 08 | [references/08-contracts-openapi.md](references/08-contracts-openapi.md) | OpenAPI 3.1 authoring, style and linting, design-first/code-first, SDK codegen, contract testing, mocks, spec governance | Writing or reviewing specs, generating clients, adding contract tests, enforcing style |
| 09 | [references/09-events-webhooks.md](references/09-events-webhooks.md) | CloudEvents envelope, webhook delivery and signatures, retries and dead letters, AsyncAPI, schema registries, transactional outbox | Publishing/consuming webhooks or events, designing delivery guarantees, event schema evolution |

## Loading

- **Installed agent** — `skill({ name: "api-design" })` in OpenCode; Claude Code reads
  `<skills-dir>/api-design/SKILL.md`.
- **Orchestrator** — read this file, then inject only the references the task needs.
- **Not installed** — proceed with embedded guidance, state the degraded mode, and do not
  invent pack-only content.
- **Consumers** — reference this pack as `load skill senior-api-design (optional)`.

## Port

- **Port id** — `skill://senior/api-design` (version in `metadata.port-version`).
- **Kind** — read-only reference pack; no side effects, no tools required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "api-design" })` in OpenCode; Claude Code reads `<skills-dir>/api-design/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers reference it as `load skill senior-api-design (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major.
