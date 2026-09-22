# Domain-Driven Design

Bounded contexts, ubiquitous language, aggregates, domain events, context mapping, and when DDD
is overkill.

## Strategic vs Tactical

DDD has two halves and they are independent.

| Half | Concern | Artifacts | Payoff |
|---|---|---|---|
| Strategic | Where boundaries are and who owns what | Bounded contexts, context map, ubiquitous language | Alignment of teams and models with the business |
| Tactical | How to model inside a boundary | Aggregates, entities, value objects, domain events, repositories | Correct invariants, testable domain logic |

Strategic DDD pays off almost everywhere with more than one team or a non-trivial domain.
Tactical patterns (repositories, aggregates, factories) pay off only where business rules are
complex enough to justify the indirection. Taking tactical patterns without strategic ones
produces ceremony; taking strategic ones without tactical ones is often the right call for CRUD
systems.

## Ubiquitous Language

One term, one meaning, per bounded context. The language lives in code identifiers, database
columns, API fields, events, and conversations — the same word everywhere.

- Maintain a glossary per context, not per company: the same word may legitimately differ
  between contexts ("customer" in Sales vs Support), and the difference is a boundary signal.
- Name things after the business, not after the schema: `OverdueInvoicePolicy`, not
  `InvoiceProcessorManager`.
- When domain experts and developers need a translation layer every meeting, the model is wrong
  or the boundary is in the wrong place.
- Ban synonyms in one context: if `client`, `account`, and `customer` all exist, pick one and
  rename.

## Bounded Context

A bounded context is the boundary within which a model and its language are consistent. It is a
modeling and ownership unit, not necessarily a deployment unit — one monolith can host many
contexts, and one context can span a few services if the team owns them.

Heuristics for finding contexts:

- **Linguistic** — words keep changing meaning; there is a translation when crossing.
- **Capability** — the business capability has its own rules, lifecycle, and success metric.
- **Data ownership** — one team can be the single writer for its data.
- **Rate of change** — parts of the model change for different reasons at different speeds.
- **Regulatory/trust boundary** — different compliance or access rules apply.
- **Team ownership** — a context should not be shared by two teams with equal authority
  (shared ownership erodes models).

Contexts do not map one-to-one to services, databases, or repositories. Choosing one context per
service is common, but a context may start as a module in a modular monolith (see
[./03-styles.md](./03-styles.md), [./05-modularity-boundaries.md](./05-modularity-boundaries.md)).

## Context Mapping Patterns

The context map documents relationships between contexts. Name each relationship; unlabeled
"we call them" integrations are where coupling hides.

| Pattern | Direction | Use when | Cost |
|---|---|---|---|
| Partnership | Bidirectional | Two teams must succeed or fail together on shared model changes | Coordination overhead; plan joint releases |
| Shared kernel | Bidirectional | A small, stable model subset is genuinely shared | Any change breaks both; keep it tiny |
| Customer/Supplier | Upstream -> downstream | Downstream can influence upstream priorities | Needs planning and negotiation |
| Conformist | Upstream -> downstream | Upstream will not change; downstream adopts its model | Downstream loses modeling freedom |
| Anti-corruption layer (ACL) | Downstream translates | Legacy or foreign model must not leak in | Translation code and tests to maintain |
| Open host service | Upstream exposes stable API | Many consumers need the same capability | API versioning discipline required |
| Published language | Upstream publishes documented schema | Integration via events/schemas | Schema evolution governance |
| Separate ways | None | Duplication is cheaper than integration | Duplicate data and logic |

Rules:

- Draw the map at the same zoom as the C4 context view; link it from architecture docs (see
  [./02-c4-modeling.md](./02-c4-modeling.md)).
- Every relationship has an owner on each side and a change protocol.
- Prefer ACL over conforming to a legacy model when the legacy semantics are wrong.
- Shared kernel must have an explicit change process and be small (a handful of value types, not
  an entity model).

## Aggregates

An aggregate is a consistency boundary: a cluster of objects the domain treats as one unit for
invariants. One aggregate is loaded and saved as a whole inside one transaction; the aggregate
root is the only entry point.

Rules:

- **One transaction, one aggregate.** Cross-aggregate consistency is eventual, coordinated by
  domain events and, across services, sagas.
- **Reference other aggregates by identity**, never by object reference or foreign-key navigation
  into another aggregate's internals.
- **Size by invariant, not by object graph.** If two objects never need to be consistent in the
  same instant, they are different aggregates. Most aggregates are one root plus a small
  collection.
- **Derive, do not store, what can be computed** from the aggregate's own state; store what the
  invariant needs and what queries need (the latter may live in a read model).
- **The root enforces transitions.** No setters that let callers violate invariants; expose
  intent-revealing operations (`order.submit()`, not `order.status = "submitted"`).
- **Keep aggregates in memory only as long as the use case needs**; avoid session-long object
  graphs and lazy-loading webs.

Aggregate checklist for a candidate:

- [ ] Can you name the invariant in business language?
- [ ] Does the invariant need all the members to be checked atomically?
- [ ] Does the unit fit comfortably in one transaction on the expected scale?
- [ ] Are all external references by id?
- [ ] Is there a single root through which all changes flow?

