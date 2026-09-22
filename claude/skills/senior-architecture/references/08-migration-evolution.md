# Migration and Evolution

Strangler fig, expand-contract, dual writes, incremental migration plans, coexistence, and
decommissioning.

## Principles

- **Incremental over big-bang.** Every migration step ships to production and is reversible.
- **Coexist, then cut over, then decommission.** Three distinct phases with separate exit
  criteria.
- **Measure parity.** Migrated behavior is verified against the old system (shadow traffic,
  dual-read comparison) before it carries real load.
- **Migrate one seam at a time.** A seam is a route, an entity, a queue, a capability — small
  enough to finish and revert in days.
- **Decisions first.** Record the target, the approach, and the rejected options in an ADR (see
  [./01-adr.md](./01-adr.md)).
- **Decommission is part of the plan.** A migration without a removal date is permanent dual
  maintenance.

## Approach Selection

| Situation | Approach | Primary guardrail |
|---|---|---|
| Replace a legacy system or component | Strangler fig with a routing facade | One seam per iteration; parity metrics visible |
| Change a live database schema | Expand-contract (parallel change) | Old and new code both work at every step |
| Swap a library or implementation behind a stable interface | Branch by abstraction plus feature flag | Flag owner and removal date |
| Migrate data to a new store | Backfill plus dual-read, then cut reads; CDC for continuous sync | Reconcile counts and checksums; never dual-write |
| Module to service inside a monolith | Extract along an enforced module seam | Module boundary already tested in CI |
| Change an API contract | Additive version plus sunset window | Telemetry on old-version usage before removal |
| Moving workloads to a new platform | Shadow traffic, then canary, then progressive rollout | Rollback path and cost comparison per stage |
| Full rewrite for a small, low-risk system | Big-bang (rare) | Freeze, migrate, verify, old system read-only |

A rewrite is attractive and usually wrong: the old system embeds years of undocumented rules. If
a rewrite is truly chosen, run it behind the same strangler facade as any replacement.

## Strangler Fig

Put a facade in front of the legacy system and route traffic incrementally to the new
implementation until the legacy system has no callers.

Steps:

1. **Identify seams.** Start with read-only, low-blast-radius routes (reporting, search) before
   write paths.
2. **Introduce the facade.** A gateway, reverse proxy, or adapter layer that can route by path,
   header, tenant, or percentage. Keep it dumb: no business logic in the facade.
3. **Implement the new capability** behind the facade, integrated with the legacy system only
   through APIs/events, never shared tables.
4. **Dual-run and compare.** Shadow traffic to the new path; log differences; fix until parity
   is acceptable. Compare business outcomes, not just HTTP codes.
5. **Shift traffic progressively.** Internal users, then 1%, then cohorts/tenants, then all.
6. **Freeze the legacy path.** Reject new features on the legacy side; all changes go to the new
   implementation.
7. **Decommission.** Drain traffic, delete code, drop data per retention rules (see below).

Routing strategies:

| Strategy | Use when | Notes |
|---|---|---|
| Path prefix | Coarse split, easy to operate | Fast, visible; needs URL stability |
| Header/claim (tenant, user agent) | Pilot with selected tenants | Good for enterprise rollouts; easy rollback |
| Percentage / weighted | Gradual load shift | Track error/latency parity per cohort |
| Feature flag in-app | Migrating internal calls | Dead flags accumulate; enforce removal dates |
| Message replay split | Queue/topic consumers | Run old and new consumers on shadow topics |

Facade anti-patterns to avoid: accumulating translation logic (put it in an adapter service),
routing rules in multiple places, and no telemetry on which path served a request.

## Expand-Contract (Parallel Change)

Any change to data or an interface that old and new callers cannot agree on must pass through
three phases.

1. **Expand** — add the new shape without removing the old. New optional column, new field, new
   event version, new endpoint. Deploy readers/writers that tolerate both.
2. **Migrate** — backfill existing data or dual-write temporarily, verify, then switch reads and
   writes to the new shape.
3. **Contract** — remove the old shape only after telemetry proves zero usage and the rollback
   window has passed.

Database example (rename `name` to `full_name`):

```sql
-- Phase 1: expand
ALTER TABLE customer ADD COLUMN full_name TEXT;
-- application writes both name and full_name; reads prefer full_name when present

-- Phase 2: backfill, then stop writing the old column
UPDATE customer SET full_name = name WHERE full_name IS NULL;

-- Phase 3: contract, after zero reads/writes of name for one full release cycle
ALTER TABLE customer DROP COLUMN name;
```

Rules:

- Never add a NOT NULL column without a default/backfill plan for existing rows.
- Destructive changes (`DROP`, narrowing types, tightening constraints) are contract-phase only.
- Test the rollback: at every phase, the previous application version must still work.
- Django/Rails/Alembic-style migration tools run each phase as its own deployable migration. Do
  not bundle expand and contract in one release.
- For APIs: deprecation and sunset headers plus usage telemetry before removal.

## Dual Writes

Writing to two systems without a shared transaction is a correctness hazard: partial failure,
out-of-order writes, and divergent state.

| Scenario | Verdict |
|---|---|
| Application writes DB and publishes an event | Never. Use transactional outbox or CDC |
| Application writes old and new database during migration | Avoid. Use CDC/backfill or outbox-driven sync |
| Temporary dual-write with reconciliation and a hard end date | Acceptable only with explicit owner, metric, and deadline |
| Analytics/projection writes | Not dual writes; derive from the event stream |

