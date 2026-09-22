# Architecture Styles

Style selection across modular monolith, microservices, event-driven, serverless, and
CQRS/event sourcing, with costs and team-size fit.

## Style Selection Table

| Situation | First choice | Why | Primary cost |
|---|---|---|---|
| 1-3 teams, young domain, unclear boundaries | Modular monolith | Fast feedback, cheap refactoring, no distributed failure | Boundaries need discipline to stay real |
| Clear bounded contexts, independent release needs, 4+ teams | Microservices | Independent deployability, team autonomy | Distributed systems complexity, platform investment |
| High fan-out, temporal decoupling, streaming data, audit needs | Event-driven | Loose coupling, buffering, replay | Eventual consistency, broker operations, ordering |
| Spiky or unpredictable load, small team, glue workloads | Serverless / managed | Pay per use, no servers to patch, fast start | Cold starts, runtime limits, lock-in, local dev friction |
| Read/write asymmetry, temporal queries, high audit bar | CQRS + event sourcing | Full history, independent read scaling | Modeling difficulty, projections, versioning events |
| Mixed: different attributes per capability | Modular monolith as core + selectively extracted services | Pay distributed cost only where it buys something | Two operating models to teach |
| Regulatory or latency-bound monolith | Keep monolith, scale vertically and by cell | Simplicity is a feature | Scaling ceiling; plan cellular decomposition |

Default unless a specific driver says otherwise: **modular monolith**. A well-bounded monolith
is the cheapest correct answer for most products, and it keeps the option to extract services
later (see [./05-modularity-boundaries.md](./05-modularity-boundaries.md)).

## Modular Monolith

One deployable unit, real internal boundaries: modules own their data and expose explicit
interfaces; cross-module calls go through those interfaces only.

Practices that make it a real style rather than a folder convention:

- One module per bounded context or capability, each with a public API package and private
  internals (see [./04-ddd.md](./04-ddd.md)).
- Enforced dependency direction with fitness functions in CI
  ([./05-modularity-boundaries.md](./05-modularity-boundaries.md)).
- No cross-module database access: a module owns its tables; others use its API.
- In-process events for decoupling within the boundary where useful.
- One build, one deploy, one database cluster is acceptable; schema-level separation by module
  makes extraction possible later.

Costs and limits:

- One release train for all modules; feature flags partially compensate.
- A noisy module can degrade the whole process (memory, threads); process-level isolation is
  absent.
- Scaling is whole-process unless you shard or run multiple deployment cells.

Fits when: fewer than roughly 3-4 teams, domain still churning, operational platform is thin,
and time-to-market dominates.

## Microservices

Independent services aligned to bounded contexts, each owning its data and deployable on its own
cadence.

Prerequisites before splitting (all of them, not most):

- A stable platform: CI/CD per service, centralized logs/metrics/traces, service discovery or
  gateway, secrets management, IaC.
- On-call ownership per service; a service without an owner decays.
- Contract discipline: versioned APIs and events, consumer-driven tests (see
  [./07-integration-patterns.md](./07-integration-patterns.md)).
- Data ownership rules: single writer per data set; no shared tables
  ([./06-data-architecture.md](./06-data-architecture.md)).
- SLOs per service and error budgets; otherwise nobody knows what "healthy" means.

Decomposition rules:

- One service per bounded context first, not per entity; entities become aggregate boundaries
  inside a service.
- Split by rate of change and scaling needs, not by layer.
- Prefer wide services (a context) over many narrow CRUD services; nanoservices multiply
  operational cost without buying autonomy.
- Extract from a modular monolith along module seams once a driver exists: independent scaling,
  different compliance scope, or release contention.

Costs:

- Partial failure everywhere; every call needs timeout/retry/idempotency.
- Distributed data means sagas, outbox, and eventual consistency.
- Debugging crosses process and team boundaries; tracing is mandatory.
- Per-service overhead: repos, pipelines, dashboards, on-call rotations.

Fits when: 4+ teams sharing a product, distinct release/scaling/compliance needs per context,
and the platform team exists to carry the operational load.

## Event-Driven Architecture

Components communicate by producing and consuming events (facts) through a broker, decoupling
producers from consumers in time and identity.

| Variant | Shape | Use when |
|---|---|---|
| Event notification | Thin event, consumer fetches details | Low coupling, but chatty and ordering-sensitive |
| Event-carried state transfer | Event carries the data consumers need | Consumers must not call back; breaks read coupling |
| Event sourcing | Events are the source of truth; state is a fold | Audit, temporal queries, rebuildable projections |
| Publish/subscribe fan-out | Many independent consumers | Notifications, projections, integrations |
| Stream processing | Continuous transformation/aggregation | Analytics, enrichment, materialized views |

Broker choice shape (verify specific products and versions upstream):

- **Log-based** (Kafka-compatible, Pulsar, NATS JetStream): ordered per partition, replayable,
  retention by time/size — good for event streaming and rebuildable consumers.
- **Queue-based** (SQS-compatible, RabbitMQ-style): per-message ack, competing consumers,
  simpler routing — good for work distribution and commands.
- **Brokerless cloud events** (EventBridge-style routers): low ops, coarse guarantees — good for
  integration fan-out, weak ordering.

Costs: eventual consistency, at-least-once delivery (consumers must deduplicate), schema
evolution discipline, replay safety, and a broker that becomes critical infrastructure.

