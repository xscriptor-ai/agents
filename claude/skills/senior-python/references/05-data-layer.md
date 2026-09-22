# Data Layer

SQLAlchemy 2.0 async sessions and transactions, Alembic, pydantic-settings, Django ORM, pandas 3/Polars, caching, connection pooling, and safe migrations.

## SQLAlchemy 2.0 Setup

```python
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

engine = create_async_engine(
    "postgresql+asyncpg://user:pw@host/db",
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,
    pool_recycle=1800,
)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False, autoflush=False)
```

- 2.0 style only: `select(Model).where(...)`, `session.scalars(...)`. The legacy `Query`
  API is removed from new code paths.
- `expire_on_commit=False` avoids implicit lazy refreshes after commit, which raise in
  async contexts.
- `autoflush=False` makes writes explicit; flush/commit at the service boundary.
- Use `Mapped[...]`/`mapped_column` declarative models; `DeclarativeBase` is the base class.
- Sync engine + `Session` remain valid for scripts, data jobs, and Celery workers; mixing
  sync and async sessions on the same connection is not possible (`MissingGreenlet`).

## Sessions and Unit of Work

```python
async def create_user(session: AsyncSession, name: str) -> User:
    user = User(name=name)
    session.add(user)
    await session.flush()   # assigns PK, sends INSERT
    return user             # caller commits
```

- One session per request/task ("unit of work"), never a module global. Sessions are cheap;
  connections are not.
- Commit once at the outer boundary (`async with session.begin():`) so multi-repository
  operations stay atomic.
- `flush()` to get generated keys; `commit()` to persist; `refresh()` only when you need
  DB-side defaults or triggers.
- After a failed flush the session is in a failed state; roll back and rebuild rather than
  continuing.
- FastAPI dependency pattern in [web frameworks](./04-web-frameworks.md); cancel/shutdown
  must close sessions.

## Transactions and Savepoints

```python
async with SessionLocal() as session:
    async with session.begin():
        session.add(User(name="a"))
        async with session.begin_nested():  # SAVEPOINT
            session.add(User(name="b"))
```

- `session.begin()` commits on clean exit, rolls back on exception.
- `begin_nested()` creates a savepoint; roll back the inner block without losing the outer
  transaction.
- Avoid manual `commit()` inside repository methods when the caller owns the transaction;
  it breaks atomicity and complicates tests.
- `SELECT ... FOR UPDATE` via `.with_for_update()` for row locks; keep lock ordering
  consistent to avoid deadlocks.
- Isolation: default is usually right; do not raise isolation level as a substitute for
  correct locking.

## Loading Strategies and the N+1 Problem

```python
from sqlalchemy import select
from sqlalchemy.orm import selectinload

stmt = select(Order).options(selectinload(Order.items)).where(Order.id == order_id)
order = (await session.execute(stmt)).scalar_one()
```

| Relationship | Strategy | Notes |
|---|---|---|
| Many-to-one / one-to-one | `joinedload` | Single query, FK join |
| One-to-many / many-to-many | `selectinload` | Second query with `IN`, avoids row multiplication |
| Deep chains | `selectinload(A.b).selectinload(B.c)` | Compose explicitly |
| Rarely needed | `raiseload("*")` / `lazy="raise"` | Fails fast on accidental lazy load |

- Async lazy loading raises `MissingGreenlet`; treat that error as a design bug, not an
  invocation problem.
- Set `lazy="raise"` (or `lazy="raise_on_sql"`) on relationships by default and opt into
  eager loading per query — this makes N+1 a startup/test failure.
- `selectinload` with pagination is safe; `joinedload` + `LIMIT` on a collection needs
  `selectinload` or a subquery to avoid truncated rows.
- Watch query counts in tests: assert the number of statements per endpoint.

## Engine, Pooling, and PgBouncer

- Pool math: `max_connections >= replicas * (pool_size + max_overflow)`. Postgres and
  pgbouncer have hard limits; exceeding them produces intermittent connection errors under
  load.
