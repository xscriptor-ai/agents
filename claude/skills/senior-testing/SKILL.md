---
name: senior-testing
description: 'Cross-language testing reference pack: strategy and the pyramid/trophy
  trade-off, unit, integration, end-to-end, property-based, mutation, and consumer-driven
  contract testing, test doubles, test data management, flake control, CI parallelism,
  coverage and quality metrics, and AI-assisted test generation. Use when planning
  a test strategy, deciding what to test at which layer, writing or reviewing unit,
  integration, E2E, contract, or property tests, choosing test doubles, designing
  factories and fixtures, stabilizing a flaky suite, wiring sharding and reruns in
  CI, interpreting coverage or mutation scores, or reviewing LLM-generated tests.
  Tooling ranges cover pytest, Vitest, Playwright, Testcontainers, Hypothesis, fast-check,
  proptest, jqwik, Pact, Stryker, PIT, and cargo-mutants. Optional pack: consumers
  degrade gracefully when it is absent.'
---

# Testing

Cross-language testing practice for senior engineers, current through 2026. The pack is
tool-agnostic in its rules and concrete in its examples: pytest, Vitest, Jest, go test,
cargo test, and JUnit 5 on one side; Playwright, Testcontainers, Hypothesis, fast-check,
proptest, jqwik, Pact, Stryker, PIT, and cargo-mutants on the other. It assumes tests run
in CI containers, that a build pipeline gates merges, and that a human reviews every test
change.

## Domain Overview

- **Purpose** — tests are a risk-reduction investment, not a ritual. Every test must answer
  "what defect will this catch that nothing cheaper already catches?"
- **Layers** — unit tests pin logic; integration tests pin boundaries (DB, HTTP, queues);
  contract tests pin cross-service interfaces; E2E tests pin the critical user paths.
  The classic pyramid still fits most backends; frontends and CLIs often behave like a
  trophy: heavy integration, thinner unit, few E2E ([strategy](./references/01-strategy.md)).
- **Determinism** — the top source of lost trust is flake, not missing tests. Order
  dependence, shared state, wall-clock assumptions, and unseeded randomness are defects in
  the suite and are fixed or deleted, never normalized ([flaky CI](./references/08-flaky-ci.md)).
- **Economics** — the cost of a test grows with its layer (runtime, setup, maintenance),
  so the default is the lowest layer that can detect the failure. Test budget is finite;
  spend it on risk, not on code coverage vanity ([strategy](./references/01-strategy.md),
  [metrics](./references/09-coverage-metrics.md)).
- **Proof beyond examples** — property-based tests explore input classes; mutation testing
  measures whether assertions actually constrain behavior; contract tests measure interface
  compatibility. These are gates, not extras ([property and mutation](./references/05-property-mutation.md),
  [contracts](./references/06-contract.md)).
- **AI ergonomics** — LLM-generated tests are drafts: fast to produce, prone to
  hallucinated APIs, tautological assertions, and over-mocking. They require review,
  execution, and human sign-off like any other diff ([AI-assisted](./references/10-ai-assisted.md)).

## Core Rules (non-negotiable)

1. **Tests are production code.** They are versioned, reviewed, type-checked or linted,
   and refactored when they hurt. A test nobody can maintain is a liability, not an asset.
2. **Every test has a failure mode and an owner.** A test that cannot fail, or whose
   failure nobody would act on, is deleted. Flaky and skipped tests carry an owner and an
   expiry date.
3. **Deterministic by default.** No wall clock, no unseeded randomness, no real network in
   unit tests, no inter-test order dependence, no shared mutable state. Freeze time and
   seed randomness explicitly when they are inputs.
4. **Assert outcomes, not implementation.** Verify observable behavior and contracts.
   Avoid asserting private calls, internal ordering, or log strings unless they are the
   contract.
5. **Use the lowest useful layer.** If a unit test can catch the defect, do not write an
   E2E. E2E is reserved for journeys no lower layer can exercise end to end.
