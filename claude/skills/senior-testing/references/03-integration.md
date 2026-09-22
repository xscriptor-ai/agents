# Integration Testing

Testing real component boundaries: databases, HTTP clients, queues, caches, and filesystems with production-like dependencies.

## What Integration Tests Are For

An integration test exercises your code together with a real external dependency or a real
infrastructure component. It catches the defect classes unit tests cannot:

- SQL correctness: joins, constraints, nullability, transaction behavior, migration drift.
- Serialization and protocol errors: JSON field names, headers, content types, encoding.
- Wiring bugs: dependency injection, configuration loading, middleware order.
- Concurrency at boundaries: connection pool exhaustion, lock contention, retry semantics.
- Third-party API assumptions: pagination, rate limits, error envelopes.

The unit/integration line is not "mock vs real" but "is the boundary under test". A test
that spins a real Postgres but only exercises pure domain logic is an expensive unit test.

## Component Boundaries

| Boundary | Real dependency | Substitute | Caught by real |
|---|---|---|---|
| Relational DB | Testcontainers (Postgres/MySQL) | H2/SQLite | Dialect, constraints, locking |
| Document DB | Testcontainers (Mongo) | moto-style fake | Index and query semantics |
| HTTP API (yours) | In-process test client | none | Middleware, auth, serialization |
| HTTP API (third-party) | Contract-tested stub / WireMock | respx / msw | Headers, retries, timeouts |
| Message broker | Testcontainers (Kafka/Rabbit/NATS) | in-memory bus | Ordering, ack, redelivery |
| Object storage | Testcontainers (MinIO) | fake client | Multipart, presign, permissions |
| Cache | Testcontainer (Valkey/Redis) | in-memory dict | TTL, eviction, atomicity |
| Clock/locale | injected clock | n/a | Timezone, DST, formatting |

Two speeds of integration test:

- **Narrow integration** — one component plus one real dependency (repository + real DB).
  Keep these in the PR gate; aim < 5 s each.
- **Wide integration** — several components wired together (API + DB + queue) without a
  browser. Useful for smoke coverage; keep them in a separate job or nightly.

## Database Tests

### Testcontainers pattern

```python
import pytest
from sqlalchemy import create_engine
from testcontainers.postgres import PostgresContainer

@pytest.fixture(scope="session")
def engine():
    with PostgresContainer("postgres:17-alpine") as pg:
        eng = create_engine(pg.get_connection_url(), future=True)
        run_migrations(eng)
        yield eng
        eng.dispose()

@pytest.fixture
def session(engine):
    with engine.begin() as conn:
        yield conn
        conn.rollback()
```

- Pin image tags. `latest` breaks reproducibility without warning; bump tags deliberately.
- Run migrations once per session, not per test. Migration speed dominates otherwise.
- Use the same database engine and major version as production. SQLite in place of
  Postgres systematically hides type, constraint, and concurrency bugs.
- Keep an embedded option (e.g. SQLite) only for tests that genuinely do not touch SQL
  semantics; do not maintain two schemas.

### Transaction strategies

| Strategy | How | Pros | Cons |
|---|---|---|---|
| Rollback per test | Wrap each test in a transaction and roll back | Fastest, perfect isolation | Cannot test code that commits internally |
| Truncate per test | `TRUNCATE ... RESTART IDENTITY CASCADE` | Tests commit; simple | Slower; sequence restarts matter |
| Schema per worker | Create a fresh schema/DB per worker | Parallel-safe | Setup overhead; migration run per worker |
| Snapshot restore | Load a prepared DB dump | Fast for large fixtures | Snapshot drift when schema changes |
| Reset by delete | Delete rows by tenant key | Good for shared DB | Ordering and FK complexity |

Decision rule: default to rollback. Switch to truncate or schema-per-worker when the code
under test manages its own transactions; use snapshots when seeding dominates runtime.

```python
@pytest.fixture(autouse=True)
def _clean(db):
    yield
    with db.cursor() as cur:
        cur.execute("TRUNCATE orders, order_items RESTART IDENTITY CASCADE")
```

- Beware of autocommit/pooling interplay: a connection returned to the pool with an open
  transaction poisons the next test. Ensure teardown closes or rolls back explicitly.
- Never truncate shared reference data; seed it in migrations or a session fixture.

### What to assert

- Round-trip persistence: write then read through different code paths.
- Constraints: unique, foreign key, check, NOT NULL — assert the error, not just failure.
- Transactions: rollback on exception, isolation level behavior where it matters.
- Migrations: forward migration on a populated DB and, where supported, rollback.
- Query correctness: ordering, pagination cursors, aggregates under multi-row data.

