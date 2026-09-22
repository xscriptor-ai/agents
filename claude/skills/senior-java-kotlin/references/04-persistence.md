# Persistence (JPA, jOOQ, Migrations, Pooling)

Scope: data access on the JVM: JPA/Hibernate modeling, jOOQ, transaction semantics, fetch strategies, schema migration, connection pooling, and caching.

## Stack baseline

| Component | Range | Notes |
| --- | --- | --- |
| Jakarta Persistence | 3.1 / 3.2 | Hibernate 6.6+ and 7.x respectively; verify the matrix upstream |
| Hibernate | 6.6+ / 7.x | Hibernate 6 removed legacy `javax` and many old APIs |
| jOOQ | 3.x | Code generation from your schema; licensing differs by database and edition |
| Flyway | 10+ / 11+ | Database modules are separate artifacts; some database support is commercial — verify licensing |
| Liquibase | 4.x | XML/YAML/SQL changelogs, rollback support |
| HikariCP | current | Default pool in Spring Boot; keep the driver on the same support window |
| Spring Data JPA | 3.x / 4.x | Repository abstraction; do not let it hide fetch behavior |

## Entity design

```java
@Entity
@Table(name = "orders")
public class Order {
    @Id @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "order_seq")
    private Long id;

    @Version private long version;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "customer_id")
    private Customer customer;

    @ElementCollection
    @CollectionTable(name = "order_lines", joinColumns = @JoinColumn(name = "order_id"))
    private List<OrderLine> lines = new ArrayList<>();
}
```

Rules:

- Entities are mutable identity objects: no records, no `final` classes (proxying), no Lombok `@Data` (generated `equals/hashCode` breaks proxy semantics and lazy loading).
- Identity: use generated numeric IDs; implement `equals`/`hashCode` on a business key or database ID with a null-safe, stable contract. Never use all fields (mutability) and never use the default `Object` identity (proxy and set operations fail).
- Association defaults: `ManyToOne`/`OneToOne` `LAZY`; never rely on `EAGER`. `@Basic(fetch=LAZY)` on large columns does little without bytecode enhancement — prefer separate tables or projections for blobs.
- Bidirectional associations: keep one owning side, provide add/remove methods that maintain both sides, avoid cascades that delete more than intended.
- `@Version` optimistic locking on aggregates modified by concurrent users; handle `OptimisticLockException` with retry or user-visible conflict.
- Use `Instant`/`LocalDate`/`OffsetDateTime`; avoid `java.util.Date`, calendar, and timezone-naive types. Store timestamps in UTC.
- Enums: `@Enumerated(EnumType.STRING)`; ordinal mapping breaks on reordering.
- Generated schema is not the contract: use migrations in production (`ddl-auto=validate` at most). Hibernate schema generation is for tests only.
- Prefer `@Column` lengths/precision explicit; never let the database pick types silently for money (`NUMERIC`, not `FLOAT`).

Anti-patterns:

- Lazy loading in view/templating layers after the transaction closed.
- `@Data`/`@EqualsAndHashCode` on entities.
- Storing large collections of entities as `@ElementCollection` without bounding their size.
- God entities spanning many aggregates; split by transactional boundary.

## Fetch strategies and N+1

N+1 is the default failure mode: one query for parents, then one per child.

| Strategy | Use when | Notes |
| --- | --- | --- |
| `JOIN FETCH` in JPQL | Small, known fetch set; pagination not combined | Collection fetch join plus `setMaxResults` triggers in-memory pagination |
| `@EntityGraph` | Varying fetch plans per query | Declarative; can also trigger in-memory pagination with collections |
| Batch fetching (`@BatchSize`, `hibernate.default_batch_fetch_size`) | Many small lazy loads | Turns N+1 into N/batch queries; safe with pagination |
| `@Subselect`/`@Fetch(SUBSELECT)` | Fetching the same collection for many parents | One extra query per collection |
| DTO projection (`select new ...`) | Read-mostly screens, reports | Fastest; no persistence context bookkeeping |
| Two-query pattern (ids, then fetch by ids) | Paginated aggregates with collections | Predictable and safe with pagination |

Detection:

- Enable SQL logging in development and read the log; count statements per request.
- Use `hibernate.generate_statistics=true` and inspect query counts in tests; assert query counts on critical paths.
- Datasource proxies (p6spy, datasource-proxy) or Hibernate `StatementInspector` in test scope; fail tests when a request issues more than N statements.
- JFR/telemetry can show SQL hotspots in production (`./05-jvm-performance.md`).

Rules:

- Every repository method that returns an aggregate for display should declare its fetch needs; there is no correct global default.
- Avoid `EAGER` to "fix" N+1; it moves the problem and makes unrelated queries heavy.
- Pagination and collection fetch joins do not mix in JPA 3.x; use the two-query pattern or keyset pagination with DTOs.
- `Slice<T>` for "is there more" checks avoids a count query; `Page<T>` issues an extra `count(*)` — disable it when the UI does not need totals.
- Offset pagination degrades deep in large tables; use keyset/seek pagination (`WHERE (created_at, id) < (:last_created, :last_id) ORDER BY created_at DESC, id DESC`).

