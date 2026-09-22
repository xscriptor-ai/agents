# Unit Testing

Structure, naming, determinism, isolation, test doubles, parameterization, edge cases, and assertion quality for fast, trustworthy unit tests.

## Definition

A unit test exercises one unit of behavior in isolation: a function, a class method, a
reducer, a small module. "Isolated" means no network, no filesystem surprises, no shared
mutable state, and no dependence on test order or wall clock. A unit test should run in
milliseconds and fail with a message that identifies the defect without debugging.

## Arrange-Act-Assert

```python
def test_discount_applies_loyalty_rate_before_tax():
    cart = Cart(items=[Item(price=100_00)], customer=Customer(loyalty_tier="gold"))

    total = price_cart(cart, tax_rate=Decimal("0.20"))

    assert total == Decimal("108.00")
```

- One logical behavior per test. Multiple asserts are fine when they describe the same
  outcome (e.g. fields of one returned object).
- Blank lines separate the three phases; if the act phase is more than a line or two, the
  unit is probably doing too much.
- Prefer pure functions with injected dependencies; they make AAA trivial.

### Given-When-Then

The same structure in BDD vocabulary. Use whichever the team already speaks; mixing both
in one repository is worse than either.

## Naming

Names are documentation; a failing suite should read like a defect list.

| Style | Example | Good for |
|---|---|---|
| Behavior sentence | `rejects_expired_coupon_at_checkout` | Python, Ruby, Go |
| Given/When/Then | `given_expired_coupon_when_checkout_then_rejected` | Java, Kotlin, explicit BDD |
| should + verb | `should_reject_expired_coupon` | JS/TS, .NET |
| Method + scenario + outcome | `calculateTotal_expiredCoupon_throws` | Legacy JVM conventions |

Rules:

- Name the **behavior**, not the method under test (`test_parse_2` is noise).
- Avoid "test1", "works", "happy_path" without a subject.
- Keep names searchable: a stack trace line should be enough to find the test.
- Parameterized cases get explicit case IDs so CI output reads
  `test_rounds_half_up[cash-fraction]`.

## Determinism

| Non-deterministic input | Fix |
|---|---|
| Current time | Inject a clock (`Clock` interface, `freezegun`/`time-machine`, `vi.setSystemTime`) |
| Random IDs / tokens | Inject an ID generator or seed; never assert on a specific random value |
| Random order of collections | Sort before asserting or compare as sets/multisets |
| Randomness in algorithms | Seed explicitly; property tests may be randomized with a recorded seed |
| Locale, timezone, encoding | Pin in the test config (`TZ=UTC`, `LC_ALL=C`, explicit `encoding="utf-8"`) |
| Environment variables | Load from a test config object; do not read `os.environ` implicitly |
| Network | Replace with a fake if the unit is not the network boundary |
| Concurrency | Prefer deterministic scheduling (latch/barrier) over `sleep` |

Rule of thumb: if a test fails once every N runs without a code change, it is broken even
if the current commit is "green" ([08-flaky-ci](./08-flaky-ci.md)).

## Isolation

- Tests must pass when run alone, in any order, and in parallel.
- No shared mutable module-level state; reset singletons and caches between tests.
- No test may depend on another test's side effects. Interdependence is often introduced
  by session-scoped fixtures; make shared fixtures immutable or reset them explicitly.
- Each test owns its data (unique IDs per run allows parallel and repeated execution
  ([07-test-data](./07-test-data.md))).
- Randomize test order periodically (e.g. `pytest-randomly`, Vitest `sequence.shuffle`) to
  expose hidden coupling.
- Parallelism should be safe by construction, not by pinning tests to one worker.

## Test Doubles Taxonomy

| Double | Definition | Use | Risk |
|---|---|---|---|
| Dummy | Placeholder passed but never used | Filling required parameters | Hides dead parameters |
| Stub | Returns canned values | Force a code path | Drifts from real behavior |
| Spy | Records interactions, delegates optionally | Assert a side effect happened | Over-specification |
| Mock | Preprogrammed expectations, fails on unexpected calls | Strict interaction contracts | Very brittle |
| Fake | Working, simplified implementation | Behavioral collaborator (in-memory repo) | Semantic divergence from production |

### Rules for doubles

1. **Mock boundaries you own.** Define a port/interface, then substitute it. Do not patch
   library internals; wrap them first.
2. **Prefer fakes for behavior, stubs for data, mocks sparingly.** A fake in-memory
   repository exercises real branching; a mock only proves the test's own expectation.
3. **Patch where it is looked up, not where it is defined.** `myapp.clients.payments`,
   not `stripe`.