6. **Mock only boundaries you own.** Do not mock types you do not control; wrap third-party
   SDKs in a thin adapter and fake the adapter ([unit](./references/02-unit.md)).
7. **Test data is generated, isolated, and synthetic.** Unique per run, never production
   PII, never shared mutable fixtures across tests ([test data](./references/07-test-data.md)).
8. **A red suite stops the line.** Fix, quarantine with owner and expiry, or delete.
   Retries and reruns are diagnostic instruments, never the policy ([flaky CI](./references/08-flaky-ci.md)).
9. **Quality gates must be explainable.** Coverage, mutation score, and flake rate have
   owners, trends, and a stated purpose. A gate the team games is worse than no gate
   ([metrics](./references/09-coverage-metrics.md)).
10. **Test changes ship with the code that needs them.** A behavioral change without a
    test change is incomplete; a test change without a behavioral reason is suspect.

## Decision Tables

### Which layer for this defect

| Defect class | Lowest layer that catches it | Notes |
|---|---|---|
| Pure logic, branching, validation | Unit | Property tests for input classes |
| Serialization, API shape, DI wiring | Component / integration | Cheaper than E2E |
| SQL, migrations, constraints, transactions | Integration (real DB) | Testcontainers, not H2/SQLite substitutes |
| Cross-service interface drift | Consumer-driven contract | One per consumer-provider pair |
| Auth, payments, signup, checkout journeys | E2E | Critical paths only, small count |
| Performance, load, concurrency | Dedicated perf suite | Separate pipeline, not PR gate |
| Visual/accessibility regressions | Component or E2E with snapshots | Tolerance thresholds required |

### Test budget by system type

| System | Unit | Integration | Contract | E2E | Rationale |
|---|---|---|---|---|---|
| Backend service | 50-70% | 20-35% | per pair | 5-10 journeys | Logic-dense, boundary-heavy |
| Frontend SPA | 20-40% | 40-60% (component) | shared contracts | 5-10 journeys | Rendering is integration work |
| CLI tool | 60-80% | 10-20% | n/a | smoke only | Deterministic I/O |
| Data/ML pipeline | 40-60% | 30-50% (data fixtures) | schema tests | few | Data contracts matter most |
| Infrastructure | n/a | plan/apply tests | n/a | drift checks | Tests are plan assertions |

### Test double selection

| Need | Double | Cost | Failure mode it invites |
|---|---|---|---|
| Return canned values | Stub | Low | Drifts from real API |
| Verify a call happened | Mock/spy | Low | Over-specification, brittle |
| Working in-memory behavior | Fake | Medium | Diverges from production semantics |
| Record and replay boundaries | Contract/snapshot | Medium | Stale recordings |
| Real dependency | Testcontainer/embedded | High | Slower CI, image churn |

### Language tooling floors (verify upstream for current releases)

| Language | Runner | Doubles | Property | Mutation | Coverage |
|---|---|---|---|---|---|
| Python >= 3.12 | pytest 8+ | unittest.mock, pytest-mock, fakes | Hypothesis | mutmut / cosmic-ray | coverage.py / pytest-cov |
| TypeScript | Vitest 2+ or Jest 29+ | Vitest `vi`, msw, sinon | fast-check | StrykerJS | v8/Istanbul |
| Go >= 1.22 | go test | interfaces + gomock | rapid / gopter | go-mutesting / gremlins | go test -cover |
| Rust | cargo test | mockall / trait fakes | proptest / quickcheck | cargo-mutants | llvm-cov / tarpaulin |
| Java/Kotlin 21+ | JUnit 5 | Mockito | jqwik | PIT / pitest | JaCoCo |
| C#/.NET 8+ | xUnit | Moq / NSubstitute | FsCheck | Stryker.NET | coverlet |

### CI stage policy

