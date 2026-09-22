# Data

Scope: SQL access with `database/sql` and pgx, generated queries with sqlc, migrations, transactions, caching with Valkey/Redis, pool sizing, and database test strategy.

## database/sql fundamentals

`sql.Open` validates arguments and returns immediately; it does not dial. Verify connectivity with `PingContext` at startup and fail fast.

```go
db, err := sql.Open("pgx", dsn) // pgx stdlib adapter
if err != nil {
	return fmt.Errorf("open db: %w", err)
}
db.SetMaxOpenConns(20)
db.SetMaxIdleConns(20)              // match open to avoid churn
db.SetConnMaxLifetime(30 * time.Minute)
db.SetConnMaxIdleTime(5 * time.Minute)

ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
defer cancel()
if err := db.PingContext(ctx); err != nil {
	return fmt.Errorf("ping db: %w", err)
}
```

- Always pass `ctx`: `QueryContext`, `ExecContext`, `QueryRowContext`. A missing deadline turns a slow database into a hung service.
- `QueryRow.Scan` returns `sql.ErrNoRows` for zero rows — a normal condition, map it explicitly. `Query` requires `rows.Close()` even on error paths; check `rows.Err()` after the loop.
- `Scan` into `*sql.Null[T]` (generics since 1.22) or `*T` pointers for nullable columns; never into `sql.NullString` when the SQL type is not string.
- Prepared statements: pgx caches per-connection automatically; with `database/sql` use `Stmt` only when the same connection affinity matters. Re-preparing per request is usually unnecessary.
- Batch inserts: multi-row `INSERT ... VALUES` or `COPY` via pgx beats N round trips by orders of magnitude. Batch sizes of 500-5000 rows; bound the total statement size.
- Never build SQL with `fmt.Sprintf` on user input. Parameters only. Identifiers (table/column names) cannot be parameters — allowlist them.
- Connection pool knobs interact with the database's own `max_connections` and any PgBouncer in between; size pools from the sum of all service replicas, not per pod in isolation. See [./04-web-services.md](./04-web-services.md) for request budgets.

## Transactions

```go
func (r *Repo) Transfer(ctx context.Context, from, to string, amount int64) error {
	tx, err := r.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return fmt.Errorf("begin: %w", err)
	}
	defer func() { _ = tx.Rollback() }() // no-op after commit

	if _, err := tx.ExecContext(ctx, `UPDATE accounts SET balance = balance - $1 WHERE id = $2`, amount, from); err != nil {
		return fmt.Errorf("debit: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `UPDATE accounts SET balance = balance + $1 WHERE id = $2`, amount, to); err != nil {
		return fmt.Errorf("credit: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	return nil
}
```

- `defer tx.Rollback()` is the standard guard; `Rollback` after `Commit` returns `sql.ErrTxDone` and is safely ignorable. If you must surface rollback failures, `errors.Join` them in the deferred function.
- Canceling the context rolls back the transaction and returns the context error; wrap it so callers can `errors.Is(err, context.DeadlineExceeded)`.
- Keep transactions short: no HTTP calls, no user think-time, no `time.Sleep`, no logging I/O. Long transactions hold locks and consume a pooled connection.
- Serialization failures (`40001`) and deadlocks (`40P01`) are retryable **in the database**, not the Go runtime. Wrap the whole tx in a retry helper with jitter, bounded attempts, and idempotent statements.
- Nested transactions become savepoints; prefer explicit `SAVEPOINT` when partial rollback is genuinely needed.
- A `Tx` is bound to one connection: never capture it in goroutines.

## pgx v5

For PostgreSQL, pgx v5 is the default driver. `lib/pq` is in maintenance mode; its use is legacy. `database/sql` remains useful for portability and for libraries that require it — pgx provides `stdlib` registration for that case.

```go
cfg, err := pgxpool.ParseConfig(dsn)
if err != nil {
	return err
}
cfg.MaxConns = 20
cfg.MinConns = 2
cfg.MaxConnLifetime = 30 * time.Minute
cfg.HealthCheckPeriod = time.Minute

pool, err := pgxpool.NewWithConfig(ctx, cfg)
if err != nil {
	return err
}
defer pool.Close()

rows, err := pool.Query(ctx, `SELECT id, name FROM users WHERE tenant = $1`, tenant)
if err != nil {
	return err
}
defer rows.Close()
for rows.Next() {
	...
}
return rows.Err()
```

