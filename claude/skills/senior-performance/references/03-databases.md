# Databases

Scope: indexing strategy, query plan reading, N+1 detection, connection pool sizing, partitioning, read replicas, and the slow query workflow.

## Indexing Strategy

An index is a write-time tax paid for read-time speed. Add one only when a measured query needs it.

| Index type | Best for | Cost / caveat |
|---|---|---|
| B-tree | Equality, range, ordering, `LIKE 'prefix%'` | Default; can bloat and need maintenance |
| Composite B-tree | Multi-column predicates and sort order | Column order decides usability |
| Covering (`INCLUDE`) | Avoiding heap or table fetches | Wider index, more write cost |
| Partial | Hot subsets (`WHERE status = 'open'`) | Only usable when the predicate is implied |
| Expression / functional | Queries on `lower(email)` or computed values | Must match the expression exactly |
| Hash | Equality only (rarely better than B-tree) | No range or ordering; crash-safety history |
| GIN | JSONB containment, arrays, full-text search | Slow writes, fast containment |
| GiST / SP-GiST | Geometry, ranges, nearest-neighbor | Specialized operators and selectivity |
| BRIN | Very large append-only tables, naturally ordered | Small and cheap; coarser filtering |

- Column order in a composite index follows the query: equality predicates first, then range or sort columns. An index on `(a, b)` serves `a` and `a, b` but not `b` alone.
- Selectivity matters: an index on a boolean or gender column rarely helps alone, but works as the leading column of a filtered composite or partial index.
- Covering indexes trade storage for eliminating random heap access on hot queries; verify the plan actually stops fetching.
- Every index slows inserts, updates that touch indexed columns, and vacuum. Find unused indexes (`pg_stat_user_indexes`) and drop them; verify upstream before trusting any single view.
- Watch index bloat: bulk deletes and updates leave dead entries. Monitor size versus live rows and plan `REINDEX CONCURRENTLY` where supported.
- Statistics drive plans. After large data changes, run `ANALYZE`; for correlated columns, consider extended statistics. Raise statistics targets on columns used in selective predicates.
- New indexes on large production tables: build concurrently or online; know the lock level of the exact operation before running it.

## Reading Query Plans

- Use `EXPLAIN (ANALYZE, BUFFERS)` for real timings, row counts, and cache behavior. Plain `EXPLAIN` shows estimates only.
- Compare estimated to actual rows. A misestimate by 100x or more is the usual root cause of a bad join strategy or a spill to disk.
- Scan nodes: sequential scan (fine for large result fractions), index scan, index-only scan (covering), bitmap heap scan (moderate selectivity), parallel variants.
- Join nodes: nested loop (good for small outer sets, dangerous when the outer is large), hash join (good for large unsorted sets, memory-sensitive), merge join (pre-sorted inputs).
- Red flags: nested loop with a huge outer side, sorts with `external merge Disk` in the plan, `Rows Removed by Filter` far above returned rows, hash batches exceeding `work_mem`, repeated inner scans.
- Set `work_mem` deliberately per session or per workload, not globally huge: it is per operation and multiplied by concurrency.
- MySQL: `EXPLAIN ANALYZE` (8.0.18+) and `EXPLAIN FORMAT=JSON` expose actual timings and `rows_examined_per_scan`. Watch `Using filesort`, `Using temporary`, and high `rows_examined` relative to returned rows.
- Non-sargable predicates defeat indexes: functions on the indexed column, implicit casts, `LIKE '%term'`, arithmetic on the column, and `OR` across different columns. Rewrite, add an expression index, or split the query.
- Avoid deep `OFFSET` pagination; it reads and discards rows. Use keyset (seek) pagination on an indexed, ordered key.

### Rewrites That Pay

| Anti-pattern | Rewrite |
|---|---|
| Function on an indexed column | Precompute the value or add an expression index |
| `LIKE '%term%'` | Full-text or trigram index; prefix search where acceptable |
| `OR` across different columns | `UNION ALL` of indexed branches, or one composite index |
| Deep `OFFSET` | Keyset pagination on `(sort_key, id)` |
| Repeated aggregate in a loop | `GROUP BY` in one query or a materialized rollup |
| `SELECT *` on wide rows | Select needed columns; enable index-only access |
| Row-by-row upserts | Set-based upsert, bulk `INSERT ... ON CONFLICT`, or `COPY` |