If an invariant spans aggregates, model it as a process (saga) or accept eventual consistency,
rather than merging aggregates into a distributed transaction.

## Tactical Building Blocks

| Building block | Definition | Notes |
|---|---|---|
| Entity | Identity that persists across state changes | Equality by id, not attributes |
| Value object | Immutable descriptive value | Equality by value; replace, never mutate |
| Aggregate root | Entity that guards the consistency boundary | Only allowed handle on the aggregate |
| Domain event | Past-tense fact meaningful to domain experts | Name in business terms; version as a contract |
| Domain service | Operation that spans objects and has no natural home | Stateless; not a dumping ground for logic |
| Repository | Collection-like access to aggregates | One per aggregate root; hides persistence |
| Factory | Encapsulates complex creation/invariants | Useful when constructors would take too much |
| Policy/Specification | Named business rule object | Useful for configurable rules and tests |

Persistence mapping stays outside the domain model (repository implementations are adapters),
keeping the domain free of framework and storage concerns (see
[./05-modularity-boundaries.md](./05-modularity-boundaries.md)).

## Domain Events

Domain events express what happened in the language of the business: `OrderSubmitted`,
`PaymentCaptured`, `ShipmentDelivered`. They serve three purposes: decoupling within a process,
consistent integration across contexts, and audit/analysis.

- Name with past tense and business meaning; include the aggregate id, occurred-at timestamp,
  and a schema version.
- Distinguish **domain events** (internal, fine-grained, may change) from **integration events**
  (published, versioned, contract-governed). Translate between them; do not publish raw internal
  events.
- Publish reliably via transactional outbox or CDC, never dual-write
  ([./06-data-architecture.md](./06-data-architecture.md)).
- Consumers are idempotent and order-aware per aggregate id
  ([./07-integration-patterns.md](./07-integration-patterns.md)).
- Enrich events enough for consumers to act without callbacks; keep payloads a stable contract.

## Event Storming

A lightweight modeling workshop to discover the domain quickly.

| Phase | Focus | Output |
|---|---|---|
| Chaotic exploration | Stick every domain event on a timeline | Shared story of the process |
| Timelines | Order events, mark alternative paths | Happy path plus branches |
| Pain points | Mark hotspots, bottlenecks, unknowns | Questions for domain experts |
| Commands/policies | What triggers each event; which rules apply | Commands, policies, aggregates sketch |
| Boundaries | Look for linguistic shifts and ownership | Candidate bounded contexts |

Practical guidance: 2-4 hours, domain expert in the room (mandatory), one facilitator, no
laptops; use a physical or digital board and keep the result as an artifact. Follow up with a
context map and candidate aggregates, then validate against real use cases.

## When DDD Is Overkill

Do not pay tactical DDD costs on simple domains.

| Signal | Interpretation |
|---|---|
| Mostly CRUD with validation | Skip tactical patterns; use a thin service layer and a read model |
| One team, simple domain, short lifetime | Strategic sketch is enough; no context map ceremony |
| No access to domain experts | You cannot build a real model; lean on data and simple rules |
| Rules are configuration, not logic | A rules table/engine beats an object model |
| Reporting/WIP analytics systems | Model for queries, not for invariants |
| Prototype or spike | Timebox; do not build aggregates for throwaway code |

A pragmatic middle ground: strategic boundaries and ubiquitous language always; aggregates and
repositories only where an invariant list justifies them. Simple contexts can use active
record/transaction script and still be well-bounded.

## Anti-Patterns

- **Big ball of mud** — no boundaries, shared language drift, everything depends on everything.
- **Anemic domain model everywhere** — getters/setters plus services holding all logic; DDD
  costs without DDD benefits, or a sign the domain is simple.
- **Entity equals table** — one class per table with database-driven modeling; invariants leak.
- **Aggregate as whole object graph** — loading half the database per transaction; lock
  contention and memory blowups.
- **Shared kernel creep** — the "shared" model grows until it is the system.
- **Leaky ACL** — legacy concepts exposed directly to consumers; translation skipped "for now".
- **Event explosion** — pulsing every field change as a public event with no versioning or
  ownership.
- **Context equals team org chart** — boundaries drawn by reorg rather than domain; they change
  with every reorganization.

## Checklist

- [ ] Ubiquitous language glossary exists per context.
- [ ] Context map names every relationship and pattern.
- [ ] Each context has an owner team and single-writer data.
- [ ] Aggregates justified by named invariants; ids used across aggregates.
- [ ] Domain events are past-tense, business-named, and versioned.
- [ ] Integration events are separated from internal domain events.
- [ ] Event publication is outbox-based, not dual-write.
- [ ] Tactical patterns applied only where complexity warrants.
- [ ] Model validated with domain experts, not just developers.

## Related

- Choosing an architecture style for the contexts: [./03-styles.md](./03-styles.md)
- Enforcing context and package boundaries: [./05-modularity-boundaries.md](./05-modularity-boundaries.md)
- Consistent data and event publication: [./06-data-architecture.md](./06-data-architecture.md)
- Contracts and messaging between contexts: [./07-integration-patterns.md](./07-integration-patterns.md)
