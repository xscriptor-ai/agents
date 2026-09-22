# GraphQL

Schema design, nullability, Relay-style pagination, federation, persisted queries, query cost
limits, authorization, and resolver performance.

## Schema Design

The schema is the contract; SDL is the source of truth. Generate types and clients from it, and
review SDL changes like code.

- **Schema-first, single style.** Use one casing (`camelCase` fields, `PascalCase` types),
  consistent suffixes (`*Input`, `*Payload`, `*Connection`, `*Edge`), and documented
  descriptions on every type and field.
- **Separate input and output types.** Never reuse a domain type as an input: outputs evolve
  under output compatibility rules, inputs under input rules.
- **Prefer object types plus explicit relations over generic JSON scalars.** Only use custom
  scalars (`DateTime`, `URL`, `JSON`) with a documented serialization and validation.
- **Interfaces and unions model polymorphism** (`Node`, `SearchResult = Order | Customer`);
  always provide `__typename`-driven client fragments.
- **Enums are additive.** Adding a value is breaking for exhaustive `switch` clients only if
  they do not handle unknown values; document that clients must tolerate unknown enum values
  (see [versioning](./04-versioning-compat.md)).
- **Mutation shape**: one field per action, verb-led (`createOrder`, `cancelOrder`), returning
  a payload object with the mutated entity plus any side-effect fields. Never return the bare
  entity from a mutation.
- **Errors inside mutations**: distinguish *expected* domain failures (return in the payload as
  a union or typed error list) from *unexpected* failures (transport/GraphQL errors). Do not
  throw for validation feedback; clients then have to parse error strings.
- **Deprecate, do not delete**: `@deprecated(reason: "...")`, keep the field resolvable, and
  remove only after usage telemetry shows zero traffic and a version/sunset has passed.
- **Descriptions are documentation**; include units, ranges, and null semantics. Lint them
  (see the GraphQL style guidance in [contracts](./08-contracts-openapi.md)).

```graphql
type Query {
  order(id: ID!): Order
  orders(first: Int = 20, after: String, filter: OrderFilter): OrderConnection!
}

type Mutation {
  createOrder(input: CreateOrderInput!): CreateOrderPayload!
}

type CreateOrderPayload {
  order: Order
  userErrors: [UserError!]!
}

type UserError {
  field: [String!]
  code: OrderErrorCode!
  message: String!
}
```

**Anti-patterns**

- A single `Query { everything }` namespace with hundreds of root fields and no grouping.
- Reusing `Order` as `OrderInput` or vice versa.
- Nullable everything "to be safe"; see nullability below.
- Exposing database ids as the only identifier while `node(id:)` expects global ids.

## Nullability

Nullability is the hardest schema decision: it is expensive to change in both directions
(making nullable fields non-null is breaking; making non-null fields nullable is also breaking
for clients with non-null expectations).

- **Errors are not null by default.** Use non-null for fields your resolver can always satisfy,
  including `errors` arrays from mutations.
- **Null propagates**: if a non-null field resolves to null, null bubbles to the nearest
  nullable parent, potentially nulling a whole object. A single failing field can kill a large
  response; design for this rather than discovering it in production.
- **Prefer non-null for lists and list items when the domain guarantees them**
  (`[User!]!`), and make the list item nullable only when "missing item" is meaningful.
- **External/legacy data boundaries**: keep fields nullable where a dependency may fail, and
  return partial data; pair with error handling that records the failure rather than throwing.
- **Changing direction is a breaking change.** Treat both directions as breaking in CI diffing
  unless you control every client (see [versioning](./04-versioning-compat.md)).
- Some servers expose a `@semanticNonNull`-style directive to mean "null only on error" while
  keeping schema-level nullability; check whether your framework/client stack supports it
  before adopting (verify upstream).

## Pagination (Connections)

Use the Relay connection pattern for every list field. It gives clients a stable cursor,
cheap "next page" navigation, and a uniform shape.

```graphql
type OrderConnection {
  edges: [OrderEdge!]!
  pageInfo: PageInfo!
  totalCount: Int
}

type OrderEdge {
  node: Order!
  cursor: String!
}

type PageInfo {
  hasNextPage: Boolean!
  hasPreviousPage: Boolean!
  startCursor: String
  endCursor: String
}

type Query {
  orders(first: Int, after: String, last: Int, before: String): OrderConnection!
}
```

- **Cursors are opaque** (base64 of a sort key plus a tiebreaker). Never expose offsets as
  cursors; they drift under concurrent writes.
- **One direction per query**: forbid `first` with `last` and `after` with `before` together to
  keep ordering unambiguous.
- **Cap `first`** server-side (for example 100) and return a clear error or clamp with a
  documented rule. Do not silently paginate differently than requested.
- **`totalCount` is optional and expensive**; expose it only when the backing store can answer
  cheaply, or provide an approximate/`hasMore` alternative.
- **Ordering must be total**: append `id` as a tiebreaker so cursors never skip/duplicate items
  (same rules as [HTTP pagination](./05-pagination-filtering.md)).
- **Nested connections** multiply cost; require arguments on nested list fields that could
  return unbounded data.

## Federation

Federation lets multiple teams own types in subgraphs and compose one supergraph served by a
router. Moving to federation is an organizational decision; a single graph service is simpler.

- **Only federate when ownership is real**: multiple teams deploying independently, or a
  gateway over pre-existing services. Federating a small team's graph adds a composition and
  operations burden for no benefit.
