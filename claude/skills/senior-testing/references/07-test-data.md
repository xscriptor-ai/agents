# Test Data Management

Factories, builders, fixtures, seeding, PII handling, per-run uniqueness, and database snapshots.

## Principles

1. **Tests own their data.** No test depends on rows it did not create. Shared mutable
   fixtures are the root of half of all cross-test flake.
2. **Generate, do not copy.** Production data in tests is a compliance incident waiting to
   happen. Generate synthetic data that is structurally faithful.
3. **Unique per run.** Every run gets a namespace (run ID) so parallel CI jobs, retries,
   and repeated local runs never collide.
4. **Minimal but sufficient.** Data should contain exactly the fields the test reads. Wide
   sparse objects hide which fields matter.
5. **Deterministic where asserted, random where identity is irrelevant.** Fix values that
   the test asserts on; randomize values that only need to be unique.

## Factories and Builders

### Factory pattern

Factories produce valid objects with sane defaults and per-field overrides. Prefer them
over shared fixture rows.

```python
from dataclasses import dataclass, replace

@dataclass(frozen=True)
class User:
    id: str
    email: str
    plan: str = "free"
    created_at: str = "2026-01-01T00:00:00Z"

def make_user(**overrides) -> User:
    base = User(id=f"usr_{next(counter)}", email=f"user{next(counter)}@example.test")
    return replace(base, **overrides)
```

Rules:

- Defaults must be *valid*; a factory that produces invalid objects by default forces every
  caller to fix it.
- Overrides are explicit in the test body, making the relevant variation visible.
- Factories are plain functions or typed builders; avoid magic global registries that make
  data sources invisible.
- Never use a factory to hide the setup that is the point of the test.

### Builder pattern

Use builders when construction is sequenced or when many optional fields must be varied:

```python
order = (
    OrderBuilder()
    .with_item("sku-1", qty=2, price="9.99")
    .with_coupon("SAVE10")
    .shipping_to("DE")
    .build()
)
```

Builders shine for HTTP request bodies, protobuf/JSON payloads, and complex aggregates.
Keep the fluent chain shallow (<= 5 steps) before splitting into named scenarios.

### Factory libraries by ecosystem

| Ecosystem | Library | Notes |
|---|---|---|
| Python | factory_boy, polyfactory, faker + plain functions | factory_boy with SQLAlchemy/Django; polyfactory for pydantic models |
| TypeScript | fishery, @faker-js/faker, zod fixtures | fishery for typed factories |
| Ruby | FactoryBot | Mature; beware association graph explosion |
| Java | Instancio, Easy Random | Instancio supports object graph generation with overrides |
| .NET | AutoFixture, Bogus | AutoFixture for anonymous values; Bogus for realistic fakes |
| Go | gofakeit, plain builders | Idiomatic Go favors explicit builders |
| Rust | fake, proptest strategies | fake for rand-derived values |

Verify current versions upstream; the library ecosystems move faster than this table.

## Fixtures: Scope and Discipline

| Fixture kind | Example | Lifetime | Rule |
|---|---|---|---|
| Ephemeral value | record, DTO | Per test | Default; no cleanup needed |
| Local resource | temp dir, container | Per test/module | Teardown guaranteed, exception-safe |
| Session resource | DB engine, browser | Per suite | Immutable or explicitly reset |
| Reference data | countries, currencies, permissions | Per environment | Seed via migrations; never truncate |
| Golden data | expected report output | Per repository | Reviewed changes only |

- Fixtures provide **lifecycle**, factories provide **data**. Do not encode business data
  in fixtures; that couples unrelated tests.
- Hidden `autouse` fixtures that create data are an anti-pattern: tests must declare what
  they need.
- Session-scoped mutable state must have a documented reset path or the tests using it must
  be read-only.

## Seeding Reference Data

- Seed reference/lookup tables (currencies, countries, plans, permission catalogs) through
  migrations or an idempotent seed script shipped with the application.
- Tests must not depend on seed ordering or auto-increment IDs for business meaning; look
  up by natural key.
- Keep seed data versioned with the schema; drift between seeds and migrations breaks
  integration suites in confusing ways.
- For multi-tenant products, seed shared catalogs once and tenant-specific data per test.

## PII and Anonymization

### Never in tests

- Real names, emails, phone numbers, addresses, government IDs, payment instruments, or
  health data.