## Serverless and Managed Platforms

Functions, managed containers, and managed data services where the platform owns scaling and
patching.

Good fit:

- Bursty or low-volume workloads where idle capacity is waste.
- Glue and automation: scheduled jobs, webhooks, file processing, queue consumers.
- Small teams without a platform group.

Costs and cautions:

- Cold starts and execution limits shape design (per-request latency, duration caps, payload
  sizes); verify current limits upstream per provider.
- Local development and debugging are weaker; emulators drift from production behavior.
- Vendor lock-in is real at the integration layer (identity, queues, storage triggers); isolate
  with ports and adapters if portability matters.
- Cost can invert at sustained high utilization; model it, do not assume.
- State is the hard part: use managed state deliberately, and avoid functions calling functions
  in long chains (use queues or workflows).

## CQRS and Event Sourcing

| Aspect | CQRS | Event sourcing |
|---|---|---|
| What it is | Separate write model from read models | State stored as an append-only event log |
| Buys | Independent read scaling, tailored read shapes | Audit, temporal queries, replay, projections |
| Costs | Projection pipeline, staleness, eventual consistency | Event versioning, snapshots, storage growth, steep learning curve |
| Pair with | Read models, caches | CQRS projections, outbox, schema registry |
| Avoid when | Simple CRUD, strongly consistent UI needs | No audit/temporal driver, small domain, team unfamiliar |

CQRS rules of thumb:

- Keep one authoritative write model per aggregate; read models are disposable and rebuildable.
- Define the freshness contract for each read model; the UI must handle the lag.
- Version events from day one; events are a public contract.

Event sourcing rules of thumb:

- Events are facts in past tense; never edit or delete them (compensate instead).
- Snapshot for performance, not for correctness.
- Do not expose the raw event store to other services; publish integration events via outbox.
- Treat schema evolution as a first-class problem (upcasting, weak schema, versioned types).

Details: [./06-data-architecture.md](./06-data-architecture.md).

## Team-Size Fit

Approximate guidance; team topologies and domain complexity matter more than headcount.

| Engineering teams (stream-aligned) | Credible styles |
|---|---|
| 1 team (3-9 people) | Modular monolith, serverless where it fits; one deployable is strength |
| 2-3 teams | Modular monolith with strict modules; extract at most 1-2 services with clear drivers |
| 4-8 teams | Microservices for domains with independent cadence; keep shared kernel small |
| 8+ teams | Microservices plus platform team; enforce context map, service catalog, SLO ownership |
| Any size, high audit | Event sourcing/CQRS only where the audit driver is explicit |

## Cost and Complexity Comparison

| Style | Runtime coupling | Data consistency | Ops surface | Cognitive load | Time to first release |
|---|---|---|---|---|---|
| Modular monolith | High (same process) | Strong (local ACID) | Low | Moderate | Fast |
| Microservices | Low per pair, high in aggregate | Eventual across services | High | High | Slow without platform |
| Event-driven | Very low | Eventual; ordering constraints | Medium-high | Moderate-high | Medium |
| Serverless | Very low | Depends on managed stores | Low-medium | Moderate | Fast for small scopes |
| CQRS/ES | Medium-low | Eventual for reads | Medium-high | High | Slow |

## Migration Pointers

- Monolith -> services: strangler fig with a routing facade; one seam at a time
  ([./08-migration-evolution.md](./08-migration-evolution.md)).
- Add events: transactional outbox first; do not dual-write
  ([./06-data-architecture.md](./06-data-architecture.md)).
- Move reads off the write model: CQRS projection behind an existing API, then swap the read path.
- Introducing event sourcing mid-flight: start with one aggregate and a versioned event stream,
  never a big-bang rewrite.

## Anti-Patterns

- **Distributed monolith** — services that must deploy together and share a database; the worst
  of both styles.
- **Resume-driven architecture** — choosing a style to learn it; choose against attributes.
- **Nanoservices** — one entity per service; the network becomes the call stack.
- **Shared database across services** — contract-by-table; every schema change breaks callers.
- **Event soup** — hundreds of event types with no ownership or schema discipline.
- **Serverless for sustained high load** — cost inversion and limit fights; model the workload.
- **CQRS everywhere** — read models for simple CRUD add lag and infrastructure for nothing.
- **Big-bang rewrite** — replacement projects that lose feature parity forever.

## Checklist

- [ ] Style justified against ranking quality attributes, not preference.
- [ ] Team topology and size match the operating model the style requires.
- [ ] Boundaries align with bounded contexts and data ownership.
- [ ] Failure and consistency behavior defined for every distributed hop.
- [ ] Platform prerequisites present before splitting (CI/CD, telemetry, IaC, on-call).
- [ ] Migration path incremental and reversible; no dual writes.
- [ ] Cost model covers infrastructure and cognitive load, not just compute.
- [ ] Exit criteria documented for any temporary hybrid.

## Related

- Finding the contexts to cut along: [./04-ddd.md](./04-ddd.md)
- Enforcing the boundaries inside the chosen style: [./05-modularity-boundaries.md](./05-modularity-boundaries.md)
- Consistency and data ownership mechanics: [./06-data-architecture.md](./06-data-architecture.md)
- Deciding with attributes and risks: [./09-quality-attributes.md](./09-quality-attributes.md)