4. **Never mock the unit under test.** If you must, the unit is too large; split it.
5. **Do not assert call order** unless order is a documented contract.
6. **Keep doubles in sync with reality** through contract tests on the real boundary
   ([06-contract](./06-contract.md)); otherwise stubs become fiction.
7. **One adapter per third-party** keeps vendor types out of domain code and gives tests a
   single seam.

```python
class InMemoryUserRepo:
    def __init__(self) -> None:
        self._by_id: dict[str, User] = {}

    def get(self, user_id: str) -> User | None:
        return self._by_id.get(user_id)

    def save(self, user: User) -> None:
        self._by_id[user.id] = user
```

## Parameterized Tests

Use tables to cover input classes; one assertion per case keeps failures precise.

```python
import pytest

@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        pytest.param("10", 10, id="positive"),
        pytest.param("-3", -3, id="negative"),
        pytest.param("0", 0, id="zero"),
    ],
)
def test_parse_int(raw: str, expected: int) -> None:
    assert parse_int(raw) == expected
```

- Give every case a stable ID; CI output is the only documentation most readers see.
- Keep tables small and thematic; a 60-row boolean matrix is a sign the unit should be
  decomposed.
- Use indirect parameterization for fixture-level variation only when it stays readable.
- Do not parameterize when cases need different arrange logic; that is a new test.

## Edge Cases and Boundary Analysis

For every input, ask: minimum, maximum, just inside/outside each boundary, empty,
one, many, duplicates, malformed, and adversarial.

| Input class | Cases |
|---|---|
| Numbers | 0, -0, min, max, overflow, NaN, infinity, float precision |
| Strings | empty, whitespace, unicode, combining chars, very long, embedded NUL |
| Collections | empty, single, many, duplicates, unsorted, nested, null elements |
| Dates/times | leap day, DST transition, month end, epoch, timezone boundaries |
| Identifiers | empty, max length, invalid chars, case sensitivity, URL-encoded |
| Concurrency | simultaneous writes, retries, cancellation mid-flight |
| Money | rounding halves, currency precision, negative values, zero-decimal currencies |

State transitions: test valid transitions, invalid transitions, and idempotency where the
domain claims it.

## Assertion Quality

- Assert on the **full meaningful result**: a single `assert result == expected` beats
  five partial asserts that can all pass while the object is wrong.
- Include a context message for non-obvious comparisons.
- Prefer structural equality (dataclasses, records) so new fields are covered
  automatically.
- Use domain-specific assertions (`assertThat(response).hasStatus(409)`) only when the
  error message is materially better.
- Avoid boolean collapse: `assert is_valid(x) is True` hides which branch failed; assert
  the underlying property instead.
- For exceptions: assert the type and the message/error code that clients depend on, not
  the full stack text.
- Floating point: use tolerance (`pytest.approx`, `expect(x).toBeCloseTo`) and state why.
- Never assert on `repr()` of complex objects.

### Weak vs strong assertions

| Weak | Strong | Why |
|---|---|---|
| `assert result is not None` | `assert result == expected_order` | Existence proves nothing |
| `assert mock.called` | `assert saved.status == "paid"` | Interaction vs outcome |
| `assert "error" in text` | `assert response.error_code == "EXPIRED_COUPON"` | Substring matching is accidental |
| `assert len(items) > 0` | `assert [i.id for i in items] == ["a", "b"]` | Order and content matter |
| `assert x != y` | `assert x == expected` | Negative assertions miss most defects |

## Snapshot Discipline

- Snapshots are useful for large serialized outputs (HTML, JSON, OpenAPI) when normalized.
- Normalize volatile fields (IDs, timestamps, sort order) before comparison.
- Snapshot updates are a reviewable change and must never happen automatically in CI.
- One snapshot per behavior; opaque 2000-line blobs hide regressions instead of revealing
  them.

## Anti-Patterns

- Assertion-free tests that only check "no exception".
- Mock-heavy tests where the test verifies its own stubs.
- One giant test with ten phases and no isolation.
- `time.sleep` in unit tests; inject the clock or poll with a deadline.
- Copy-paste test bodies with one literal changed; use parameterization.
- Testing private helpers; refactor to expose behavior.
- Catching broad exceptions in the test to keep it green.
- `@skip` without a linked issue and an owner.

## Unit Test Checklist

- [ ] AAA structure visible; one behavior per test.
- [ ] Name states scenario and expected outcome; parameterized cases have IDs.
- [ ] Time, randomness, locale, and I/O are injected or pinned.
- [ ] Tests pass alone, shuffled, and in parallel.
- [ ] Doubles sit at owned boundaries; fakes preferred for behavior.
- [ ] Boundary value analysis applied to numeric/string/date inputs.
- [ ] Assertions are outcome-based and produce readable failure messages.
- [ ] No assertion-free tests, no skipped tests without owner and expiry.
