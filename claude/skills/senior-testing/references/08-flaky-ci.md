# Flaky Tests and CI Test Infrastructure

Detecting and quarantining flake, rerun policy, parallelism and sharding, timeouts, environment isolation, and ownership.

## Why Flake Is the Priority

A suite is trusted only if red means broken. Every flaky test erodes that trust: teams
rerun instead of reading, real regressions hide behind noise, and CI minutes burn. Flake
rate is a first-class quality metric, tracked with the same seriousness as coverage
([09-coverage-metrics](./09-coverage-metrics.md)).

Definitions used throughout:

- **Flaky** — a test that produces different results across runs of the same commit.
- **Flake rate** — flaky test executions / total executions over a window (per test and
  per suite).
- **Quarantine** — moving a flaky test out of the blocking suite into a tracked,
  owned, non-blocking suite with an expiry date.

## Detecting Flake

| Technique | What it catches | Notes |
|---|---|---|
| Rerun failures once and record | Intermittent tests | The record is the point; parsing JUnit XML required |
| Same-commit reruns in nightly | Order/timing dependence | Repeat the full suite 2-3 times |
| Test-level metrics over time | Gradual decay | Store per-test pass rate, duration, retries |
| Random order / seed sweep | Hidden coupling | `pytest-randomly`, Vitest shuffle, JUnit ordering |
| Parallelism | Shared resource collisions | Each worker must have isolated DB/ports |
| Nightly long runs (property, E2E) | Rare-input failures | Higher example counts, more browsers |
| Static heuristics | Known smells | `sleep`, fixed ports, shared temp paths, wall clock |

Tooling: JUnit XML is the common denominator; ingestion into the CI provider's test
analytics or a small database gives per-test history. Datadog CI Visibility, BuildPulse,
GitHub test reports, and codecov's flake detection all consume the same format. Pick one;
the analysis matters more than the brand.

## Quarantine Policy

1. **Detect** — CI marks a test flaky when it fails then passes on a same-commit rerun, or
   when its historical pass rate drops below a threshold (for example < 99%).
2. **Quarantine immediately** — an automated bot moves the test to a quarantine suite,
   opens an issue, and assigns the CODEOWNER. Blocking CI returns to green-fast.
3. **Budget** — quarantine has a hard expiry (for example 14 days) and a maximum size
   (for example 2% of tests). Exceeding the budget fails the quality metrics review, not
   the per-PR build.
4. **Fix or delete** — at expiry: fix with a root-cause note, or delete. Deleted flaky
   tests that covered real behavior must be replaced by a lower-layer test
   ([01-strategy](./01-strategy.md)).
5. **Never re-block the gate with an unfixed flaky test** — that trains reruns.

```yaml
# quarantine metadata example
quarantine:
  - test: "e2e/checkout.spec.ts::applies gift card"
    owner: payments-team
    issue: PAY-1234
    quarantined_at: 2026-09-01
    expires_at: 2026-09-15
    reason: "race on inventory reservation"
    replacement: "unit: inventory reservation is atomic"
```

- Quarantined tests still run (non-blocking) so signal is not lost and fixes can be
  verified.
- Report quarantine size and age in the weekly quality dashboard.
- No silent `@skip`; skips without issue and owner fail a lint check.

## Rerun Policy

Reruns are diagnostic, not a fix.

| Context | Allowed | Policy |
|---|---|---|
| PR gate | 1 automatic retry for infrastructure-classified failures only | Every retry logged; flake counted |
| Nightly E2E | 1-2 retries with artifact capture per attempt | Failure after retries becomes an issue |
| Local dev | Manual, unlimited | Developer investigates before pushing |
| Test-flight branch | Full reruns | Used to reproduce and confirm fixes |

- Classify failures: assertion (deterministic, no retry), timeout (retry once), infra
  (runner/network, retry once), unknown (capture artifacts, no retry until triaged).
- Count every retry as a data point; a test that retries frequently is flaky even if it
  never finally fails.
- Do not let retries mask a real intermittent bug in production code. Many "flaky tests"
  are actually race conditions in the system ([04-e2e](./04-e2e.md) flake table).
- Playwright/Pytest/Vitest all support retries; configure them centrally so a single
  policy applies.

## Parallelism and Sharding

### Parallelism within a run

- Ensure per-worker isolation: database schema/name per worker, unique ports (ephemeral
  port assignment, not fixed 5432 collisions), unique temp dirs, unique topic/bucket
  names ([07-test-data](./07-test-data.md)).
- Worker-aware fixtures: derive names from `PYTEST_XDIST_WORKER`, Playwright's
  `parallelIndex`, or a UUID per worker.
