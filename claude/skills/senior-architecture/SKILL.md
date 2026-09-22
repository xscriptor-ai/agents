---
name: senior-architecture
description: 'Architecture reference pack, current for 2026: ADRs, C4 modeling and
  diagrams-as-code, style selection (modular monolith, microservices, event-driven,
  serverless, CQRS/event sourcing), DDD, module boundaries and fitness functions,
  data ownership and distributed consistency (sagas, outbox, read models, data mesh),
  integration patterns, migration (strangler fig, expand-contract), quality attribute
  tradeoffs (ATAM, CAP/PACELC), and docs-as-code governance. Use when choosing or
  reviewing a system''s structure or style, writing or superseding an ADR, drawing
  C4 views, defining bounded contexts, aggregates, or domain events, enforcing dependency
  direction in CI, designing idempotent retries and ordering, planning a strangler-fig
  or expand-contract migration, running a lightweight ATAM, or keeping architecture
  docs and tech radar alive. Optional pack; consumers degrade gracefully when absent.'
---

# Architecture

Design and evolution of system structure: where the boundaries are, how parts communicate, where
state lives, and how decisions and diagrams stay true over time. This pack is opinionated about
what the industry has converged on (ADRs, C4, fitness functions, outbox, strangler fig) and
treats the rest as explicit tradeoffs against quality attributes. It covers structure and
decision-making, not framework internals; language and API specifics live in their own packs.

## Domain Overview

- **Architecture is the set of decisions that are expensive to change.** Everything else is
  implementation detail. Spend review effort where reversal cost is high.
- **No best style, only fitted tradeoffs.** Monolith versus microservices versus serverless is a
  function of team size, domain volatility, operational maturity, and quality attribute
  priorities — not fashion.
- **Boundaries follow business capabilities.** Services and modules mirror bounded contexts and
  ownership, not layers, frameworks, or the org chart alone.
- **Decisions are recorded, not remembered.** An ADR is the durable artifact; diagrams and code
  are downstream of it.
- **Distribution has a price.** Every network hop buys independent deployability and pays in
  latency, partial failure, and consistency complexity. Prefer the simplest distribution that
  meets the attributes.
- **Enforce boundaries mechanically.** Rules that live only in reviews rot; fitness functions in
  CI keep them true.
- **Evolution is incremental by default.** Strangler fig and expand-contract beat big-bang
  rewrites; every migration step is shippable and reversible.
- **Verify upstream.** Version floors below are ranges or `x` series; confirm current support in
  official docs before pinning.

## Core Rules (non-negotiable)

1. **Write the ADR before the irreversible step.** If a decision is expensive to reverse (style,
   datastore, protocol, tenancy, cloud lock-in), record context, options, decision, and
   consequences first. Never delete an ADR; supersede it (see [references/01-adr.md](references/01-adr.md)).
2. **State the quality attributes and rank them.** At least: availability, consistency, latency,
   cost, security, operability. A decision that does not name which attribute it trades against
   is not reviewable (see [references/09-quality-attributes.md](references/09-quality-attributes.md)).
3. **Cut boundaries by capability and ownership, not by technology.** A boundary that does not
   own its data and release cadence is a folder, not a boundary (see
   [references/04-ddd.md](references/04-ddd.md), [references/05-modularity-boundaries.md](references/05-modularity-boundaries.md)).
4. **Dependencies point in one direction.** Domain code never imports infrastructure or
   transport; stable modules never depend on volatile ones; no cycles between modules or
   services.
5. **Single writer per data set.** Each service/context owns its schema and is the only writer.
   Others read through APIs, events, or a read model — never by sharing tables (see
   [references/06-data-architecture.md](references/06-data-architecture.md)).
6. **Prefer synchronous request/response until async has a named reason.** Async buys
   decoupling and buffering; it pays in eventual consistency and operational surface. Write the
   reason down.
7. **Every remote call assumes failure.** Explicit timeouts/deadlines, bounded retries with
   jitter, circuit breakers, bulkheads, and idempotent operations are mandatory, not hardening
   (see [references/07-integration-patterns.md](references/07-integration-patterns.md)).