| Need | pgx API |
|---|---|
| Single query | `pool.QueryRow`/`Query` |
| Many statements per round trip | `pgx.Batch` |
| Bulk load | `CopyFrom` (COPY protocol) |
| Notifications | `Conn.WaitForNotification` (dedicated connection) |
| Custom types | `pgtype` mappings; `RegisterType` |
| LISTEN/NOTIFY consumers | one goroutine per dedicated `pgx.Conn` |

- `pgx.Rows` are single-use; `CollectRows`/`RowToStructByName` helpers reduce boilerplate but hide streaming — use them with bounded result sets.
- Default pool size is the greater of 4 and `GOMAXPROCS`; treat it as a starting point, not a tuning.
- `pgx.ErrNoRows` from `QueryRow.Scan`; `pgconn.PgError` carries SQLSTATE — branch on codes (`unique_violation` = `23505`) rather than message text.
- Context cancellation sends a cancel request to the server; verified with `pgx.Conn` internals. Avoid `context.Background()` in queries.

## sqlc and query generation

sqlc compiles SQL into typed Go. It fits read-heavy services where SQL is the source of truth and the team wants compile-time safety without an ORM.

```yaml
version: "2"
sql:
  - engine: "postgresql"
    queries: "internal/storage/queries"
    schema: "migrations"
    gen:
      go:
        package: "db"
        out: "internal/storage/db"
        sql_package: "pgx/v5"
```

- Pros: no runtime reflection, explicit SQL, generated structs for rows/params, caught schema drift at build time.
- Cons: dynamic filters become awkward; complex queries still need hand tuning; regeneration churn in diffs. The config schema (`version: "2"` at time of writing) changes between major sqlc releases — verify the current schema upstream before pinning.
- Alternatives: hand-written pgx for small surfaces; `ent` for graph-like domains with generated hooks; `gorm` when pragmatism dominates and query control is secondary. Justify the abstraction; ORMs hide N+1 and unbounded queries.
- Generated code is committed and never edited by hand ([./03-project-layout-tooling.md](./03-project-layout-tooling.md)).

## Migrations

- Tools: `goose` and `golang-migrate` are the common embeddable choices; Atlas adds declarative schema diffing and linting. Pick one, run it from CI, and never apply migrations by hand in production.
- Name migrations with timestamps and descriptions; one logical change per file; always write the down migration even if you never roll back.
- Make DDL transactional where the engine supports it (PostgreSQL does); avoid mixing DDL and long data backfills in one migration.
- Zero-downtime pattern: **expand/contract**. Add nullable column/index with `CONCURRENTLY` → deploy code writing both → backfill in batches → switch reads → drop old column in a later release.
- Backfills: batch by primary key with `LIMIT`, sleep/throttle, and make them idempotent and restartable.
- Locking: `CREATE INDEX CONCURRENTLY` avoids long locks; adding a `NOT NULL` column with a default historically rewrote tables — check current engine behavior (modern PostgreSQL handles constant defaults efficiently; verify the version).
- Apply migrations at deploy time from a single job, not from every application replica at startup, unless you use an advisory lock.
- Migration state must be observable: log version, duration, and failures; alert on pending migrations.

## Caching with Valkey/Redis

Valkey is the BSD-licensed Redis fork and the safe default for new infrastructure; both speak the Redis protocol and are compatible with Go clients. `go-redis` v9 is the mainstream client; `rueidis` offers higher throughput with pipelining and client-side caching. Verify current maintenance status upstream.

```go
func (s *Store) GetUser(ctx context.Context, id string) (*User, error) {
	key := "user:v3:" + id
	if raw, err := s.rdb.Get(ctx, key).Bytes(); err == nil {
		var u User
		if err := json.Unmarshal(raw, &u); err == nil {
			return &u, nil
		}
	} else if !errors.Is(err, redis.Nil) {
		return nil, fmt.Errorf("cache get: %w", err)
	}

	u, err := s.db.LoadUser(ctx, id)
	if err != nil {
		return nil, err
	}
	b, _ := json.Marshal(u)
	ttl := 10*time.Minute + time.Duration(rand.IntN(60))*time.Second // jitter
	if err := s.rdb.Set(ctx, key, b, ttl).Err(); err != nil {
		slog.WarnContext(ctx, "cache set failed", "err", err) // degrade, don't fail
	}
	return u, nil
}
```