- Production tokens, cookies, or API keys; even expired ones leak infrastructure details.
- Screenshots or traces containing real customer data.

### Anonymization pipeline (when production-derived data is unavoidable)

1. Inventory columns and events that can contain PII; tag them in the schema or catalog.
2. Apply deterministic pseudonymization (HMAC with a rotated key) so joins still work.
3. Generalize or bucket quasi-identifiers (birth date -> age band, postal code -> region).
4. Validate with automated PII scanning (regex plus a detector service) before load.
5. Restrict access to the anonymized dataset; log who reads it.
6. Re-anonymize from scratch rather than mutating a prior copy, so removals and consent
   status flow through.

Rules:

- Prefer synthetic generation over anonymization; it removes the leak surface entirely.
- Synthetic data must preserve distributions and referential integrity, or tests pass for
  unrealistic reasons.
- Use reserved domains for generated emails (`@example.com`, `@example.test`) and
  documentation phone ranges so accidental sends fail safely.
- Never send test emails/SMS/payments through production providers; use sandboxes or local
  sinks.

## Unique Data per Run

Patterns for collision-free parallel execution:

| Target | Strategy |
|---|---|
| Database rows | Unique keys prefixed with run ID: `tenant = f"t-{run_id}-{n}"` |
| Emails | `user+{run_id}-{n}@example.test` |
| Object storage | Bucket/prefix per run with lifecycle expiry |
| Message topics | Topic per run, auto-deleted on teardown |
| External sandboxes | Idempotency keys containing run ID |
| Feature flags | Unique flag key per run; delete on teardown |

- Generate `run_id` once (CI job ID or UUID) and thread it through fixtures.
- Deterministic within a run, unique across runs: derive values from
  `(run_id, logical_name)` so retries of the same test reuse the same data and do not
  accumulate garbage.
- Cleanup strategy: delete by run prefix at the end of the job, plus a TTL sweep in the
  environment for crashed jobs.
- Assert-uniqueness: a test that inserts the same natural key twice should be an explicit
  intended scenario, not an accident.

## Database Snapshots and Templates

When seeding is expensive (large catalogs, complex graphs), use a prepared template:

| Technique | How | When |
|---|---|---|
| Template database | Create + migrate + seed once; `CREATE DATABASE x TEMPLATE y` per worker | Postgres, per-worker isolation |
| Dump/restore | `pg_dump`/`pg_restore` or schema snapshot | Cross-engine, versioned fixtures |
| Migration + seed script | Run migrations, then idempotent seeds | Always; the source of truth |
| Masked prod clone | One-time masked extract | Manual exploratory testing only, not CI |

Rules:

- Templates must be rebuilt whenever migrations change; stale templates cause test suites
  to test the wrong schema. Hash the migration directory and rebuild on mismatch.
- Never check binary dumps into the repository without a documented regeneration process.
- Prefer schema-level creation (migrations) plus programmatic seeds over opaque dumps;
  they diff, review, and version.
- Snapshot restore needs to reset sequences and ownership to avoid privilege drift between
  environments.

## Anti-Patterns

- Shared "seed once" global data mutated by tests; hidden ordering dependencies.
- Real production extracts in CI (even "just for debugging").
- Random data with seeds that change every run, breaking reproducibility and assertions.
- Factories with dozens of fixed magic values; tests that vary one field but assert none.
- Massive YAML fixtures containing every possible field; changes ripple everywhere.
- Cleanup that runs only on success; crashed runs leave garbage that poisons later runs.
- Using auto-increment IDs in assertions; they vary with execution order.
- Emails sent to real addresses from test suites.

## Test Data Checklist

- [ ] Factories/builders with valid defaults; tests override only what they assert.
- [ ] No production PII, tokens, or screenshots anywhere in the repo or CI artifacts.
- [ ] Run-scoped uniqueness for rows, topics, buckets, tenants, and sandboxes.
- [ ] Reference data seeded via migrations or idempotent script, keyed by natural keys.
- [ ] Cleanup by run prefix plus TTL sweep; exception-safe teardown.
- [ ] Snapshot/template rebuild is automated and triggered by migration hash changes.
- [ ] External services use sandbox credentials or local sinks only
      ([03-integration](./03-integration.md)).
- [ ] Data volume is bounded per test; suite runtime stable as factories grow.