- `pool_pre_ping=True` detects dead connections after failovers; `pool_recycle` avoids
  stale connections behind idle timeouts.
- Behind pgbouncer in transaction mode, prepared statements break connections: disable the
  driver cache (`connect_args={"statement_cache_size": 0}` for asyncpg,
  `prepare_threshold=None` for psycopg3) or run pgbouncer in session mode.
- For serverless/bursty workers, a small pool or `NullPool` plus an external pooler is
  usually safer than a large local pool.
- Always set connect/read timeouts (`connect_args` or driver-level); an unresponsive DB
  must not hang the event loop forever.

## Alembic

- Initialize with the async template: `alembic init -t async migrations`.
- Set a deterministic naming convention on the metadata so autogenerate and downgrades can
  address constraints:

```python
from sqlalchemy import MetaData

NAMING = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}
metadata = MetaData(naming_convention=NAMING)
```

- Autogenerate does not detect everything: server default changes, type changes, enum
  alterations, check constraints, and some index renames require manual edits. Review every
  migration.
- Ship schema and data migrations separately; data backfills belong in explicit scripts with
  batching and progress logging.
- `alembic upgrade head` runs at deploy start (or a migration job), never
  `Base.metadata.create_all` in production.
- `op.batch_alter_table` for SQLite; use `autocommit_block()` for index operations that
  cannot run inside a transaction.
- In CI, `alembic upgrade head` then `alembic check`/`--autogenerate` to detect drift
  between models and migrations.

## pydantic-settings

```python
from functools import lru_cache

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_nested_delimiter="__", extra="ignore"
    )

    database_url: str
    redis_url: str = "redis://localhost:6379/0"
    api_key: SecretStr
    debug: bool = False

@lru_cache
def get_settings() -> Settings:
    return Settings()
```

- `SecretStr` prevents accidental logging of secrets; use `get_secret_value()` explicitly.
- Validate settings at startup; fail fast with a clear aggregate error.
- Prefer environment variables in production, `.env` only locally; never commit `.env`.
- Inject `Settings` rather than importing a module-level singleton, so tests can override.

## Django ORM

- `select_related("author")` for FK/one-to-one joins; `prefetch_related("tags")` for many
  relations. Combine with `Prefetch(..., to_attr=...)` for shaped caches.
- `only()`/`defer()` to avoid wide rows; `values()`/`values_list()` for read-only reports.
- Large scans: `.iterator(chunk_size=...)` (sync) / `.aiterator(...)` (async) instead of
  materializing all rows.
- Writes: `save(update_fields=[...])`, `bulk_create`/`bulk_update` (verify minor-version
  async variants upstream), `F()` expressions for atomic increments.
- `select_for_update()` inside `transaction.atomic()` for row locks; never hold locks across
  network calls.
- Assert query counts in tests with `django_assert_num_queries`/`assertNumQueries`; use
  `django-debug-toolbar` or `django-silk` in development to spot N+1 early.
- Async bridging details in [web frameworks](./04-web-frameworks.md).

## pandas 3 and Polars

| Aspect | pandas 3.x | Polars |
|---|---|---|
| Execution | Eager (per-operation) | Lazy by default with streaming |
| Memory | Row/column blocks, improved with Arrow strings | Columnar Arrow, typically lower |
| Strings | PyArrow-backed by default | Arrow-native |
| Multi-core | Single-threaded per op (GIL) | Native multithreading |
| Ecosystem | Broadest | Growing, strong Parquet/Arrow |
| Choose when | Existing pandas code, libraries | New pipelines, large files, performance |

```python
import polars as pl

result = (
    pl.scan_parquet("events/*.parquet")
    .filter(pl.col("kind") == "click")
    .group_by("user_id")
    .agg(pl.len().alias("clicks"))
    .collect(streaming=True)
)
```