## HTTP Stubs and Fakes

| Tool class | Examples | When |
|---|---|---|
| In-process interceptor | respx (httpx), responses (requests), nock (Node) | Client library tests, fast, no ports |
| Standalone stub server | WireMock, MockServer, Prism | Language-agnostic, cross-process |
| MSW (browser/node) | msw | Frontend tests and Storybook |
| Contract stub server | Pact stub / broker | Provider behavior pinned by consumers ([06-contract](./06-contract.md)) |
| Record and replay | VCR-style cassettes | Legacy APIs; scrub secrets and expire recordings |

Rules:

- Stub at the HTTP boundary, never at the SDK method level. Stubbing `stripe.Charges.create`
  teaches you nothing about auth headers or payload shape.
- Assert the outgoing request: URL, method, auth header presence, idempotency key. Most
  integration defects are in what you send, not what you receive.
- Model error responses explicitly: 4xx with body, 5xx, timeouts, malformed JSON, partial
  reads. Happy-path-only stubs hide the retry and circuit-breaker bugs.
- Record credentials in fixtures only as placeholders. Never commit real tokens.
- Set timeouts in tests lower than production defaults so a hung stub fails fast.

## Queues and Event Streams

- Publish, then consume with a bounded poll (deadline + backoff), never a fixed sleep.
- Assert at-least-once semantics: consumers must be idempotent; test a duplicate delivery.
- Test poison messages: malformed payload goes to DLQ and does not block the partition.
- For Kafka, prefer a dedicated topic per test run with unique names; cleanup via topic
  deletion or short retention.
- Pin consumer group IDs per test to avoid cross-run interference.

## Cleanup and Isolation

- Total isolation is the goal: a test that passes only when run after another test is a
  defect. Prefer per-test unique keys (`tenant_id = uuid4()`) over global cleanup scripts
  ([07-test-data](./07-test-data.md)).
- Cleanup must be exception-safe. Use fixtures with teardown guarantees
  (`yield` fixtures, `t.Cleanup`, `afterEach` registration).
- Leftovers are a signal: monitor container logs and database size in CI to catch leaks.
- External state that cannot be reset (third-party sandboxes) should be handled through
  idempotent test data and unique identifiers rather than assumptions of a clean slate.
- Run integration tests in parallel with per-worker resources: database name from worker
  ID, unique topic names, unique bucket prefixes.

## Speed

| Technique | Gain | Caveat |
|---|---|---|
| Session-scoped container and engine | Seconds per suite | State leaks; clean between tests |
| Transaction rollback | Milliseconds per test | Cannot test commits |
| Parallel workers with isolated DBs | Near-linear to 4-8x | More memory, container startup burst |
| Truncate over drop/create | Big for small schemas | Sequence resets |
| Prepared snapshot / template DB | Big when seed data is heavy | Must be rebuilt on migration change |
| Reuse containers locally only | Seconds per run | Hidden state; never in CI |
| Move slow cases to nightly | PR stays fast | Coverage shifts; keep smoke subset |

Targets: narrow integration case <= 2 s, full PR integration job <= 8 minutes. If a single
test takes longer than 10 seconds, question the scope, not the runner.

## Anti-Patterns

- Testing against a shared staging database; cross-team interference and data drift.
- Mocking the ORM/driver instead of the database; you are testing the mock's SQL dialect.
- Hidden ordering dependencies between tests through leftover rows.
- One "integration" suite that covers everything and takes 45 minutes, run on every push.
- Retrying DB connection failures inside tests instead of failing fast.
- Asserting only HTTP 200; response bodies and side effects are where bugs live.
- Using SQLite for Postgres code paths and calling it integration coverage.
- Leaving containers running after crashes; no `--rm`/testcontainers reaper.

## Integration Test Checklist

- [ ] Real database engine matching production, pinned image tag.
- [ ] Migrations run once; schema version asserted in a test.
- [ ] Isolation strategy chosen deliberately (rollback/truncate/schema-per-worker).
- [ ] HTTP dependencies stubbed at HTTP layer with error cases covered.
- [ ] Outgoing requests asserted (method, path, auth, idempotency keys).
- [ ] Cleanup exception-safe; no cross-test leakage; parallel-safe by unique keys.
- [ ] Narrow integration in PR gate <= 8 minutes; wide integration nightly.
- [ ] No staging environment dependency, no production credentials, no committed secrets.
