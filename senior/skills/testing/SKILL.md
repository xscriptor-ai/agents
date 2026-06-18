---
description: "Cross-language testing strategies — unit vs integration vs E2E, mocking, test data management, flaky test handling, coverage metrics, CI integration"
---

# Testing Strategies

## Test Pyramid

- **Unit tests (70%)** — single function/class, fast, no I/O
- **Integration tests (20%)** — module boundaries, database, external services
- **E2E tests (10%)** — full user flow, critical paths only

## Unit Testing

### Structure: Arrange-Act-Assert (AAA)

```python
def test_calculate_discount():
    order = Order(items=[Item(price=100)], customer=Customer(loyalty=True))
    result = DiscountCalculator.calculate(order)
    assert result == 20.0
```

### Naming Convention

```
test_[unit]_[scenario]_[expected]
test_calculate_discount_loyalty_customer_returns_twenty_percent
```

### Coverage Targets

| Metric | Target | Minimum |
|--------|--------|---------|
| Line coverage | 85% | 70% |
| Branch coverage | 80% | 60% |
| Function coverage | 90% | 75% |

Do not chase 100% coverage — focus on critical paths.

## Integration Testing

### Database Testing

- Use test containers (Testcontainers, Docker Compose).
- Truncate tables between tests, never drop/create.
- Use factories or builders for test data.

```python
class TestOrderRepository(TestCase):
    @classmethod
    def setUpClass(cls):
        cls.container = PostgresContainer()
        cls.container.start()

    def test_saves_order_with_line_items(self):
        order = OrderFactory.build()
        repo = OrderRepository(self.connection)
        repo.save(order)
        saved = repo.get(order.id)
        assert saved.total == order.total
```

### External Service Integration

- Use WireMock or similar for HTTP stubs.
- Use real service in CI with sandbox credentials.
- Never call production from tests.

## Mocking Strategies

| Approach | Use When | Pitfall |
|----------|----------|---------|
| Stub | Return fixed values | Brittle to API changes |
| Mock | Verify interaction occurred | Over-specification |
| Fake | Working implementation, not production | Drift from real behavior |
| Spy | Record calls for later assertion | Same as mock issues |

### Rules

- Mock boundaries you own (interfaces you define).
- Do not mock types you do not own — wrap them.
- Use dependency injection to enable mocking.

## Test Data Management

- Factory pattern (FactoryBot, factory_boy) for defaults.
- Builders for complex objects with overrides.
- Seed data only for reference/lookup tables.
- Generate unique data per test run to avoid collisions.

## Flaky Test Handling

1. **Detect** — retry on failure in CI, tag with @flaky.
2. **Quarantine** — move to separate suite, do not block CI.
3. **Diagnose** — check for shared state, timeouts, ordering dependencies.
4. **Fix or Delete** — flaky tests erode trust. Delete if not fixable.

## CI Integration

| Stage | Tests | Parallelism | Timeout |
|-------|-------|-------------|---------|
| Pre-commit | Lint + fast unit | 1x | 2 min |
| PR | Unit + integration | 4x parallel | 10 min |
| Main merge | Full suite + E2E | 8x parallel | 20 min |
| Nightly | E2E + stress tests | 8x parallel | 60 min |

## Language-Specific Tooling

| Language | Unit | Mock | Coverage | Integration |
|----------|------|------|----------|-------------|
| Python | pytest | unittest.mock | pytest-cov | Testcontainers |
| TypeScript | vitest | vitest.mock | c8/v8 | Testcontainers |
| Go | go test | gomock | go test -cover | dockertest |
| Rust | cargo test | mockall | tarpaulin | testcontainers |
| Java | JUnit 5 | Mockito | JaCoCo | Testcontainers |