- pandas 3 shifts defaults: Copy-on-Write semantics, Arrow-backed strings, changed
  `inplace` behavior. Upgrade by running the suite with the new defaults and fixing chained
  assignment warnings; see the official migration guide (verify upstream for the exact
  minor).
- Prefer vectorized expressions over `apply`/`iterrows`; keep Python loops out of hot
  transforms.
- Convert across libraries explicitly (`pl.from_pandas`, `.to_pandas()`); do not mix
  indexes and lazy semantics implicitly.
- Use `polars` to read and pre-aggregate before loading into pandas/ML libraries when data
  is large.

## Caching and Ephemeral State

```python
from redis.asyncio import Redis

redis = Redis.from_url("redis://localhost:6379/0", decode_responses=True, socket_timeout=0.5)

async def get_user_name(user_id: int) -> str | None:
    key = f"user:v1:{user_id}:name"
    if (cached := await redis.get(key)) is not None:
        return cached
    name = await load_name(user_id)
    await redis.set(key, name, ex=300)
    return name
```

- Cache-aside with explicit TTLs; no TTL means unbounded memory and stale Forever.
- Stampede protection: distributed lock, single-flight, or probabilistic early refresh.
  Add jitter to TTLs so keys do not expire in lockstep.
- Invalidate on write (delete key or version the prefix); version keys when the schema
  changes so old entries cannot poison new readers.
- Serialize with JSON/msgpack; never unpickle cache contents from shared infrastructure.
- Valkey is the Redis-compatible fork; `redis-py` works with either. Newer clients
  (`valkey-glide`) add native async performance — verify maturity upstream.
- A local in-process LRU (cachetools) is per worker and cannot be invalidated across
  replicas; use it only for immutable, cheap-to-recompute data.
- Cache failures must degrade to the source of truth, with a timeout and a circuit breaker
  if the cache is hot.

## Migration Safety

- Expand/contract pattern: add nullable column, dual-write, backfill in batches, switch
  reads, add constraints, drop old column in a later release.
- `NOT NULL` and type changes require a validation scan; add the constraint separately
  (`NOT VALID` then `VALIDATE CONSTRAINT` on Postgres) to limit lock duration.
- Create indexes concurrently on Postgres (`postgresql_concurrently=True` inside an
  autocommit block); never build a large index in a transaction that holds locks.
- Backfill in bounded batches with sleep/throttle; monitor replication lag and deadlocks.
- `ALTER TABLE ... RENAME` breaks running old code; assume mixed-version deploys for the
  duration of a rollout.
- Review generated SQL (`alembic upgrade --sql`, Django `sqlmigrate`), store migrations in
  version control, and never edit a migration that has already run in production.

## Anti-Patterns

- A global engine/session shared by all requests, or session-per-thread without cleanup.
- Lazy loading in async code (`MissingGreenlet`) hidden by ad-hoc `refresh()` calls.
- `create_all()` in production instead of migrations.
- Committing inside repositories mid-business-operation, breaking atomicity.
- Unbounded `iterator()` without chunk size; `SELECT *` on wide tables.
- Cache reads/writes without timeout, TTL, or invalidation plan.
- Row-wise pandas loops and `apply` where vectorization exists.
- Autogenerated migrations merged without review (they can silently drop data).

## Checklist

- [ ] Async engine configured with pool math consistent with DB/pooler limits.
- [ ] One session per request/task; `expire_on_commit=False`; explicit commit boundary.
- [ ] Eager loading explicit; `lazy="raise"` catches accidental N+1.
- [ ] Alembic naming convention set; migrations reviewed, reversible, and CI-checked.
- [ ] Settings validated at startup with `SecretStr` for secrets.
- [ ] Cache TTLs, jitter, invalidation, and timeouts defined.
- [ ] pandas/polars choice documented; upgrade path tested for pandas 3 defaults.
- [ ] Migration plan follows expand/contract with backfill and lock analysis.
