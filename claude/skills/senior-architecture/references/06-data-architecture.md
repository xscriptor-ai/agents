# Data Architecture

Data ownership per service, consistency models, sagas, transactional outbox, CQRS read models,
and data mesh basics.

## Ownership: The Single-Writer Rule

Every data set has exactly one writer — one service, module, or context that owns its schema,
its invariants, and its write path. Everyone else reads it through an API, an event stream, or
their own derived read model.

- The owner controls schema evolution; consumers control nothing about the schema.
- No shared tables between services, ever. A shared table is a hidden distributed transaction
  waiting to break release independence (see [./03-styles.md](./03-styles.md)).
- Cross-context reads that need many entities are an argument for a read model or a query
  service, not for a join across ownership lines.
- Be explicit about derived data: who rebuilds it, from what, and how stale it may be.
- Classify data (PII, financial, operational) at the owner, with retention and residency rules
  attached to the owning service.

## Consistency Model Selection

| Use case | Model | Mechanism | Notes |
|---|---|---|---|
| Invariants within one aggregate/service | Strong (ACID) | Local transaction | Preferred default; keep transactions short |
| Workflow across aggregates, same service | Usually strong | One transaction or saga with domain events | Prefer one transaction where feasible |
| Workflow across services | Eventual | Saga with compensations | No isolation; design for intermediate states |
| Publish state changes to others | Eventual | Transactional outbox or CDC | Never dual-write |
| Fast, denormalized reads | Eventual | CQRS projection | Freshness contract per read model |
| Inventory/reservation, money movement | Serialize at one writer | Owner-side reservation or single partition | Avoid distributed locking across services |
| Analytics across domains | Eventual, batch or streaming | Data products / lakehouse | Governance and contracts required |

Questions to answer for every eventual path: how stale can it be, what does the user see in the
window, and what happens when propagation is late or lost.

## Local Transactions and Aggregate Boundaries

- One transaction per aggregate is the default; keep it inside one service and one datastore.
- Transactions should be short: no remote calls inside a transaction, no waiting on user input.
- Isolation level is part of the design: know whether the store gives read-committed or
  snapshot semantics, and how the code behaves on write conflicts (retry, fail, or merge).
- If a business invariant spans aggregates, model the process explicitly (saga) rather than
  stretching a transaction across a network.
- Optimistic concurrency (version columns, ETags) is the usual tool for lost-update prevention;
  use it at aggregate roots.

## Sagas

A saga is a sequence of local transactions with compensating actions. Two coordination styles:

| Aspect | Orchestration | Choreography |
|---|---|---|
| Control | Central coordinator/state machine | Each service reacts to events |
| Visibility | Process state queryable in one place | Emergent; requires tracing and event catalog |
| Coupling | Services depend on coordinator contract | Services depend on event contracts only |
| Complexity | Grows in the coordinator | Grows in the network of interactions |
| Best for | Complex, long, visible workflows (money, fulfillment) | Simple, linear, few-step flows and fan-out |
| Watch out | Coordinator becomes a god service | Event chains become hard to reason about |

Saga rules:

- Every step must be **idempotent** and **compensable**, or explicitly non-compensable with a
  business-approved fallback (for example manual review queue).
- Compensations are semantic undo, not rollback: a refund is not an un-charge.
- Timeouts and no-response handling are first-class transitions; "stuck saga" is a failure mode
  with an alert and an operator path.
- Persist saga state durably; the process must survive restarts.
- Keep steps small; one step = one local transaction plus one message.

Minimal orchestration shape (pseudocode):

```text
on OrderSubmitted(orderId):
  state[orderId] = RESERVING
  send ReserveStock(orderId, items)

on StockReserved(orderId):
  state[orderId] = CHARGING
  send ChargePayment(orderId, amount)

on PaymentDeclined(orderId, reason):
  state[orderId] = COMPENSATING
  send ReleaseStock(orderId)

on StockReleased(orderId):
  state[orderId] = CANCELLED
```

Choreography is the same flow expressed as event subscriptions; document the event graph and
give each event an owner.

## Transactional Outbox

Problem: writing to your database and publishing to a broker are two systems; a crash between
them loses or duplicates work. A dual write is a correctness bug, not a tuning issue.

Solution: write the event to an outbox table **in the same local transaction** as the state
change; a relay publishes it and marks it sent. Consumers deduplicate.

```sql
CREATE TABLE outbox (
  id            UUID PRIMARY KEY,
  aggregate_id  TEXT NOT NULL,
  aggregate_seq BIGINT NOT NULL,     -- per-aggregate ordering
  type          TEXT NOT NULL,
  payload       JSONB NOT NULL,
  occurred_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at  TIMESTAMPTZ,
  attempts      INT NOT NULL DEFAULT 0
);
CREATE INDEX outbox_unpublished ON outbox (occurred_at) WHERE published_at IS NULL;
```

Relay options (verify current tooling upstream):

- **Polling publisher** — periodic `SELECT ... WHERE published_at IS NULL ORDER BY occurred_at
  LIMIT n` with `FOR UPDATE SKIP LOCKED`; simple, adds small lag, needs an index and cleanup.
- **Log tailing / CDC** — Debezium-style connector or managed CDC reads the write-ahead log and
  publishes changes; lower latency, more moving parts, schema coupling to the outbox table.
- **Database-native queue features** — some stores offer notification/job tables (Postgres
  `LISTEN/NOTIFY`, `pg_notify` limits) — useful as a wake-up signal, not a durable queue alone.

Outbox rules:

- Same transaction as the business write; no exceptions.
- Publish order per aggregate via `aggregate_seq`; global ordering is neither needed nor
  scalable.
- At-least-once delivery: consumers must be idempotent by event id.
- Retain until published plus a replay window; archive or purge with a documented policy.
- Monitor lag (oldest unpublished row age) and dead letters; alert on both.
- The outbox relay is infrastructure, not a business process; keep it boring.

## Idempotent Consumers (Inbox)

Every consumer stores processed event ids and ignores duplicates.

```sql
CREATE TABLE inbox (
  consumer    TEXT NOT NULL,
  event_id    UUID NOT NULL,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (consumer, event_id)
);
```

- Apply the state change and the inbox insert in one local transaction.
- Prune the inbox by retention window tied to the broker's max redelivery horizon.
- Prefer deterministic, idempotent operations (upserts keyed by business id) so replays are
  naturally safe; the inbox table is the backstop.
- Deduplicate side effects (emails, payments) by a business key, not only by event id.

## CQRS Read Models

Read models are denormalized, disposable stores optimized for specific queries. They are
projections of events or of source tables.

- One read model per query shape; do not build a general-purpose replica and call it CQRS.
- Freshness contract: state the acceptable lag per read model and expose it where users care
  ("as of 2 seconds ago" beats silent staleness).
- Projections must be idempotent and rebuildable from the source of truth; keep a rebuild
  runbook and test it.
- Track projection position per consumer, not globally; different models advance independently.
- Handle out-of-order and late events with per-aggregate sequencing
  ([./07-integration-patterns.md](./07-integration-patterns.md)).
- Schema migrations for read models are safe to run offline (drop and rebuild) — that is their
  advantage; use it.

## Event Sourcing (Data View)

State is derived from an append-only log of domain events.

- The event store is the system of record; all other stores (including read models) are derived.
- Events are immutable; corrections are new compensating events.
- Snapshots are a performance optimization only; never the source of truth.
- Version event schemas from the first release; support upcasting on read.
- Do not expose the internal event stream as a public integration API; publish translated
  integration events via outbox.
- Storage grows forever unless you accept archival with replay-from-archive procedures.

## Polyglot Persistence and Storage Choice

Choose per access pattern and ownership, not per fashion.

| Need | Store shape | Notes |
|---|---|---|
| Transactional core, complex invariants | Relational (ACID) | Default; mature tooling and consistency |
| Massive key-value access at low latency | KV store | Design for partition key; limited query flexibility |
| Full-text and faceted search | Search index | Derived; rebuildable; never a system of record |
| Flexible documents per aggregate | Document store | Validate invariants in code; careful with cross-doc consistency |
| Time-series/metrics | TSDB or columnar | Retention and downsampling policies up front |
| Analytics/lakehouse | Open table formats (Iceberg/Delta/Hudi class; verify upstream) | Schema evolution and time travel; catalog needed |
| Graph relationships | Graph store | Only when traversals dominate; otherwise relational works |

Derived stores must have an owner, a rebuild path, and acceptable-loss classification.

## Data Mesh Basics

For analytics at organizational scale, data mesh shifts ownership to domains:

1. **Domain ownership** — business domains own and publish their data products.
2. **Data as a product** — discoverable, addressable, trustworthy, self-describing, with SLAs.
3. **Self-serve platform** — paved road for storage, pipelines, catalogs, access control.
4. **Federated computational governance** — global standards (contracts, lineage, privacy)
   enforced automatically.

Use it when: many domains, analytics bottlenecked on a central team, strong platform in place.
Do not use it as a license for every team to buy its own warehouse; without the platform and
governance pillars it degenerates into data sprawl. For a single product team, a single lakehouse
with clear ownership beats mesh ceremony.

## Anti-Patterns

- **Shared database** — integration through tables; every schema change is a cross-team break.
- **Dual write** — DB commit plus broker publish outside a transaction; lost or duplicated events.
- **Event-as-command** — publishing "do this" events with an assumed single consumer; that is an
  RPC with extra steps.
- **Read model as source of truth** — someone writes to a projection; rebuilds destroy data.
- **Saga without compensations** — steps that fail leave inconsistent state with no operator
  path.
- **Unbounded outbox** — no retention, no lag alert, table grows until the relay dies.
- **Cross-service joins** — fan-out reads to N services per request; use a projection.
- **Mesh without platform** — each team building its own pipelines; duplication and drift.

## Checklist

- [ ] One writer per data set; ownership documented per service.
- [ ] Consistency model named per use case, with staleness windows.
- [ ] Cross-service workflows are sagas with idempotent steps and compensations.
- [ ] All state changes publish via outbox or CDC; no dual writes.
- [ ] Consumers deduplicate (inbox or deterministic upsert); side effects keyed.
- [ ] Outbox lag and dead letters monitored with SLOs.
- [ ] Read models rebuildable, with tested rebuild runbook and freshness contract.
- [ ] Event schemas versioned; compatibility checked in CI.
- [ ] Data classification, retention, and residency rules attached to owners.
- [ ] Derived stores have owners and acceptable-loss classification.

## Related

- Style choice and service data ownership: [./03-styles.md](./03-styles.md)
- Delivery guarantees, ordering, and retry semantics: [./07-integration-patterns.md](./07-integration-patterns.md)
- Attribute tradeoffs behind consistency decisions: [./09-quality-attributes.md](./09-quality-attributes.md)
- Migrating ownership and stores safely: [./08-migration-evolution.md](./08-migration-evolution.md)