- Verify every rewrite with the same plan inspection; some help only at certain data distributions.
- Keep query shapes stable across parameter values so plans do not flip between fast and slow.

## N+1 Detection and Fixes

N+1 is the most common application-level database performance bug: one query for the list, then one per element.

| Signal | Where to see it |
|---|---|
| Query count scales linearly with result count | ORM logs, `pg_stat_statements` call counts, APM span counts |
| Same statement shape repeated with different IDs | Slow query log, statement fingerprints |
| Request latency proportional to collection length | Traces with hundreds of sibling database spans |
| Database CPU high while unique queries are few | Fingerprint aggregation |

- Detect in tests: assert a maximum query count for key endpoints. A list endpoint that performs 500 queries with 500 rows should fail the suite.
- Fix with eager loading: `JOIN` or `IN (...)` prefetch, ORM `select_related`/`joinedload`/`include`, or a dataloader that batches lookups per request tick.
- Batch size has limits: chunk `IN` lists (hundreds to low thousands of ids) and keep parameter counts inside protocol and plan-cache limits.
- Enforce the policy: configure ORM lazy-loading to raise in test or production profiles where an accidental lazy load is a defect.
- GraphQL and RPC layers need the same discipline: dataloaders per request scope, deduplicated by key.
- Watch fan-out amplification: a serializer that lazily touches associations can reintroduce N+1 behind an otherwise fixed endpoint.

## Connection Pool Sizing

Every application instance opens a pool; the fleet total must fit the database.

```text
pool_size * app_instances + admin_reserve <= server_max_connections
```

- Server-side memory per connection is real (work memory, session state, TLS). Hundreds of idle connections cost memory and scheduler overhead for no throughput.
- A widely used starting heuristic (HikariCP and similar): `connections = (cpu_cores * 2) + effective_spindles`, then adjust from measured wait time. Small pools with fast queries often beat large pools; the database is a shared resource, not a queue to enlarge at will.
- Little's Law for pools: minimum busy connections equals `queries_per_second * average_query_time`, adjusted upward for variance and headroom. See `./01-methodology.md`.
- Set an acquire timeout. A request that waits forever for a connection turns pool exhaustion into a total outage; fail fast and shed instead.
- Monitor: pool in-use ratio, wait time (p95/p99), acquisition timeouts, and connection churn. Churn means connections are being opened and closed too often.
- Pool exhaustion has three common causes: a slow query holding connections, a leak (missing release on an error path), and a burst exceeding the pool's throughput ceiling.

| Symptom | Likely cause | Action |
|---|---|---|
| Wait time rises with traffic, DB CPU modest | Pool too small or queries too slow | Size from Little's Law, profile slow queries |
| Connections exhausted during errors | Leak on exception path | Add release guarantees, test failure paths |
| DB CPU saturated, pool queued | Too much concurrency at the database | Reduce pool, batch, cache, scale reads |
| High connect/disconnect rate | No pooling or aggressive idle eviction | Use a pool; tune idle timeout and lifetime |
| Prepared statements break through PgBouncer | Transaction pooling mode resets session state | Use statement-safe mode or named prepared statement support; verify upstream |

- External poolers (PgBouncer, pgpool, ProxySQL) add another queue. Sizing now spans app pool, pooler pool, and server limit; document all three.
- Serverless and bursty workloads need pooled access paths; opening a connection per invocation does not scale. Verify managed pooler limits upstream.

## Partitioning