8. **Avoid distributed transactions.** Use sagas with compensations plus a transactional outbox
   (or CDC) to publish state changes; consumers deduplicate. Dual writes are a bug (see
   [references/06-data-architecture.md](references/06-data-architecture.md)).
9. **Make consistency explicit per use case.** "Eventually consistent" must name the propagation
   window and what the user sees meanwhile.
10. **Enforce boundaries with fitness functions in CI.** ArchUnit, dependency-cruiser,
    import-linter, or equivalent fail the build on violations. If it is not tested, it is not a
    rule (see [references/05-modularity-boundaries.md](references/05-modularity-boundaries.md)).
11. **Diagrams are code and live next to the code.** Structurizr DSL, PlantUML, Mermaid, or D2 in
    version control; hand-drawn exports are stale the day they are committed (see
    [references/02-c4-modeling.md](references/02-c4-modeling.md)).
12. **Migrate by strangling, not by rewriting.** Route traffic incrementally, keep old and new
    alive during coexistence, and plan decommissioning from day one (see
    [references/08-migration-evolution.md](references/08-migration-evolution.md)).
13. **Design for operability from the first commit.** SLOs, structured telemetry, and runbooks
    are architecture, not aftercare.
14. **Revisit decisions on a cadence.** ADRs marked `deprecated`/`superseded`, docs with owners
    and freshness dates (see [references/10-documentation-governance.md](references/10-documentation-governance.md)).

## Decision Tables

### Architecture style

| Situation | First choice | Notes |
|---|---|---|
| One product, one to three teams, unclear domain | Modular monolith | Enforce module boundaries in CI; service extraction stays cheap |
| Many teams, independent release cadence, clear contexts | Microservices | One service per context owner; distributed cost is real |
| Bursty, spiky, or event-heavy workloads; small team | Serverless / managed platforms | Watch cold starts, vendor lock-in, per-invocation cost |
| Audit-critical domain, temporal queries, rich history | Event sourcing with CQRS | High modeling and ops cost; not a default |
| Read/write asymmetry, heavy reporting | CQRS read models on top of the writer | Keep the write model authoritative |
| Integration across heterogeneous systems | Event-driven with a broker | Choreography for fan-out, orchestration for process state |

Details, costs, and team-size fit: [references/03-styles.md](references/03-styles.md).

### Integration style

| Need | Choose | Avoid |
|---|---|---|
| Interactive query, immediate answer, low blast radius | Synchronous HTTP/gRPC with deadline | Chaining more than two hops synchronously |
| Workflow across services, long-running process | Orchestrated saga with compensations | Distributed transaction (2PC) across services |
| Fan-out state change notification | Events via broker, transactional outbox | Dual writes to database and broker |
| Request to a specific owner with retry semantics | Command/queue with idempotency key | Fire-and-forget without dead-letter handling |
| Third-party callback | Webhooks with signatures and replay protection | Assuming exactly-once delivery |

See [references/07-integration-patterns.md](references/07-integration-patterns.md).

### Data consistency

| Use case | Model | Cost |
|---|---|---|
| Money movement within one service | ACID transaction, single writer | Vertical scaling limits |
| Cross-service workflow | Saga (orchestration or choreography) + compensation | Complexity, no isolation guarantee |
| Publish after commit | Transactional outbox (or CDC) | Extra table/connector, lag monitoring |
| Fast reads at scale | CQRS projection/read model | Rebuild tooling, staleness window |
| Analytics across domains | Data mesh / lakehouse products with contracts | Governance overhead, metadata discipline |

See [references/06-data-architecture.md](references/06-data-architecture.md).

### Boundary enforcement

| Stack | Fitness function |
|---|---|
| JVM | ArchUnit / ArchUnitTS style tests in the build |
| TypeScript/JavaScript | dependency-cruiser, ESLint `no-restricted-imports`, package `exports` |
| Python | import-linter contracts, module `__all__`, layering tests |
| Go | `internal/` packages, arch-go, import graph lint |
| Multi-repo/org | Build-system visibility rules, CODEOWNERS, review by boundary owner |

