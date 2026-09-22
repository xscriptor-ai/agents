# Integration Patterns

Synchronous versus asynchronous integration, contracts, idempotency, retries, ordering, and
choreography versus orchestration.

## Sync vs Async

| Need | Choose | Why | Cost |
|---|---|---|---|
| User waits for the answer | Synchronous request/response | Simplest mental model; immediate errors | Coupling in time; failure propagates upstream |
| Work can be deferred | Async command via queue | Buffering, retry, load leveling | Eventual completion; needs status/query path |
| Notify many interested parties | Publish event | Producer does not know consumers | Eventual consistency; schema governance |
| Consistency across services | Saga (async steps) | No distributed transaction | Intermediate states; compensation logic |
| Stream of continuous data | Log/topic with consumer groups | Ordering, replay, high throughput | Operational weight; retention design |
| Third-party callback | Webhook with signature | Push instead of polling | Delivery is at-least-once; verify and dedupe |

Decision questions: Can the caller wait? Can the answer be stale? Who owns failure handling?
What happens if the callee is down for an hour? Sync chains longer than two hops deserve a hard
look — each hop multiplies availability loss.

## Interaction Styles

| Style | Payload | Consumer knowledge | Use when |
|---|---|---|---|
| Request/response (RPC) | Command/query plus result | Caller knows callee | Interactive, low-latency, simple ownership |
| Command message | Imperative, targeted | Sender knows the receiver's queue | Work distribution with retries |
| Event notification | Fact, minimal data | Producer knows nothing | Decoupling; consumers fetch if needed |
| Event-carried state transfer | Fact plus relevant state | Producer knows nothing | Consumers must not call back; read decoupling |
| Document message | Full data snapshot | Producer knows nothing | Sync/import, cache hydration |
| Stream | Continuous records | Producer knows nothing | Analytics, materialized views, CDC |

Do not publish commands as events. "OrderShipped" is an event; "ShipOrder" is a command that
belongs on a queue addressed to an owner.

## Contracts and Schema Evolution

Every integration has a contract; the contract outlives the implementation.

| Surface | Contract artifact | Compatibility gate |
|---|---|---|
| HTTP/JSON | OpenAPI 3.1 (verify current) | Schema diff in CI; additive changes only |
| gRPC | `.proto` files | Reserved fields/numbers; new package for breaks |
| Events | AsyncAPI or schema registry (Avro/JSON Schema/Protobuf; verify upstream) | Registry compatibility mode (backward/forward/full) |
| Webhooks | Documented payload plus signature scheme | Versioned event types; dual-publish during migration |
| File/batch | Schema plus validation rules | Test fixtures in both sides' CI |

Rules:

- Version schemas; never mutate a published schema in place.
- Add optional fields; do not remove, rename, or retype without a version and a migration window.
- Consumers ignore unknown fields (tolerant reader) unless strictness is the point.
- Defaults are contract: an omitted field changing behavior breaks clients.
- Consumer-driven contract tests (Pact-style; verify current tooling) catch drift where the
  producer cannot know all consumers.
- Schema registry plus CI compatibility checks beats documentation alone.

## Delivery Semantics

| Guarantee | How achieved | Reality |
|---|---|---|
| At-most-once | Fire and forget, no ack/retry | Loss on failure; rarely acceptable |
| At-least-once | Ack after durable processing; retry on failure | Duplicates; consumers must deduplicate |
| Exactly-once (effectively) | Idempotent consumer plus at-least-once transport, or transactional broker semantics | The practical target; "exactly once" is scoped to a technology pair |

Design for effectively-once: at-least-once delivery plus idempotent processing plus a dedup
store. Broker "exactly-once" features (transactional producers/consumers) help within one
broker's boundary but do not cover external side effects.

## Idempotency

An operation is idempotent if repeating it has the same effect as doing it once.

Techniques:

- **Idempotency key** — caller-generated unique key; the receiver stores `(key, result)` and
  returns the stored result on repeat. Standard for HTTP POST payments and other unsafe
  operations.
- **Natural/business key** — upsert by `(order_id, version)`; replay naturally safe.
- **Inbox table** — record processed event ids in the same transaction as the state change
  ([./06-data-architecture.md](./06-data-architecture.md)).
- **Conditional writes** — `INSERT ... ON CONFLICT DO NOTHING`, compare-and-set by version.

```sql
INSERT INTO payment_attempts (idempotency_key, order_id, status, amount, created_at)
VALUES ($1, $2, 'pending', $3, now())
ON CONFLICT (idempotency_key) DO NOTHING
RETURNING id;
```

Rules: scope keys to an owner and an operation; set a retention window and document it; return
the same response for a repeated key within the window, and a conflict error outside it. Key
external side effects (emails, charges) by business id, not by attempt.

## Timeouts, Retries, and Circuit Breaking

- **Timeouts are mandatory and explicit.** Derive them from the caller's SLO budget, not from
  library defaults. Always set a deadline and propagate it downstream (gRPC deadlines, HTTP
  timeouts).
