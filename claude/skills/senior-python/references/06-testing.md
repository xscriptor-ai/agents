# Testing

pytest layout and configuration, fixtures, parametrization, async tests, Hypothesis, mocking boundaries, Testcontainers, coverage, snapshots, and CI parallelism.

## Layout and Configuration

```toml
# pyproject.toml
[tool.pytest.ini_options]
minversion = "8.0"
testpaths = ["tests"]
addopts = "-ra --strict-markers --strict-config"
markers = ["integration: requires external services", "slow: nightly only"]
asyncio_mode = "auto"
asyncio_default_fixture_loop_scope = "function"
filterwarnings = ["error"]
```

- `--strict-markers` catches typo'd markers; `--strict-config` catches config typos.
- `filterwarnings = ["error"]` turns deprecations into failures before they become removals.
- `src/` layout keeps tests importing the installed package, not the working directory
  ([tooling](./07-tooling-packaging.md)).
- Recommended layout:

```text
project/
  src/pkg/
  tests/
    conftest.py
    unit/test_core.py
    integration/test_db.py
    fixtures/golden/
  pyproject.toml
```

- Keep `tests/` free of production imports by path hacks; install the package editable in
  dev (`uv sync`) so imports match production.

## Fixtures

```python
from collections.abc import Iterator
from pathlib import Path

import pytest

@pytest.fixture
def tmp_config(tmp_path: Path) -> Iterator[Path]:
    path = tmp_path / "config.toml"
    path.write_text("[app]\ndebug = false\n")
    yield path
```

- Fixture scope: `function` (default, isolated), `module`, `session` (expensive clients).
  Wider scopes leak mutable state; make shared fixtures immutable or reset explicitly.
- conftest hierarchy: root `tests/conftest.py` for universal fixtures, subdirectory
  conftest for area-specific ones. Avoid hidden autouse behavior.
- Prefer factories as plain functions over deep fixture graphs; fixtures are for lifecycle,
  factories for data.
- `yield` fixtures run teardown even on test failure; keep cleanup exception-safe.
- `request.addfinalizer` for multiple resources; `monkeypatch` auto-rolls back.
- Use `tmp_path`/`tmp_path_factory`, never the repo root or `/tmp` hardcoded.

## Parametrization

```python
import pytest

@pytest.mark.parametrize(
    ("raw", "expected"),
    [pytest.param("1", 1, id="positive"), pytest.param("-2", -2, id="negative")],
)
def test_parse(raw: str, expected: int) -> None:
    assert int(raw) == expected
```

- Name cases with `ids=` for readable CI output; use `pytest.param(..., marks=...)` to
  xfail or skip individual cases.
- Indirect parametrization lets fixtures vary by case: `@pytest.mark.parametrize("backend", [...], indirect=True)`.
- Do not build giant cross-product parametrizations that explode runtime; split or sample.
- Reproduce a single case with `pytest "tests/test_x.py::test_parse[negative]"`.

## Async Tests

- Choose one plugin: `pytest-asyncio` or `anyio`. Mixing both causes loop/fixture confusion.
- `pytest-asyncio`: `asyncio_mode = "auto"` marks async tests automatically, or use
  `@pytest.mark.asyncio` explicitly. Set `asyncio_default_fixture_loop_scope` to silence
  the deprecation and make loop scope explicit.
- Loop scopes: function-scoped loops isolate state but re-create clients per test;
  session-scoped loops share connection pools and context. Be deliberate — a shared loop
  with a shared session is a common source of cross-test pollution.
- anyio: `@pytest.mark.anyio` plus an `anyio_backend` fixture parametrized over asyncio/trio
  exercises both backends ([async](./03-async-concurrency.md)).
- Always add `pytest-timeout` (or `asyncio.timeout` inside the test) so a hung await fails
  the suite instead of hanging CI.
- Assert on cancellation behavior explicitly: start a task, cancel it, await, verify cleanup.

## Hypothesis

```python
from hypothesis import given
from hypothesis import strategies as st

@given(st.lists(st.integers()))
def test_reverse_twice(xs: list[int]) -> None:
    assert list(reversed(list(reversed(xs)))) == xs
```

- Property tests complement example tests: round-trips, idempotence, invariants, ordering.
- Reproduce failures with `@example(...)` (permanent regression) and `--hypothesis-seed=...`
  for a one-off replay.
- `derandomize=True` in CI trades coverage for reproducibility; keep nightly runs
  randomized.
- `st.assume` for preconditions; `target` to steer search toward interesting values.
- Stateful testing with `RuleBasedStateMachine` is excellent for caches, retries, and
  session lifecycles.
- Watch health checks: slow example generation or too-large data usually means the strategy
  is unbounded — constrain sizes.

## Mocking Boundaries