| Stage | Scope | Budget | Failure policy |
|---|---|---|---|
| Pre-commit | Lint, format, fast unit subset | <= 2 min | Blocks commit locally |
| Pull request | Unit + integration + contracts | <= 15 min | Blocks merge; flaky => quarantine |
| Main merge | Full suite + smoke E2E | <= 30 min | Blocks release tag |
| Nightly | E2E, mutation, property-long, perf | <= 2 h | Files issues, no merge block |
| Release candidate | Full E2E on prod-like env + migration tests | Gate | Manual sign-off |

### What not to test

- Generated code, framework code, and language runtime.
- Trivial getters/setters and pass-through wrappers with no logic.
- Third-party library internals (their tests are upstream's job).
- Log wording, private method call counts, and object identity unless contractual.
- Exact timestamps, random UUIDs, or ordering that the spec does not promise.
- The same behavior at two layers "for safety"; that is duplicated maintenance cost.

## Reference Index

Load only what the task needs. All paths are relative to this file.

| # | Reference | Scope | Load when |
|---|---|---|---|
| 01 | [references/01-strategy.md](references/01-strategy.md) | Pyramid vs trophy, risk-based testing, test budget, what not to test, ownership, shift-left/right | Planning a strategy, allocating effort, deciding what to skip |
| 02 | [references/02-unit.md](references/02-unit.md) | AAA, naming, determinism, isolation, doubles taxonomy, parameterized tests, edge cases, assertion quality | Writing or reviewing unit tests, choosing mocks vs fakes |
| 03 | [references/03-integration.md](references/03-integration.md) | Component boundaries, database tests, Testcontainers, HTTP stubs, transactions, cleanup, suite speed | Testing repositories, queues, HTTP clients, or DB behavior |
| 04 | [references/04-e2e.md](references/04-e2e.md) | Critical-path selection, Playwright patterns, selectors, auth state, test data, traces/video, flake control | Building browser or end-to-end suites, stabilizing them |
| 05 | [references/05-property-mutation.md](references/05-property-mutation.md) | Property-based testing in Hypothesis, fast-check, proptest, jqwik; shrinking/invariants; Stryker, PIT, cargo-mutants as gates | Proving invariants, raising assertion strength, quality gates |
| 06 | [references/06-contract.md](references/06-contract.md) | Consumer-driven contracts with Pact, schema compatibility, provider verification, versioning, contracts vs E2E | Multiple services or teams share an interface |
| 07 | [references/07-test-data.md](references/07-test-data.md) | Factories/builders, fixtures, seeding, PII and anonymization, unique data per run, DB snapshots | Designing shared test data, eliminating collisions and PII |
| 08 | [references/08-flaky-ci.md](references/08-flaky-ci.md) | Flake detection and quarantine, rerun policy, parallelism/sharding, timeouts, environment isolation, ownership | CI is slow, red on retry, or non-deterministic |
| 09 | [references/09-coverage-metrics.md](references/09-coverage-metrics.md) | Coverage types and pitfalls, diff coverage, mutation score, DORA metrics, honest dashboards | Setting gates, reading quality dashboards, reporting metrics |
| 10 | [references/10-ai-assisted.md](references/10-ai-assisted.md) | LLM-generated tests, review requirements, adversarial cases, prompt patterns, hallucinated assertions, human sign-off | Using LLMs to draft tests, reviewing AI-generated suites |

## Port

- **Port id** — `skill://senior/testing` (version in `metadata.port-version`).
- **Kind** — read-only reference pack; no side effects, no tools required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "testing" })` in OpenCode; Claude Code reads `<skills-dir>/testing/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers reference it as `load skill senior-testing (optional)`.
- **Cross-pack links** — language packs carry implementation-level testing chapters (for example `skill://senior/python` reference 06); this pack owns cross-language strategy and the contract between layers.
- **Stability** — `stable`; breaking changes bump `port-version` major.