Anti-patterns:

- `findAll()` on a large table feeding a list endpoint.
- `@OneToMany(fetch = EAGER)` on multiple collections (cartesian explosion).
- Open Session in View (OSIV) left on in production to mask lazy loading: it holds connections through rendering and hides N+1.
- `toString()` on entities generated by Lombok triggering lazy loads during logging.

## Transactions

```java
@Service
public class TransferService {
    private final Accounts accounts;

    @Transactional
    public void transfer(long from, long to, BigDecimal amount) {
        accounts.debit(from, amount);
        accounts.credit(to, amount);
    }
}
```

Propagation reference:

| Propagation | Behavior | Use |
| --- | --- | --- |
| `REQUIRED` (default) | Join existing or start new | Normal service methods |
| `REQUIRES_NEW` | Suspend outer, new transaction | Auditing/outbox that must commit independently |
| `NESTED` | Savepoint inside outer | Partial rollback within one transaction (driver support required) |
| `MANDATORY` | Fail without existing | Internal methods that must run in a caller's unit of work |
| `NOT_SUPPORTED` | Suspend, run without transaction | Long reads/reports that should not hold connections |
| `NEVER` | Fail if a transaction exists | Strict stateless operations |

Rules:

- Transactions belong on service methods, not controllers or repositories; the service defines the unit of work.
- `@Transactional` on self-invocation does nothing (proxy bypass). Extract to another bean or use programmatic `TransactionTemplate`.
- Rollback defaults: unchecked exceptions roll back; checked exceptions do not. Set `rollbackFor` explicitly when needed.
- `readOnly = true` on query-only methods: skip dirty checking, hints to the database, and blocks accidental writes.
- Keep transactions short. Never call HTTP, messaging, or file systems inside one; use outbox or post-commit hooks.
- Isolation: default `READ_COMMITTED`; raise only with a demonstrated anomaly and a plan for retries/locking.
- Timeouts: set `@Transactional(timeout = ...)` and database statement timeouts; an unbounded transaction holds connections and locks.
- Kotlin classes are final; apply `kotlin("plugin.spring")` (all-open) so proxying works.
- Nested transaction managers (JPA + JDBC, multiple datasources) need `ChainedTransactionManager`-style patterns or XA only when truly required; prefer single-datasource designs.

Anti-patterns:

- `@Transactional` on private/self-called methods.
- Catching exceptions inside a transaction and continuing after a constraint violation (the context is poisoned; consider flushing and rolling back).
- Distributed transactions across services; use sagas/outbox (`./03-spring-boot.md`).
- Holding a transaction open while waiting on user input or a slow downstream call.

## Locking and concurrency

- Optimistic: `@Version` + retry on conflict. Default for user-facing edits.
- Pessimistic: `@Lock(PESSIMISTIC_WRITE)` with short transactions for contention-heavy counters/queues; beware deadlocks — acquire locks in a consistent order.
- `SELECT ... FOR UPDATE SKIP LOCKED` via native query or jOOQ for work queues; this outperforms JPA locking in most queue implementations.
- Database constraints are the last line of defense: unique keys, foreign keys, check constraints; don't rely solely on application checks.
- Idempotency: unique business keys on commands/outbox tables to deduplicate retries.

## jOOQ

Choose jOOQ when the SQL matters more than the object graph: reports, dynamic filters, bulk operations, complex joins.

```java
List<RevenueRow> rows = dsl
    .select(CUSTOMER.NAME, sum(ORDER_.AMOUNT).as("revenue"))
    .from(ORDER_)
    .join(CUSTOMER).on(CUSTOMER.ID.eq(ORDER_.CUSTOMER_ID))
    .where(ORDER_.CREATED_AT.greaterOrEqual(from))
    .groupBy(CUSTOMER.NAME)
    .orderBy(field("revenue").desc())
    .fetchInto(RevenueRow.class);
```

Rules:

- Generate code from migrations/schema in CI; commit generated code or regenerate deterministically; never let generated code drift from the database.
- Use jOOQ with the Spring `TransactionManager` (`DSLContext` backed by the same datasource) so JPA and jOOQ share transactions when mixed.
- Map to records/DTOs directly; jOOQ can fetch into records or manual mappers.
- Prefer jOOQ over JPQL for `INSERT ... ON CONFLICT`, CTEs, window functions, `MERGE`, and vendor-specific SQL.
- Keep SQL in the data layer; do not sprinkle DSL calls through services.
- Licensing: verify which databases/editions are covered by the open-source editions (`./10-migration-modernization.md`).

Anti-patterns:

- Using jOOQ to reimplement an ORM (loading entities and manually managing identity).
- Dynamic SQL built with string concatenation instead of the DSL.
- Skipping code generation and hand-writing table references, causing drift.

## Migrations (Flyway and Liquibase)