- Partition when a table is too large to vacuum, back up, or query efficiently, or when retention is a regular operation.
- Range partitioning on time is the classic fit: periodic partitions plus `DROP PARTITION` for retention instead of mass `DELETE`.
- List partitioning isolates tenants or regions; hash partitioning spreads write-heavy tables evenly when no natural range exists.
- Partition pruning only works when queries filter on the partition key. A predicate wrapped in a function or cast may disable pruning.
- Global uniqueness and foreign keys behave differently across engines; verify constraints per engine version before relying on them.
- Do not over-partition: thousands of empty partitions slow planning and catalog work. Pre-create only the horizon you need and automate creation.
- Keep a default partition only if you have a monitor for rows landing there; it silently defeats pruning and can block attaching new partitions.
- Indexes are per-partition on many engines; plan index count and maintenance time with partition count in mind.
- Rebalance cautiously: detach, copy, and attach with minimal locks; test on a clone first.

## Read Replicas

- Replicas scale read throughput and offload reporting, but introduce lag. Define the lag budget per use case (for example, under one second for product pages, minutes for analytics).
- Read-your-writes: after a user writes, their subsequent reads must see it. Route that session to the primary for a bounded window, or track a write timestamp and require a replica at least that fresh.
- Monotonic reads: avoid bouncing a user between replicas with different lags so they see data move backwards.
- Replica lag grows under write bursts, long-running queries on the replica, and network issues. Monitor and alarm on lag; stop routing reads when it exceeds budget.
- Async replication loses recent writes on failover; synchronous replication trades write latency for durability. Choose per data class.
- Route explicitly: separate connection pools and clear naming (`primary`, `replica`) so a read accidentally hitting the primary is visible in code review.
- Long analytical queries on replicas can conflict with vacuum or cause lag; isolate heavy analytics from user-facing replicas where possible.

## Slow Query Workflow

1. Capture: enable the slow query log with a threshold, aggregate with `pg_stat_statements` or the MySQL performance schema, and correlate with APM traces.
2. Rank by total time (`calls * mean_time`), not mean alone. A 5 ms query called a million times beats a rare 2 s query.
3. Reproduce on a realistic clone: production-sized tables, similar statistics, same indexes. Seed data lies.
4. Inspect the plan with `EXPLAIN (ANALYZE, BUFFERS)`; find the first node where actual rows diverge from estimates or where time concentrates.
5. Fix in order of leverage: add or fix an index, rewrite the predicate or join, reduce returned columns and rows, batch calls, then consider caching or materialization. See `./02-caching.md`.
6. Apply schema changes online: concurrent index builds, no long exclusive locks, batched backfills. Know lock levels before executing.
7. Re-measure the same query on the same data and record the before/after. Watch for plan changes under different parameter values.
8. Guard: query-count assertions, latency dashboards by fingerprint, and review of new query shapes.

- Parameter sniffing and generic plan selection can make the same query fast for one value and slow for another. Test with both common and skewed values.
- Beware accidental full-table reads from unbounded endpoints: pagination and time filters are correctness and performance controls.

## Anti-Patterns

- Adding indexes by reflex without checking selectivity, write cost, or whether the query is even hot.
- Reading plans without `ANALYZE` and trusting estimates.
- Ignoring N+1 because "the ORM handles it".
- One global `work_mem` or buffer pool sized without concurrency in mind.
- Pool sizes set by copy-paste, not by Little's Law and measured wait time.
- Deep `OFFSET` pagination on large tables.
- Mass `DELETE` for retention where partition drop exists.
- Sending read-your-write traffic to a lagging replica.
- Reclaiming from a long analytics query on a user-facing replica.
- Treating the database as infinitely scalable because replicas exist.

## Checklist

- [ ] Every hot query has an index whose column order matches its predicates and sort.
- [ ] Plans checked with actual rows and buffers; misestimates investigated.
- [ ] Query-count assertions exist for list and detail endpoints to prevent N+1.
- [ ] Pool sized from Little's Law, with acquire timeout and wait-time alerts.
- [ ] Fleet connection math documented: app pools + poolers + reserves <= server limit.
- [ ] Partition key is present in queries; retention plans use partition drop.
- [ ] Replica lag budget defined; read-your-writes routing implemented and tested.
- [ ] Slow query review ranks by total time and validates on production-like data.
- [ ] Schema changes are online-safe and reversible.
- [ ] Before/after query performance recorded with the change.