See [references/05-modularity-boundaries.md](references/05-modularity-boundaries.md).

### Migration approach

| Starting point | Approach | Guardrail |
|---|---|---|
| Monolith to services | Strangler fig with a routing facade | One seam at a time; measurable parity |
| Schema change on live data | Expand-contract (parallel change) | Old and new readers work during transition |
| New store/source of truth | CDC or backfill plus dual-read, then cut reads | Never dual-write; verify counts and lag |
| Legacy decommission | Traffic drain, flag removal, retention plan | Legal/retention sign-off before delete |

See [references/08-migration-evolution.md](references/08-migration-evolution.md).

## Reference Index

Load only what the task needs. All paths are relative to this file.

| # | Reference | Scope | Load when |
|---|---|---|---|
| 01 | [references/01-adr.md](references/01-adr.md) | ADR purpose, MADR-style template, lifecycle and statuses, repository layout, when to write one, superseding, review process | Recording or reviewing a decision, setting up `docs/adr/`, resolving a stale decision |
| 02 | [references/02-c4-modeling.md](references/02-c4-modeling.md) | C4 levels, Structurizr/PlantUML/Mermaid diagrams-as-code, context/container/component patterns, runtime and deployment views | Drawing or reviewing diagrams, onboarding, choosing a diagram tool |
| 03 | [references/03-styles.md](references/03-styles.md) | Modular monolith, microservices, event-driven, serverless, CQRS/event sourcing: decision table, costs, team-size fit | Picking or questioning an architecture style, sizing teams, justifying a split |
| 04 | [references/04-ddd.md](references/04-ddd.md) | Bounded contexts, ubiquitous language, aggregates, domain events, context mapping, when DDD is overkill | Finding boundaries, naming domains, modeling invariants, planning context maps |
| 05 | [references/05-modularity-boundaries.md](references/05-modularity-boundaries.md) | Module boundaries, dependency direction, package principles, cohesion/coupling metrics, fitness functions (ArchUnit/lint) | Enforcing layering in CI, extracting modules, reviewing dependency graphs |
| 06 | [references/06-data-architecture.md](references/06-data-architecture.md) | Data ownership per service, consistency models, sagas, transactional outbox, CQRS read models, data mesh basics | Designing state, cross-service workflows, outbox, projections, data products |
| 07 | [references/07-integration-patterns.md](references/07-integration-patterns.md) | Sync vs async, contracts and schema evolution, idempotency, retries and timeouts, ordering, choreography vs orchestration | Wiring services, hardening calls, choosing queues vs logs, fixing retry storms |
| 08 | [references/08-migration-evolution.md](references/08-migration-evolution.md) | Strangler fig, expand-contract, dual writes, incremental migration plans, coexistence, decommissioning | Replacing a system or schema, planning cutover, killing legacy |
| 09 | [references/09-quality-attributes.md](references/09-quality-attributes.md) | Quality attribute scenarios, lightweight ATAM, CAP/PACELC, consistency/latency/availability tradeoffs, risk register | Eliciting and ranking attributes, reviewing tradeoffs, writing risks |
| 10 | [references/10-documentation-governance.md](references/10-documentation-governance.md) | Docs-as-code, architecture reviews, tech radar, decision logs, keeping docs alive | Setting up docs, running reviews, curating standards, fighting doc rot |

## Loading

- **Installed agent** — `skill({ name: "architecture" })` in OpenCode; Claude Code reads
  `<skills-dir>/architecture/SKILL.md`.
- **Orchestrator** — read this file, then inject only the references the task needs.
- **Not installed** — proceed with embedded guidance, state the degraded mode, and do not invent
  pack-only content.
- **Consumers** — reference this pack as `load skill senior-architecture (optional)`.

## Port

- **Port id** — `skill://senior/architecture` (version in `metadata.port-version`).
- **Kind** — read-only reference pack; no side effects, no tools required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "architecture" })` in OpenCode; Claude Code reads `<skills-dir>/architecture/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers reference it as `load skill senior-architecture (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major.