| Criterion | Flyway | Liquibase |
| --- | --- | --- |
| Authoring | Plain SQL (primary) | XML/YAML/JSON/SQL |
| Mental model | Immutable versioned scripts | Changesets with rollback and preconditions |
| Multi-database support | Varies by database/edition | Strong across databases |
| Rollback | Manual/undo scripts (paid in some editions) | Built-in rollback blocks |
| Best for | SQL-first teams, DBA review, one main database | Enterprise, many databases, policy-driven changes |

Rules:

- Migrations are immutable once applied anywhere. Fix mistakes with a new migration.
- One logical change per migration; small, reviewable, and independently deployable.
- Expand/contract for zero-downtime schema changes: add new column (nullable/default) → dual-write/backfill → switch reads → stop writes → drop old column in a later release.
- Never mix destructive DDL and application deploys in one step for rolling deployments.
- Test migrations against a copy of production-like data; verify duration and lock behavior on large tables.
- Baselines: for existing databases, baseline at a known schema version and keep the baseline in version control.
- `ddl-auto=validate` in production plus migration-driven schema is the only acceptable combination with Hibernate.
- CI: run migrations on an empty database and on a pre-migration snapshot; fail on drift (schema diff empty).

Anti-patterns:

- Editing an applied migration to fix a typo (checksum failure and environment drift).
- Long-running `ALTER TABLE` rewriting a large table during peak hours without a plan (`NOT VALID` constraints, concurrent index builds).
- Application code that assumes a migration from a future release already ran.

## Connection pooling (HikariCP)

Sizing:

- Formula from the HikariCP/PostgreSQL community: `connections = ((core_count * 2) + effective_spindle_count)`, then cap by the database's connection limit and reserved admin connections. More connections usually reduce throughput.
- Small pools with fast queries beat large pools with queueing; measure with database-side metrics, not application guesses.
- `maximumPoolSize` is per application instance: total connections = instances × pool size. Budget globally.
- `connectionTimeout` short (e.g., seconds) so requests fail fast instead of queueing forever; `validationTimeout`, `idleTimeout`, `maxLifetime` shorter than the database/proxy idle kill.
- Leak detection threshold for staging/dev only; leaks in production show up as pool starvation.
- Transaction boundaries determine connection hold time: long transactions exhaust the pool regardless of size.

Virtual threads and pools:

- Virtual threads do not remove the need to bound database connections. The database is the scarce resource.
- With virtual threads, backlog moves from the pool queue to the database; keep pool sizes conservative and set statement timeouts.

Anti-patterns:

- Setting `maximumPoolSize` to hundreds because "requests are slow".
- Holding connections open across user think time.
- Sharing one pool across services with different latency profiles without isolation (`readOnly` replica pools separate).

## Caching

- First-level cache (persistence context) is per transaction; do not rely on it across requests. `EntityManager.clear()` in batch loops to bound memory.
- Second-level cache: only for read-heavy, rarely changing data. Shared mutable entities across nodes need invalidation via the provider (e.g., clustered invalidation) or short TTLs. Never cache entities with sensitive per-user data globally.
- Query cache is invalidated by any change to the involved tables; it is rarely a win in write-heavy systems. Measure before enabling.
- Spring `@Cacheable`/`@CacheEvict`: remember self-invocation bypass and key design; prefer explicit cache services for complexity.
- Caffeine for in-process caches with size and TTL bounds; Redis/Valkey for shared caches with network latency and serialization costs.
- Cache keys must include tenant/user where data is scoped; otherwise cross-tenant leakage.
- Prefer HTTP caching semantics for public read APIs (ETag, Cache-Control) over application caches.

Anti-patterns:

- Caching without expiry or size bounds.
- Caching exceptions/failures (negative caching) by accident.
- Two cache layers with contradictory TTLs producing stale reads that are impossible to reason about.

## Bulk operations and batching

- Set `hibernate.jdbc.batch_size` (e.g., 20-100) and `order_inserts`/`order_updates`; verify with SQL logs that batching actually happens (identity generation disables insert batching in some configurations).
- `saveAll` does not guarantee batching by itself; flush/clear periodically in loops.
- `StatelessSession` or jOOQ/JDBC for large imports; ORM identity tracking is pure overhead there.
- `@Modifying(clearAutomatically = true, flushAutomatically = true)` on bulk updates/deletes to keep the persistence context consistent.
- Use `exists`/`count` queries instead of loading collections to check emptiness at scale.

## Review checklist

- [ ] Fetch plans explicit per query; N+1 verified with statement counting tests.
- [ ] `@Version` on mutable aggregates; unique constraints for idempotency.
- [ ] Transactions at service boundary, short, with timeouts and explicit rollback rules.
- [ ] Schema only via migrations; migrations immutable and tested against realistic data.
- [ ] Pool sized from database capacity with global budget, fail-fast timeouts.
- [ ] Caching configured with bounds, TTLs, tenant scoping, and invalidation story.
- [ ] Bulk paths use batching/stateless sessions; batch loops clear the context.
- [ ] jOOQ codegen deterministic and committed/regenerated in CI.