- **Retry only idempotent operations** or operations carrying an idempotency key. Retry
  connection failures, timeouts, and 5xx/429; never retry validation errors (4xx).
- **Exponential backoff with full jitter**; cap attempts; add a retry budget (retries as a
  fraction of requests) to prevent retry storms.

```text
delay = min(cap, base * 2^attempt)
sleep = random(0, delay)          # full jitter
```

- **Circuit breaker** per dependency: open after a failure threshold, fail fast for a cooldown,
  half-open to probe; prevents pileups and gives the dependency room to recover.
- **Bulkhead** pools/timeouts per dependency so one slow callee cannot exhaust all threads or
  connections.
- **Hedged requests** only for idempotent reads with strict budgets; they add load.
- Retry at one layer only; stacked retries multiply (3 x 3 x 3 = 27 attempts).
- Dead-letter queues with alerting and an operator replay path; retrying forever is not a
  strategy.

## Ordering

Total order across a distributed system is expensive; per-key order is usually enough.

| Need | Technique |
|---|---|
| Order per aggregate | Partition key = aggregate id; broker preserves order within partition |
| Detect gaps/reorder | Monotonic sequence per aggregate on every event |
| Tolerate out-of-order arrival | Buffer/state machine keyed by sequence; reject or park older events |
| Deduplicate replays | Event id ledger (inbox) plus sequence check |
| Global order | Avoid; if truly required, single writer or single partition, with throughput ceiling |

Rules: consumers must not assume global order; producers must not change partition key over the
life of an entity (it destroys order guarantees); document the ordering scope in the event
contract.

## Choreography vs Orchestration

| Criterion | Choreography | Orchestration |
|---|---|---|
| Coupling | Event contracts only | Coordinator plus step contracts |
| Process visibility | Requires tracing/catalog | State machine is queryable |
| Change impact | New step = new subscriber | New step = coordinator change |
| Failure handling | Distributed; each service compensates itself | Centralized timeout/retry policy |
| Fits | Simple flows, fan-out, integration | Complex, long, regulated workflows |
| Risk | Hidden chains, cyclic event dependencies | Coordinator god-service, bottleneck |

Pragmatic rule: start choreographed for two or three steps; move to an orchestrated saga when
the flow gains branches, timeouts, or operators need visibility. Never mix both for the same
process without a documented reason.

## Channels, Topics, and Dead Letters

- **Queue** (point-to-point): one logical consumer group; good for commands/work.
- **Log/topic** (publish-subscribe with retention): many independent consumers, replay; good for
  events.
- Naming: `<domain>.<entity>.<event-version>` (for example `orders.order.submitted.v1`); owner
  and version visible.
- One topic per event type per bounded context keeps subscriptions and permissions manageable;
  consumer-specific routing belongs in the consumer, not the topic name.
- Dead-letter topic per consumer group, with metadata (reason, attempts, original headers) and an
  alert; replay tooling tested before the first incident.
- Retention is a design decision: replay window, cost, and privacy deletion requirements all
  apply.

CloudEvents-style envelope (verify current spec version upstream):

```json
{
  "specversion": "1.0",
  "type": "orders.order.submitted.v1",
  "source": "/orders/api",
  "id": "8f2c1e6a-0d9b-4f1a-9d1e-3f4a2b7c9e01",
  "time": "2026-03-11T09:15:00Z",
  "datacontenttype": "application/json",
  "data": { "orderId": "ord_123", "total": "42.00", "currency": "EUR" }
}
```

## Anti-Patterns

- **Chatty calls** — N+1 remote requests per user action; batch or cache or use a read model.
- **Sync chains** — five services in a synchronous call path; availability multiplies downward.
- **Retry without idempotency** — duplicate charges; the classic production incident.
- **Stacked retries** — client, gateway, and service each retrying; amplification.
- **Global ordering assumption** — code that silently depends on cross-partition order.
- **Event as RPC** — command semantics dressed as a domain event.
- **Unversioned events** — schema change breaks consumers in production.
- **Infinite dead-letter backlog** — DLQ with no alert or owner is a data loss bug with extra
  steps.
- **Shared topic free-for-all** — no owner, no schema, no permissions.

## Checklist

- [ ] Integration style chosen per interaction, with failure behavior defined.
- [ ] Every call has an explicit timeout/deadline.
- [ ] Retries only where idempotent; exponential backoff with jitter and a budget.
- [ ] Circuit breakers and bulkheads isolate dependencies.
- [ ] Delivery semantics documented; consumers deduplicate.
- [ ] Idempotency keys scoped, stored, and retained per contract.
- [ ] Ordering scope documented (per key/aggregate), sequence checks in place.
- [ ] Event schemas versioned and compatibility-checked in CI.
- [ ] DLQ per consumer with alerting and a tested replay path.
- [ ] Choreography/orchestration choice recorded per workflow.

## Related

- Reliable publication from a database: [./06-data-architecture.md](./06-data-architecture.md)
- Style-level consequences of async interaction: [./03-styles.md](./03-styles.md)
- Evolving contracts without breaking consumers: [./08-migration-evolution.md](./08-migration-evolution.md)
