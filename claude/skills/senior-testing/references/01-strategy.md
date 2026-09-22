# Test Strategy

Choosing test layers, allocating budget by risk, deciding what not to test, assigning ownership, and balancing shift-left with shift-right.

## The Strategic Question

A test strategy is an answer to four questions:

1. **What can fail?** (failure modes, not code coverage targets)
2. **How would we know, and how fast?** (detection layer and feedback time)
3. **How much does that detection cost to build and keep?** (runtime, setup, maintenance)
4. **Who acts when it fires?** (owner, runbook, severity)

If a test cannot be connected to a failure mode and an owner, it is ritual. Strategy is
about deliberately accepting risk elsewhere, not pretending every risk can be tested.

## Pyramid vs Trophy vs Honeycomb

### The classic pyramid

| Layer | Share | Speed | Confidence in integration |
|---|---|---|---|
| Unit | ~70% | ms | None |
| Integration / component | ~20% | 100 ms - 5 s | High for own boundaries |
| E2E / UI | ~10% | 10 s - 5 min | Highest, slowest, flakiest |

The pyramid optimizes for fast feedback and cheap maintenance. It remains correct for
logic-heavy backends, libraries, compilers, and data engines.

### The testing trophy (frontend and CLI reality)

Kent C. Dodds' trophy is a better fit when behavior emerges from composition of many
small units rather than from a few pure functions:

| Layer | Share | What it means in practice |
|---|---|---|
| Static analysis | "free" | Types and lint catch a large defect class before runtime |
| Unit | ~20% | Pure logic, reducers, formatters, parsers |
| Integration | ~50% | Render a component tree, hit a real router and fake server |
| E2E | ~10% | Few critical journeys through a real browser |

For React/Vue/Svelte apps the component integration layer is where most regressions
(simulated effects, routing, state wiring) actually surface; unit-testing every hook in
isolation produces a broad but shallow suite.

### Choosing explicitly

| Context | Model | Why |
|---|---|---|
| Domain/business logic library | Pyramid | Logic is pure, units are meaningful |
| CRUD backend service | Pyramid with fat integration layer | Many defects live at SQL/HTTP boundaries |
| SPA / design system | Trophy | Behavior emerges from composition |
| Event-driven / microservices | Honeycomb (many contracts, thick service tests) | Correctness lives in interactions |
| CLI / data pipeline | Pyramid + golden files | Deterministic I/O |
| ML training code | Split: unit on transforms, slow integration on end-to-end training | Training is too slow to E2E often |

Do not argue about the metaphor. Agree on the number of tests per layer, their expected
runtime, and what runs in which pipeline stage ([08-flaky-ci](./08-flaky-ci.md)).

## Risk-Based Testing

### Scoring model

Score each capability on likelihood (1-5) and impact (1-5); test investment follows the
product.

| Factor | 1 | 3 | 5 |
|---|---|---|---|
| Change frequency | Stable for years | Monthly | Daily |
| Business impact if wrong | Cosmetic | Recoverable | Revenue, safety, compliance |
| Complexity / cyclomatic | Trivial | Moderate | Branch-heavy |
| History of defects | None | Occasional | Repeated incidents |
| Boundary count (I/O, network, DB) | None | One | Several |
| Blast radius | One screen | One service | All tenants / all customers |

Risk score = likelihood x impact. High (>= 15) gets unit + integration + at least one
E2E. Medium (6-14) gets unit + integration. Low (<= 5) gets a unit test or nothing but a
smoke check.

### Risk categories that are never "low"

- Authentication and authorization decisions.
- Money movement, pricing, and tax calculation.
- Personal data handling and consent.
- Schema migrations and data deletion paths.
- Idempotency and retry behavior of externally visible writes.
- Anything with a regulatory or contractual obligation.

For these, the expected artifact is an automated test at the lowest layer that can fail
plus a monitoring signal in production (shift-right).

## Test Budget

Budget along three axes: **money** (CI minutes, device farms), **time** (feedback latency
for developers), and **attention** (how many failures a team will actually inspect).

Practical rules:

- Pull request gate target <= 15 minutes p95. Beyond that, developers batch changes and
  stop reading failures ([08-flaky-ci](./08-flaky-ci.md)).
- Keep the fast suite (unit + component) under 5 minutes on a laptop; this is the suite a
  developer runs while editing.
- Every E2E scenario must justify its minutes. If two journeys share 90% of steps, merge
  them into one journey with multiple assertions.
- Prefer one integration test over five unit tests that mock the same boundary, and one
  contract test over an E2E that exists only to catch field renames.
- Allocate roughly 10-20% of engineering time to test upkeep. If upkeep is invisible, the
  suite is decaying silently.

### Cost of a test over its life

```text
total cost = authoring + review + (runs per day x wall-clock cost) + maintenance + flake triage
```