When a temporary dual write is unavoidable, make one side authoritative, reconcile continuously
(counts, checksums, sampled rows), alert on divergence, and record the end date in the migration
plan. Prefer CDC (log-tailing) so the second store is a derived projection, not a peer writer
(see [./06-data-architecture.md](./06-data-architecture.md)).

## Data Migration Mechanics

| Step | Purpose | Evidence |
|---|---|---|
| Inventory | Know every table, column, and consumer | Data map with owners |
| Backfill | Populate the new store/shape | Rows processed, lag, error rate |
| Reconcile | Prove equivalence | Counts, aggregates, checksum samples, business metrics |
| Shadow reads | Compare without user impact | Diff rate under threshold |
| Cutover reads | Serve from the new source | Error/latency parity dashboards |
| Cutover writes | Single writer switches | No dual writes remain |
| Freeze legacy | Prevent new dependencies | Access logs show no writes |
| Decommission | Remove cost and risk | Retention/legal sign-off |

Cutover strategies: per-tenant (recommended for B2B), per-region, per-entity range, or
percentage of traffic. Avoid a global flag-day cutover unless the dataset is small and the
rollback is rehearsed.

## Coexistence Rules

While old and new run in parallel:

- **One authoritative writer per data set at any time.** Name it; everyone else reads.
- Contract-first integration: version the interface between old and new; never share tables.
- Data sync direction is one-way or explicitly bi-directional with conflict resolution rules
  (last-write-wins is a decision with consequences — record it).
- Feature parity is tracked as an explicit list; unparity items have owners and deadlines, not
  vague "later".
- Cost is dual: monitor both systems' spend and the platform bill increase during coexistence.
- Incident response knows which system is authoritative for each capability; update runbooks.

## Decommissioning

The last phase is the one most often forgotten; unfinished decommissioning becomes permanent
complexity.

Checklist before removal:

- [ ] Traffic telemetry shows zero real users (not just zero errors) for the agreed window.
- [ ] All consumers migrated and notified; no SDK/API key/queue subscriber remains.
- [ ] Data retention and legal requirements satisfied — archive where required, delete per
      policy (GDPR/CCPA-style erasure duties), document destruction.
- [ ] Backups and restore procedures updated; old system removed from DR plans.
- [ ] Monitoring, dashboards, alerts, and on-call entries removed.
- [ ] Code, feature flags, routing rules, IaC, DNS entries, certificates, and secrets deleted.
- [ ] Docs, diagrams, ADRs, and the service catalog updated
      ([./02-c4-modeling.md](./02-c4-modeling.md), [./10-documentation-governance.md](./10-documentation-governance.md)).
- [ ] Cost center, licenses, and contracts terminated.
- [ ] Post-migration review recorded; lessons fed into the next migration.

## Migration Plan Template

| Phase | Deliverable | Exit gate | Rollback |
|---|---|---|---|
| 0. Decide | ADR plus plan | Stakeholders agree on target and guardrails | n/a |
| 1. Prepare | Facade, contracts, telemetry, test data | Parity harness runs in CI | n/a |
| 2. Shadow | New path runs on copied traffic | Diff rate under threshold | Disable shadow |
| 3. Pilot | Real traffic for a small cohort | Error/latency/business parity | Route back via facade |
| 4. Progressive | 1% -> 10% -> 50% -> 100% | Stages hold for the agreed soak time | Weight back to legacy |
| 5. Freeze | Legacy read-only | No legacy writes for a release cycle | Re-open if blocked |
| 6. Decommission | Systems removed | Legal/retention sign-off | Restore from archive if needed |

## Anti-Patterns

- **Big-bang cutover** — one flag day, no rollback, all-or-nothing risk.
- **Dual-write everywhere** — divergence and duplicated business logic.
- **Facade god-service** — translation and orchestration logic accumulates in the routing layer.
- **Permanent coexistence** — two systems maintained forever because nobody owns removal.
- **Parity by proxy metric** — comparing only HTTP 200 rates while business outcomes differ.
- **Shared database between old and new** — integration through tables; schema changes break
  both.
- **Decommission without retention review** — legal exposure and unrecoverable data.
- **Feature parity not tracked** — gaps discovered by customers after cutover.

## Checklist

- [ ] ADR records the migration approach and rejected options.
- [ ] Seams are small, ordered by risk, and each step is reversible.
- [ ] Facade has telemetry (which path served what) and no business logic.
- [ ] Expand-contract used for every non-additive schema or API change.
- [ ] No dual writes; propagation is outbox or CDC.
- [ ] Backfill reconciled with counts, checksums, and business metrics.
- [ ] Cutover is progressive with soak times and rollback rehearsed.
- [ ] One authoritative writer named during coexistence.
- [ ] Decommission checklist completed, including legal retention and docs.
- [ ] Post-migration review recorded.

## Related

- Recording target state and approach decisions: [./01-adr.md](./01-adr.md)
- Where to cut seams in the existing structure: [./05-modularity-boundaries.md](./05-modularity-boundaries.md)
- Reliable data movement during migration: [./06-data-architecture.md](./06-data-architecture.md)
- Contract evolution for APIs and events: [./07-integration-patterns.md](./07-integration-patterns.md)