- **Entity keys**: subgraphs that contribute fields to a type declare
  `@key(fields: "id")` (Apollo Federation 2.x; verify the exact directive set for your router
  and composition tooling). Keys must be stable and resolvable; prefer globally unique ids.
- **Referencing without ownership**: use `@external` + `@requires` carefully; move logic to the
  owning subgraph where possible. `@shareable` (Federation 2) marks value fields multiple
  subgraphs may resolve; use it deliberately, not to silence composition errors.
- **Composition is a CI gate.** Run composition in CI and reject PRs that break it; keep a
  checked-in supergraph/composition result.
- **Router vs gateway**: a router (Apollo Router, Cosmo, Hive Gateway, or an equivalent
  Rust/Go router) is the current generation; legacy gateway implementations are on a
  deprecation path. Verify the supported federation spec version before depending on new
  directives.
- **Entity resolution performance**: batching entity fetches (DataLoader or the framework's
  equivalent) is mandatory; a router will fan out entity requests per field otherwise.
- **Alternatives**: schema stitching, GraphQL Mesh, or BFF-per-client. Choose one approach and
  document why; mixing them creates duplicate type systems.

**Anti-patterns**

- Subgraphs sharing a database and calling it federation.
- A "god" subgraph owning everything while others only extend.
- Deploying a subgraph without composition checks, so the supergraph silently loses fields.

## Persisted Queries and Allow-lists

Production graphs should not accept arbitrary client documents.

- **Trusted documents / allow-lists**: build a manifest of every operation used in production
  (extracted from clients at build time), and reject unknown operations at the edge. This is the
  strongest protection against malicious queries and schema scraping.
- **Automatic Persisted Queries (APQ)**: clients send a hash and the server returns
  `PersistedQueryNotFound` so the client retries with the document; convenient but only a
  bandwidth optimization, not a security control, unless combined with an allow-list.
- **Persisted query TTL and version pinning**: invalidate manifests on schema changes and keep
  per-client versions during rollout.
- **Schema introspection**: disabling introspection in production is defense in depth, not a
  security boundary. With an allow-list, arbitrary introspection is already blocked; without
  one, attackers can reconstruct the schema from error messages.

## Depth, Cost, and Rate Limits

| Control | What it stops | Implementation notes |
|---|---|---|
| Max depth | Deeply nested relation walks | Reject over a configured depth (commonly 10-15); account for fragments |
| Max complexity/cost | Wide sibling fan-out, expensive fields | Assign per-field cost, multiply by list size arguments |
| Max aliases/batch size | Aliasing attacks (same field N times) | Count aliases per operation |
| Query timeout | Long-running resolution | Server-side deadline; return partial data or error |
| Pagination caps | Unbounded lists | Enforced `first`/`last` maximums |
| Rate limit by cost | Expensive clients | Deduct computed cost from a token bucket per subject |
| Operation allow-list | Arbitrary documents | Strongest; see persisted queries above |
| Disable batching arrays | Batched-query amplification | Reject JSON array batches unless explicitly supported |

- Compute cost **before** execution where possible, and always enforce a hard timeout during
  execution.
- Count fragmented/aliased fields once per occurrence in the response, not once per definition.
- Publish the cost model (field weights) to heavy clients so they can self-regulate.

## Authorization

- **Enforce per field**, not only per operation: a type reachable from many paths needs checks
  at the resolver or via a policy layer, not only at the root query.
- **Pass identity through context**, never through arguments. A `userId` argument is an
  authorization bypass waiting to happen; derive the subject from the token.
- **Return 200 with a partial result plus errors** for field-level authorization failures where
  the schema allows nullability; otherwise fail the whole operation. Do not return `null` for
  forbidden fields without an error entry.
- **Depth/cost limits are also authorization**: restrict expensive admin-only fields by scope
  before computing cost.
- **Subscription auth on connect** (token in the connection init payload or headers), plus
  per-message re-checks for long-lived sockets.
- Cross-tenant safety is identical to REST: scope every resolver by tenant from the token
  (see [auth](./07-auth.md)).

## Resolver Performance

- **DataLoader (or equivalent) for every relation.** N+1 queries are the default GraphQL
  failure mode; batch by key per request, with per-request cache only.
- **Persist the parsed/validated document** (query plan cache keyed by document hash) and reuse
  it across requests.
- **Avoid per-field round trips** to remote services; batch entity resolution in federation and
  cache read-heavy reference data with explicit invalidation.
- **Watch resolver fan-out in lists**: a connection of N items times a relation of M each is
  N*M calls unless batched.
- **Measure with tracing** (OpenTelemetry spans per resolver) rather than guessing which field
  dominates latency.

**Anti-patterns**

- DataLoaders cached across requests, leaking data between users.
- Throwing for expected validation errors in mutations.
- Returning arrays where a connection is required.
- Disabling depth limits because "our clients are trusted".

## Checklist

- [ ] SDL is the checked-in source of truth; clients/codegen come from it.
- [ ] Naming, input/output separation, and mutation payload shapes are consistent.
- [ ] Nullability is deliberate; both nullability directions are treated as breaking.
- [ ] Every list field is a connection with opaque cursors and capped page sizes.
- [ ] Federation (if used) has composition in CI and batched entity resolution.
- [ ] Production uses trusted documents/allow-lists; arbitrary queries are not accepted.
- [ ] Depth, cost, alias, timeout, and rate limits are configured and tested with an attack
      fixture.
- [ ] Field-level authorization; identity from context; tenant scoping.
- [ ] DataLoaders are per-request; tracing covers resolver latency.
- [ ] Deprecations carry reasons and removal is gated on usage telemetry.