- Cache-aside is the default; write-through/write-behind only with a strong reason.
- TTL jitter prevents synchronized expiry stampedes. For hot keys, add `singleflight` so one caller recomputes while others wait ([./02-concurrency.md](./02-concurrency.md)).
- Version keys (`user:v3:`) so schema changes are a cache flush, not a migration.
- Negative caching needs shorter TTLs and explicit invalidation on create.
- Never cache authorization decisions without an invalidation path; stale permissions are a security bug.
- In-process caches (`ristretto`, `otter`, `bigcache`) remove network hops but add coherence problems; use only for immutable or slowly changing data with clear bounds.
- Serialization: prefer a stable format (JSON or protobuf); version the payload; do not cache Go gob across binary versions.
- Treat the cache as optional: all cache errors degrade to the source of truth. If it is not optional, it is a database.

## Connection pools and resource math

Let `replicas × maxConnsPerReplica + adminReserve ≤ database max_connections` (or PgBouncer `max_client_conn`). Exceeding it produces connection storms and mysterious 500s.

- Symptoms of pool exhaustion: latency spikes that grow linearly, `context deadline exceeded` on `Begin`, DB-side "too many clients".
- Long transactions and `LISTEN` connections hold slots; size them separately.
- PgBouncer in transaction mode breaks session-level features (prepared statement names, advisory locks, `LISTEN`); configure clients accordingly (pgx has a `special` setting and uses SQL-level prepared statements by default).
- Monitor: open/in-use/idle connections, wait duration, acquisition errors.

## Testing database code

| Approach | Use when | Trade-off |
|---|---|---|
| Testcontainers (`testcontainers-go`) | real engine semantics, CI has Docker | startup cost; cache images |
| Template database / snapshot restore | many tests on one instance | isolation discipline required |
| Transaction-per-test rollback | tests touching one connection | breaks code that commits or uses multiple connections |
| `sqlmock` | unit-testing query construction only | does not validate SQL; brittleness; often net negative |
| Pure functions over rows | parsing/mapping logic | easiest and fastest — extract logic from SQL |

- Run migrations against the container at suite start; never maintain a parallel test schema.
- Use `t.Cleanup` for container termination and per-test truncation; isolate tests that can run in parallel with schemas or tenant IDs.
- Time-bound every test DB call; a hung test is worse than a failing one.
- Test the failure paths: constraint violations map to domain errors, serialization retries actually retry, context cancellation rolls back.
- See [./06-testing.md](./06-testing.md) for Testcontainers lifecycle patterns and CI caching.

## Anti-patterns

- `SELECT *` in application code; schema changes silently alter scan behavior.
- N+1 queries from looped ORM loads; batch with `IN` or joins.
- Unbounded `WHERE` scans; every query that grows with data needs an index and a `LIMIT`.
- Missing `rows.Err()` checks; leaked rows keep the connection checked out.
- Transactions wrapping HTTP calls, file I/O, or logging.
- Retrying non-idempotent writes blindly.
- Cache used as primary storage; no TTL; invalidation only in tests.
- Dynamic SQL built by string concatenation.
- Migrations applied by every pod on startup.

## Review checklist

- [ ] Every query uses a context with a deadline; no background contexts in request paths.
- [ ] Rows closed, `rows.Err()` checked, `ErrNoRows` mapped to a domain error.
- [ ] Transactions short, with `defer Rollback` and retry-on-serialization where needed.
- [ ] Pool sizes derived from database limits and replica count; monitored.
- [ ] Migrations reviewed for locks and rollback; expand/contract for breaking changes.
- [ ] Cache keys versioned, TTLs jittered, failures degrade, invalidation defined.
- [ ] DB tests use the real engine (Testcontainers) for semantics; mocks limited to query-shape tests.
- [ ] No SQL string interpolation of values; identifiers allowlisted.
