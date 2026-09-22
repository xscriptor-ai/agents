# Database Migrations

Scope: zero-downtime schema evolution with expand-contract, backward-compatible changes, online DDL, batched backfills, verification, and rollback strategy.

## The Compatibility Constraint

During any deploy, old and new application versions run simultaneously (rolling, canary, blue-green), and a rollback may return to the previous version. Therefore:

- Every schema state must be readable and writable by both the current and the previous application version.
- Migrations run before application rollout, and they must complete without assuming exclusive access to tables.
- Rollback of the application must not require a schema rollback. If it does, you have a maintenance window, not a zero-downtime deploy.

This is what expand-contract (also called parallel change) exists to guarantee.

## Expand-Contract

Four phases, typically spread across two or three releases:

| Phase | Action | Application state | Reversible |
|---|---|---|---|
| Expand | Add new structure alongside the old; keep both consistent | Old version ignores it | Yes (drop new structure if unused) |
| Dual-write / migrate | New version writes both; readers move to the new structure | Both versions compatible | Yes, with care |
| Switch | All readers and writers use the new structure | Old code still compatible via old path | Yes |
| Contract | Remove the old structure | Only new version remains | Hard; do not need to |

Worked example: rename `users.name` to `users.full_name`.

1. Expand: add `full_name` (nullable). Keep `name` untouched.
2. Dual-write: release app writing both columns and reading `name`. Backfill `full_name` from `name` in batches.
3. Switch: release app writing `full_name` and reading `full_name`; keep a write-through to `name` for rollback safety.
4. Contract: after the rollback window, drop `name` and stop writing it.

- Each phase is independently deployable and independently safe to abandon.
- Never combine expand and contract in one release. The gap is the safety margin.
- Record the target state and the cleanup ticket at expand time; contract work that is never scheduled becomes permanent debt.

## Backward-Compatible Change Catalog

| Change | Safe without expand-contract | Pattern when not safe |
|---|---|---|
| Add nullable column | Yes | Keep default handling in the application |
| Add table | Yes | None |
| Add non-null column with volatile default | No | Add nullable, backfill, then add constraint; avoid table rewrites on large tables |
| Add NOT NULL constraint | No | Validate existing rows first, then constrain in a later release |
| Drop column or table | No | Contract only after all readers and writers migrated; verify with query logs |
| Rename column | No | Expand-contract (add, dual-write, switch, drop) |
| Change column type | No | New column, backfill with conversion, switch, drop |
| Widen a varchar | Usually platform-dependent | Verify engine behavior; some widenings rewrite the table |
| Add index | Depends | Use concurrent/online index build on hot tables; verify lock behavior upstream |
| Drop index | Usually | Check query plans before dropping |
| Add foreign key | No | Add `NOT VALID`, validate separately where the engine supports it |
| Change enum values | Usually safe for additions | Removals and renames require expand-contract |
| Reorder columns | No | Cosmetic; do it during a contract step if at all |

Rules:

- Prefer additive changes; they are almost always backward compatible.
- A `NOT NULL` with no default is the classic breaking change: old code inserts NULL and fails.
- Renames are dangerous because they break old code silently at runtime, not at deploy time.
- Test every migration against the previous application version, not just the new one. A migration test suite that applies the schema and runs the old code paths catches most breakage.

## Migration Tooling

| Tool class | Examples | Notes |
|---|---|---|
| Versioned SQL migration runner | Flyway, Liquibase, golang-migrate, sqitch | Deterministic, language-agnostic; own the SQL |
| Framework migrations | Rails, Django, Alembic, Prisma, Entity Framework | Convenient; review generated SQL for lock behavior |
| Online schema change | gh-ost, pt-online-schema-change, provider-native online DDL | For large MySQL-family tables; copy is external to the transaction |
| Declarative schema diffing | Atlas-style, provider tools | Diff-based; audit generated plans carefully |
| Kubernetes Jobs / init hooks | Framework-specific | Ensure single execution and observability; avoid racing replicas |

Rules:

- One runner per service, one source of truth for migrations, checksummed and immutable once applied.
- Migrations are ordered, idempotent where possible, and recorded in a migration history table.
- Never edit an applied migration; add a new one.
- Run migrations as a dedicated job with its own identity, not from every application replica.
- Keep migration runtime visible: a migration that runs for an hour inside a deploy pipeline needs its own monitoring.
- Test migrations against a production-shaped dataset in staging; a migration that takes one second on an empty table can lock for minutes on a large one.