A 200 ms unit test run 500 times a day costs ~100 seconds of machine time. A 4-minute E2E
run 50 times a day costs 3.3 hours plus a person triaging flakes at ~10% rate.

## What Not to Test

| Do not test | Reason | Do instead |
|---|---|---|
| Framework internals (routing library, ORM internals) | Upstream owns it | Test your configuration of it at one seam |
| Generated code (protobuf, OpenAPI clients, migrations autogen) | Not hand-written | Test the generator invocation and the generator's own tests |
| Trivial accessors and DTO pass-throughs | Zero logic, zero defect class | Rely on types and the first integration path |
| Log message text | Non-contractual, drives churn | Assert on structured event fields if they are contractual |
| Private methods | Implementation detail | Test via public behavior |
| Exact UUIDs/timestamps | Non-deterministic inputs | Inject clock/ID generator; assert format and ordering |
| Third-party behavior | You cannot change it | Contract test the boundary you consume ([06-contract](./06-contract.md)) |
| Dead code, feature-flagged code past removal date | Waste | Delete the code, then the tests |

Counterpoint: "do not test" is not "do not verify". If unit tests are skipped for a
boundary, some other artifact (contract test, monitor, canary) must cover it.

## Ownership

- **Every test file has an owner** recorded in `CODEOWNERS` or an equivalent map. Unowned
  suites rot first.
- **The team that owns the code owns its tests.** A central QA team is a bottleneck and a
  knowledge island; platform teams own test infrastructure, not other teams' assertions.
- **Quarantined tests have an owner and an expiry** (issue link plus date). Expired
  quarantine auto-deletes or auto-fails the build, otherwise quarantine becomes a landfill
  ([08-flaky-ci](./08-flaky-ci.md)).
- **Test infrastructure has an on-call.** When the runner is down or the container registry
  is throttled, someone is paged.
- **Failures page the code owner, not the test author.** Ownership follows code, not the
  person who happened to write the assertion.

## Shift-Left and Shift-Right

### Shift-left (move detection earlier)

| Practice | Catches | Cost |
|---|---|---|
| Static analysis and strict types | Type errors, nullability, dead code | Minutes to adopt, ongoing discipline |
| Pre-commit hooks (lint, format, fast tests) | Formatting, obvious breakage | Developer latency |
| Contract tests in CI | Interface drift before deploy | Pact broker or schema registry |
| Test-first / TDD where logic is unclear | Design problems, missing cases | Learning curve |
| Property tests on pure functions | Edge cases humans miss | Strategy authoring |
| Migration tests against a real DB | Schema breakage | Testcontainers runtime |

### Shift-right (verify in production)

| Practice | Catches | Note |
|---|---|---|
| Canary / progressive delivery | Deployment faults, perf regressions | Requires rollback automation |
| Synthetic monitoring of critical journeys | Outages, cert expiry, third-party failures | Independent of user traffic |
| Structured error budgets and alerts | Unknown unknowns | Alert on user-visible symptoms |
| Production traffic shadowing / replay | Behavioral drift under real inputs | PII scrubbing mandatory |
| Feature-flag ramp with metric guardrails | Business-logic regressions | Flags carry expiry dates |

Pairs: shift-left catches what can be known before release; shift-right catches what can
only be known after. A strategy with only one of the two is incomplete.

## Anti-Patterns

- **Coverage as goal** — writing assertion-free tests to move a number
  ([09-coverage-metrics](./09-coverage-metrics.md)).
- **Ice cream cone** — mostly E2E with weak unit/integration; slow, flaky, expensive.
- **Test everything everywhere** — same behavior asserted at three layers; triple
  maintenance, no extra detection.
- **Set-and-forget suite** — no owner, no flake budget, no runtime budget.
- **QA as gatekeeper** — manual verification at the end of the cycle; feedback too late.
- **Copy-pasted test templates** — 200 tests that all exercise the happy path with
  different names.
- **Retry-as-policy** — green build by rerunning red tests instead of fixing them.
- **Testing the mock** — assertions that only verify the test's own stubs
  ([02-unit](./02-unit.md)).

## Strategy Review Checklist

- [ ] Risk register maps capabilities to test layers; high-risk items have E2E or contract
      coverage.
- [ ] Layer distribution is intentional and recorded (pyramid, trophy, or honeycomb).
- [ ] PR gate runtime p95 <= 15 minutes; fast suite <= 5 minutes.
- [ ] Every test file has an owner; quarantine has owner + expiry.
- [ ] What-not-to-test list exists and is enforced in review.
- [ ] Detection layers pair with production monitoring for non-deterministic risks.
- [ ] Flake rate and runtime are tracked as first-class quality metrics
      ([09-coverage-metrics](./09-coverage-metrics.md)).
- [ ] Test budget is revisited quarterly or after each major incident.