| Boundary | Tool | Notes |
|---|---|---|
| Environment, attributes | `monkeypatch` | Auto-rollback, no patching internals |
| Collaborator calls | `pytest-mock` `mocker` | Spies/assertions; keep to contracts |
| Time | `time-machine` or injected clock | Freezing `datetime` globally is brittle |
| Network | `respx` (httpx), `responses` (requests), fake server | Mock at HTTP layer, not the method |
| External SDK | Thin adapter + fake adapter | Keep vendor types out of domain code |

- Patch where the name is looked up (`app.clients.redis`, not `redis.Redis`).
- Prefer fakes over mocks when behavior matters (in-memory repository, fake queue, fake
  clock). Mocks assert interactions; fakes assert outcomes.
- Never mock the function under test; never assert on call order unless order is the
  contract.
- One adapter per third-party boundary makes both production code and tests cleaner.

## Testcontainers

```python
import pytest
from testcontainers.postgres import PostgresContainer

@pytest.fixture(scope="session")
def postgres() -> PostgresContainer:
    with PostgresContainer("postgres:17-alpine") as pg:
        yield pg
```

- Pin image tags for reproducibility; never `latest`.
- Combine with a session-scoped engine, run migrations once, then isolate per test via
  transaction rollback (fast) or truncated tables (simple).
- `with_reuse` speeds local iteration but creates hidden state; do not reuse in CI.
- Containers replace docker-compose services for integration tests; keep a small
  "smoke" set for external dependencies that cannot be containerized.
- Budget startup time: mark integration tests and run them on a separate CI job or
  schedule.

## Coverage

```toml
[tool.coverage.run]
branch = true
source = ["src"]
parallel = true

[tool.coverage.report]
show_missing = true
fail_under = 85
exclude_also = ["if TYPE_CHECKING:", "raise NotImplementedError"]
```

- Branch coverage exposes untested `else` paths; line coverage alone misleads.
- `parallel = true` plus `coverage combine` when using xdist; the coverage plugin in
  pytest-cov does this automatically.
- Gate CI with `fail_under` and review missing lines in the PR, but do not chase 100%.
- Exclude only generated code, `TYPE_CHECKING` blocks, and platform shims — with a reason.
- Coverage of tests themselves is noise; measure `src/`.

## Golden and Snapshot Tests

- `syrupy` for text/JSON/graph snapshots: `pytest --snapshot-update`, then review diffs in
  the PR like code.
- Golden files for large artifacts (report output, rendered HTML, OpenAPI schema). Normalize
  volatile fields (timestamps, UUIDs, ordering) before comparison.
- Never auto-update snapshots in CI; updates are a reviewable change.
- Keep one snapshot per behavior; huge opaque blobs make regressions hard to review.

## CI Parallelism and Flakiness

- `pytest-xdist`: `-n auto --dist loadgroup` for test suites; `loadscope` keeps
  module-scoped fixtures on one worker.
- Database tests need per-worker isolation: derive a database/schema name from the xdist
  `worker_id` fixture, or wrap each test in a rollback transaction.
- `pytest-randomly` reorders and reseeds; keep it on to expose inter-test dependencies and
  record the failing seed.
- Shard long suites (for example `pytest-split`) across CI jobs; keep total wall time below
  the reviewer attention span.
- Fast PR gate: `-m "not integration and not slow"`. Nightly: full run plus Hypothesis
  with more examples.
- Flaky test policy: quarantine with an owner and issue; retries (`pytest-rerunfailures`)
  are an emergency valve, and every retry should be logged and investigated.
- Common flake sources: `time.sleep` polling, shared ports, wall-clock assumptions,
  ordering dependencies, unbounded waits on external services.

## Anti-Patterns

- Testing implementation details: private methods, call order, or internal attributes.
- `time.sleep` instead of polling with a deadline or injecting a clock.
- One giant test that asserts ten behaviors; failures become ambiguous.
- Mocking so much that the test only exercises the mocks.
- Unit tests that hit the real network or production-like databases.
- Sharing mutable module state across tests without reset.
- Skipping slow tests forever; keep a scheduled full run.
- Assertions without context on complex data; use `pytest` diffs and `pytest.raises(match=)`.

## Checklist

- [ ] pytest configured in `pyproject.toml` with strict markers/config and warnings as
      errors.
- [ ] Tests use `src/` layout import semantics; no path hacks.
- [ ] Fixtures scoped deliberately; no hidden autouse state.
- [ ] Async tests use one plugin; loop scope explicit; timeouts enabled.
- [ ] Property tests cover core invariants; regressions have `@example`.
- [ ] Mocking happens at boundaries; fakes preferred for behavior.
- [ ] Integration tests use pinned Testcontainers images.
- [ ] Coverage uses branch mode with a reasonable CI gate.
- [ ] Suite runs in parallel with per-worker DB isolation; flaky tests are tracked.