## Online DDL and Locks

- DDL often takes an exclusive lock. Even "instant" operations matter when a long-running transaction holds a conflicting lock.
- Set a short `lock_timeout` (or engine equivalent) on DDL so the migration fails fast rather than blocking all queries behind it. Retry with backoff.
- Set `statement_timeout` for the migration session to bound runaway DDL.
- For large tables on engines without online DDL, use a shadow-copy tool; it copies and swaps, with throttling and pause controls.
- Index builds: use concurrent/online variants on production tables; monitor replication lag for replicas.
- Avoid running DDL during peak traffic; schedule migrations to start at low load and allow them to continue.
- Watch for lock queues: a blocked DDL can block every subsequent query on the table. Abort rather than wait.

## Backfills

Backfills are data migrations and follow different rules from schema changes.

- Separate the backfill from the schema change: schema in one deploy, data in a background job.
- Batch by primary key or a stable order; never `UPDATE ... WHERE ...` over an unbounded table in one statement.
- Throttle: sleep between batches and monitor replica lag and primary load. Rate-limit by rows per second, not by arbitrary sleeps, and make it configurable.
- Idempotent and resumable: track progress, and restarting must not corrupt or double-apply. Use `WHERE new_col IS NULL` style predicates and a cursor.
- Backfill during dual-write so new writes are never lost; the backfill only handles historical rows.
- Validate with counts and checksums (or sampled comparisons) before switching readers.
- Long backfills can run across releases; deploy new code that tolerates partially filled columns (null handling) until the backfill completes.

## Verification

| Check | Method |
|---|---|
| Schema state | Migration history table plus a schema diff against the expected definition |
| Data completeness | Row counts and null counts for backfilled columns |
| Data correctness | Checksums or sampled row-by-row comparison between old and new structures |
| Application compatibility | Run the previous version's test suite against the new schema |
| Performance | Query plans on hot queries using the new columns or indexes |
| Replication health | Lag and error monitoring during DDL and backfill |
| Rollback readiness | Confirm the previous version runs against the current schema |

- Verification is automated and blocks the promotion step. Manual spot checks are for exploration, not gating.
- Keep a read-only replica or snapshot of the pre-migration state for the rollback window when the platform supports it cheaply.

## Rollback Strategy

- Rollback of code is preferred over rollback of schema. Design migrations so the previous code keeps working (that is the whole point of expand-contract).
- Prefer forward fixes over down migrations. Down migrations are often untested, destructive, and slower than the incident they are meant to resolve.
- If a migration must be reversible, write and test the down path in the same PR, and run it in staging.
- Irreversible operations (dropping a column, changing data in place) are contract-phase operations: run them after the rollback window has passed.
- Keep drops reversible by delaying them: rename to a quarantine name, keep for a defined period, then drop. Some teams keep a table backup for the retention window.
- Backfill errors: stop the job, fix, and resume from the cursor; never restart from zero on a live system without cause.
- Document, per migration, whether it is reversible, how long the rollback window is, and what the recovery action is.

## Anti-Patterns

- Adding a NOT NULL column without default in one step on a large table.
- Dropping or renaming a column in the same release that stops using it.
- `UPDATE` without batching on a production table.
- Running DDL and backfill in the same transaction or the same deploy step.
- Down migrations that delete data to "restore" the previous shape.
- Long-running DDL with no lock timeout, blocking the entire service.
- Assuming the ORM generates safe DDL; ORMs frequently do not.
- Testing migrations only on an empty schema.
- One team member's laptop as the only place a manual data fix is recorded.
- Contract-phase cleanup with no owner, left forever.

## Checklist

- [ ] Every change classified against the compatibility catalog.
- [ ] Expand and contract in separate releases with an owner for contract work.
- [ ] Migration tested against previous and new application versions.
- [ ] Lock and statement timeouts set; online DDL used for hot tables.
- [ ] Backfill separate, batched, throttled, idempotent, and resumable.
- [ ] Verification automated and gating: counts, checksums, compatibility, plans.
- [ ] Rollback window defined; previous code proven against new schema.
- [ ] Down path documented or explicitly waived as forward-fix-only.
- [ ] Migration runtime and replica lag monitored during execution.
- [ ] Cleanup ticket created at expand time and scheduled.