- Cap concurrency by resource, not CPU count alone: DB connection limits and container
  memory are the real bottlenecks.
- Keep tests independent: no shared login files written concurrently, no global mutable
  cache.

### Sharding across machines

| Sharding strategy | How | When |
|---|---|---|
| By duration (dynamic) | Historical timings split into equal buckets | Default for large suites |
| By file/package | Round-robin files | When tests are file-scoped |
| By tag | Critical vs extended | Separate the PR gate from nightly |
| By historical failure | Group known-slow suites separately | Avoid stragglers |

- Record durations from JUnit XML; a sharder without timings produces unbalanced runs.
- Keep a fallback: if a shard fails to report, fail the job rather than silently dropping
  tests.
- Verify total coverage: a shard plan must cover every test exactly once; add a meta-test
  for the collection step.
- Deterministic ordering within a shard helps debugging; cross-shard ordering is never
  guaranteed.

## Timeouts

Timeouts must exist at every layer, from smallest to largest:

| Layer | Example | Guidance |
|---|---|---|
| Unit test | 5 s default | `pytest-timeout`, Vitest `testTimeout` |
| Integration test | 30-60 s | Container startup excluded or measured separately |
| E2E test | 60-120 s | Playwright per-test timeout; action timeout shorter |
| Job | 15 min PR, 2 h nightly | CI-level; kills hung runs |
| Network call in test | 2-5 s | Lower than production defaults to fail fast |
| Global suite guard | Job timeout - 10% | Prevent zombie runners |

Rules:

- Never use a timeout as the *correctness* mechanism for waiting; poll with a deadline for
  the condition (`expect(...).toPass`, custom retry helper).
- Turn "hang forever" into an explicit failure with a diagnostic: which test, which step.
- Server-side timeouts under test (HTTP clients, queues) should be asserted, not just
  configured.
- Increase timeouts only with a recorded reason; a timeout bump is often masking a
  resource problem.

## Environment Isolation

- **Ephemeral > shared.** Per-PR environments avoid cross-team interference entirely. If
  shared staging is unavoidable, namespace every resource by run ID and enforce cleanup
  TTLs.
- Pin external dependency versions: container images by digest or tag, browser versions,
  database versions, locale/timezone, seeds.
- Pin locale and timezone explicitly (`TZ=UTC`, `locale=en-US`) — a runner default change
  breaks date assertions overnight.
- Freeze or inject clocks rather than relying on runner time
  ([02-unit](./02-unit.md)).
- Avoid port collisions: bind to port 0 and read the assigned port; never hardcode.
- Cache carefully: dependency caches are safe; build caches keyed on environment can hide
  drift. Include lockfile hashes in cache keys.
- Treat runner images as mutable infrastructure and version them; record the image digest
  in test reports.

## Ownership and Process

- **Owner per suite** in CODEOWNERS; the code owner receives failure notifications.
- **On-call for test infrastructure** — the platform team owns runners, containers, and
  sharding; product teams own their assertions.
- **Flake review in the weekly quality meeting**: top flaky tests, quarantine size, mean
  time to fix, flake rate trend.
- **Post-incident rule**: if a production incident would have been caught by a test that
  was quarantined or deleted, the quarantine policy gets reviewed.
- **No blame**: flake is a system property, tracked and fixed, not an individual failing.

## Anti-Patterns

- Retry counts of 3+ applied globally, with no recording of which tests retried.
- Quarantine without owner or expiry; a growing graveyard of skipped tests.
- Sharding without duration data; one shard runs 20 minutes while others run 3.
- Fixed ports, fixed temp paths, fixed tenant IDs across parallel workers.
- Increasing timeout after timeout instead of investigating the slow/hung path.
- Running E2E against shared staging with mutable global fixtures.
- Treating a "flaky infrastructure" excuse as resolution; infrastructure flake must be
  measured too.
- Hiding collection errors by allowing "no tests found" to pass.

## CI Health Checklist

- [ ] Same-commit reruns detect flake; flake rate is tracked per test and suite.
- [ ] Quarantine bot moves and tracks tests; owner, issue, and expiry required.
- [ ] Retry policy is explicit and excludes deterministic assertion failures.
- [ ] Workers are isolated (DB, ports, temp, topics) and concurrency is resource-bounded.
- [ ] Sharding uses recorded durations; shard completeness is verified.
- [ ] Timeouts exist at test, action, and job layers; no unbounded waits.
- [ ] Environments are ephemeral or run-namespaced; images, locale, TZ, and seeds pinned.
- [ ] CODEOWNERS covers test suites; infra on-call exists.
- [ ] "No tests found" and collection failures fail the build.
