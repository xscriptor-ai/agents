# Testing (JVM)

Scope: a working test strategy for JVM systems: JUnit 5, Kotest, mocking, Testcontainers, architecture tests, mutation testing, and CI reliability.

## Test strategy

| Layer | Purpose | Tools | Speed |
| --- | --- | --- | --- |
| Unit | Domain logic, pure functions, algorithms | JUnit 5, Kotest, AssertJ | Milliseconds |
| Slice | One integration seam (web, JPA, JSON) | `@WebMvcTest`, `@DataJpaTest`, MockMvc/WebTestClient | Seconds |
| Integration | Real dependencies, full context | `@SpringBootTest`, Testcontainers | Seconds to minutes |
| Contract | Consumer/provider compatibility | Pact, Spring Cloud Contract | Seconds |
| Architecture | Structural rules | ArchUnit, Konsist | Seconds |
| Mutation | Test suite quality on critical modules | PIT (pitest) | Minutes (nightly) |
| Performance | Regression thresholds | JMH, Gatling/k6 | Minutes (scheduled) |

Rules:

- The pyramid is about feedback speed, not counts. Push logic down into unit-testable code and keep integration tests for wiring and real-dependency behavior.
- Test behavior and contracts, not implementation details. Refactoring internals should not break tests.
- One logical assertion per test concept; multiple `assertAll` assertions are fine.
- Arrange-Act-Assert (or Given-When-Then) structure and names that describe the business rule, not the method name.
- Tests are production code: reviewed, refactored, and owned. Delete tests that cannot fail.

Anti-patterns:

- Ice-cream cone: mostly end-to-end tests, slow and flaky.
- Assertion-free tests ("does not throw").
- Testing getters/setters/framework behavior.
- Shared mutable fixtures across test classes.
- Coverage percentage as the only quality gate.

## JUnit 5 (Jupiter)

```java
class PricingTest {
    @ParameterizedTest
    @MethodSource("discountCases")
    void appliesDiscounts(BigDecimal base, int percent, BigDecimal expected) {
        assertThat(Pricing.apply(base, percent)).isEqualByComparingTo(expected);
    }

    static Stream<Arguments> discountCases() {
        return Stream.of(
            arguments(new BigDecimal("100.00"), 10, new BigDecimal("90.00")),
            arguments(new BigDecimal("99.99"), 0, new BigDecimal("99.99")));
    }

    @Test
    void rejectsNegative() {
        assertThatThrownBy(() -> Pricing.apply(BigDecimal.ONE, -1))
            .isInstanceOf(IllegalArgumentException.class);
    }
}
```

Features worth using:

- `@Nested` for scenario grouping; `@DisplayName` for readable reports; `@Tag` for suite selection.
- Lifecycle: `@BeforeEach`/`@AfterEach` per test; `@BeforeAll`/`@AfterAll` static or `@TestInstance(PER_CLASS)`. Prefer per-test isolation.
- `@TempDir` for filesystem tests; `@Timeout` for hang detection; `assertTimeoutPreemptively` only when necessary (it runs in another thread and can leak state).
- Extensions (`@ExtendWith`): manage resources, parameter resolution, and lifecycle. `@RegisterExtension` for per-test setup.
- Conditional execution: `@EnabledIfEnvironmentVariable`, `@EnabledOnOs`; avoid silent skips in CI.
- Dynamic tests and `@TestFactory` for generated cases.
- Parallel execution: opt in via `junit-platform.properties` (`junit.jupiter.execution.parallel.enabled=true`); tests must be independent. Do not parallelize Testcontainers-heavy suites without resource planning.
- Assertions: prefer AssertJ (`assertThat`) for readable failure messages; use `assertAll` to see all failures.

Anti-patterns:

- `@Disabled` without a linked issue and owner.
- Depending on execution order between tests.
- `Thread.sleep` for synchronization; use Awaitility (`await().atMost(...)`) or latches.
- Catch-and-ignore in tests, hiding failures under green builds.

## Kotest (Kotlin)

```kotlin
class OrderSpec : StringSpec({
    "rejects empty cart" {
        shouldThrow<IllegalArgumentException> { Order(emptyList()).checkout() }
    }

    "totals lines" {
        val order = Order(listOf(Line("a", 2, Money("3.00"))))
        order.total() shouldBe Money("6.00")
    }
})
```

Guidance:

- Spec styles: `StringSpec`, `DescribeSpec`, `BehaviorSpec`, `FunSpec` — pick one per module/repo for consistency.
- Assertions (`shouldBe`, `shouldThrow`) cover most needs; matchers compose well for collections.
- Property testing with `kotest-property` for parsers, invariants, and round-trip serialization.
- Data-driven testing via `withData`/`forAll`.
- Kotest runs on the JUnit Platform and coexists with JUnit 5; do not mix styles within one test class.
- Coroutines: `runTest`, `TestScope`, `StandardTestDispatcher`; use Turbine to assert Flow emissions.
- Use Kotest for idiomatic Kotlin suites; JUnit 5 remains fine and is required by some tooling (e.g., PIT plugin maturity).

Anti-patterns:

- Mixing Kotest and JUnit assertions in the same class.
- Overusing `Eventually`/`eventually` where deterministic awaiting is possible.
- Property tests without shrinking-friendly generators; failures must be reproducible.

## Mocking

| Tool | Language | Notes |
| --- | --- | --- |
| Mockito | Java | `@MockitoExtension`, strict stubs by default; mature |
| MockK | Kotlin | Kotlin-first: `coEvery`, `verify`, value classes, extension mocking; watch relaxed mocks |
| Fakes | Any | Hand-written in-memory implementations; fastest and most reliable |
| Spring `@MockBean`/`@MockitoBean` | Java/Kotlin | Spring context replacement; keep slice tests small |

Rules:

- Do not mock types you do not own. Wrap third-party clients in an interface you control and fake that.
- Prefer fakes for stateful collaborators (repositories, gateways); mocks for verifying interactions that are themselves the contract.
- Mock at architecture seams, not every dependency. A test full of mocks is a test of the mocks.
- Verify outcomes (returned data, persisted state) first; verify interactions only when the interaction is observable behavior (e.g., "must publish exactly one event").
- Strict stubs catch unused stubbing: remove dead stubs instead of relaxing strictness.
- Avoid mocking data classes/records; construct real instances.
- `relaxed = true` in MockK hides mistakes; use it sparingly and never in tests asserting behavior.
- Mocking static/object members (`mockkObject`, `mockStatic`) is a design smell; inject a seam instead.

Anti-patterns:

- Mocking `EntityManager`, `JdbcTemplate`, or HTTP clients directly instead of testing against the real thing in integration tests.
- Tests that only assert a method was called, not what the system did.
- Verifying exact call sequences; it locks in implementation and breaks on refactors.

## Spring test slices

| Annotation | Loads | Use |
| --- | --- | --- |
| `@WebMvcTest` | MVC layer, no JPA | Controllers, filters, validation, error mapping |
| `@WebFluxTest` | Reactive web layer | WebFlux controllers |
| `@DataJpaTest` | JPA + embedded/Testcontainers DB | Repository queries, mappings |
| `@JdbcTest` | JDBC/DataSource | jOOQ/JdbcTemplate tests (`./04-persistence.md`) |
| `@JsonTest` | Jackson | Serialization contracts |
| `@SpringBootTest` | Full context | Wiring, transactions, end-to-end service behavior |

Rules:

- Prefer the narrowest slice that exercises the behavior; full-context tests are slow and hide coupling.
- Use `@Testcontainers` plus `@ServiceConnection` (Boot 3.1+) so the application context points at real databases/brokers without property plumbing.
- Disable auto-configuration you do not need in slices; do not let tests drag the whole application.
- `@Transactional` on tests rolls back by default; it also masks flush/commit bugs. For persistence behavior you care about, flush explicitly and use non-transactional tests for commit semantics.
- Testcontainers singleton pattern (one container per JVM/suite) for speed; `withReuse(true)` for local runs only.
- Keep a `@TestConfiguration` for shared test beans; never import production-only configuration into tests accidentally.

Anti-patterns:

- One giant `@SpringBootTest` class with a dozen unrelated assertions.
- H2 for production-Postgres tests; SQL dialect and locking behavior differ. Use Testcontainers with the same engine.
- Testing `@Transactional` boundaries via mocks; only real transactions prove behavior.

## Testcontainers

```java
@Testcontainers
class OrderRepositoryTest {
    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> db = new PostgreSQLContainer<>("postgres:17-alpine");

    @Test
    void findsByStatus() { /* ... */ }
}
```

Rules:

- Same engine and major version as production (or the closest supported); never substitute H2 for PostgreSQL/Oracle behavior.
- Reuse containers (`withReuse(true)`) for local developer loops; keep isolated containers for CI to avoid cross-test state.
- Pin image tags/digests; `latest` makes builds non-reproducible.
- Use the right module per technology (Kafka, Redis, Vault, LocalStack) and wait strategies instead of sleeps.
- Ryuk cleanup is on by default; in restricted environments configure it rather than disabling it blindly.
- Container startup is a resource cost: budget CPU/memory in CI, and share containers across tests that can share state safely.
- Readiness checks: choose the module's wait strategy, not a fixed sleep; set startup timeouts.
- Seed data via migrations (Flyway/Liquibase) so tests exercise the real schema (`./04-persistence.md`).

Anti-patterns:

- Starting a container per test method.
- Tests that depend on leftovers from prior tests in a shared container.
- Random ports assumed stable across restarts; use `getMappedPort`.

## Architecture tests (ArchUnit / Konsist)

```java
@AnalyzeClasses(packages = "com.example")
class ArchitectureTest {
    @ArchTest
    static final ArchRule layers = layeredArchitecture()
        .consideringAllDependencies()
        .layer("Controllers").definedBy("..web..")
        .layer("Services").definedBy("..service..")
        .layer("Repositories").definedBy("..repo..")
        .whereLayer("Controllers").mayNotBeAccessedByAnyLayer()
        .whereLayer("Repositories").mayOnlyBeAccessedByLayers("Services");
}
```

Rules:

- Encode the architecture you intend to keep: layering, package cycles, naming, annotations, no field injection, no direct JDBC in web layer.
- Use `slices().matching("com.example.(*)..").should().beFreeOfCycles()` to prevent package tangles.
- Frozen violations (`FreezingArchRule`) to adopt rules incrementally in legacy code, with a plan to unfreeze.
- Konsist offers Kotlin-aware checks (KDoc, visibility, companion objects) where ArchUnit's bytecode view is awkward.
- Run architecture tests in the fast suite; they are cheap and catch drift early.

Anti-patterns:

- Architecture rules so broad they flag generated/framework code; exclude explicitly.
- Freezing violations forever; frozen rules hide new violations of the same kind.
- Documenting architecture only in diagrams while tests allow anything.

## Mutation testing (PIT)

- PIT mutates bytecode (boundary changes, negated conditionals, removed calls) and measures whether tests fail. Mutation score is a much better signal than line coverage.
- Scope: run PIT on critical modules (pricing, auth, state machines), not the whole monorepo on every commit.
- Thresholds: start with a baseline, require no regression (incremental analysis), and set module-specific goals.
- Configure `pitest-junit5-plugin` and target test classes by package; exclude generated code, DTOs, and trivial mappers.
- Use `timestampedReports` and incremental analysis in CI; schedule full runs nightly.
- Treat surviving mutants as a backlog: each survivor is either a missing test or dead code to delete.

Anti-patterns:

- Chasing 100% mutation score on code that does not warrant it.
- Running PIT per-commit on a large codebase (CI times explode).
- Chasing score by asserting implementation details instead of behavior.

## Async and concurrency testing

- Awaitility for eventual conditions with bounded waits; never `Thread.sleep`.
- Coroutines: `runTest` virtual time, `StandardTestDispatcher`, injected dispatchers (`./02-kotlin-core.md`); Turbine for Flow.
- Concurrency tests: stress with `ExecutorService` and barriers, then assert invariants; keep them in a separate, non-blocking-on-PR suite if slow.
- Timeouts on every async test so hangs fail fast instead of blocking CI.
- Avoid asserting exact interleavings; assert invariants and final states.

## CI test strategy

- Fail fast: lint, compile, ArchUnit, unit tests first; slices and integration tests after; nightly for mutation and long end-to-end.
- Shard tests across runners by module/package; keep each shard balanced and independently runnable.
- Retries: at most one automatic retry, and always record flaky tests. A retry that passes hides a race.
- Quarantine flaky tests with an owner and expiry date; a permanently quarantined test is deleted.
- Coverage: JaCoCo or Kover for visibility, plus mutation testing on critical modules; never a single global percentage gate.
- Contract tests (Pact) run in CI against provider verification; publish pacts from consumer builds.
- Artifacts: test reports, JFR/heap dumps on failure, container logs; without diagnostics a red build is unactionable.
- Keep the test suite fast enough that developers run it locally; if the unit suite exceeds a few minutes, fix test design before adding runners.

## Review checklist

- [ ] Domain logic unit-tested without Spring or containers.
- [ ] Integration tests use the same database engine as production via Testcontainers.
- [ ] No sleeps; Awaitility/virtual time used for async.
- [ ] Mocks only at owned seams; fakes for repositories/gateways where practical.
- [ ] Architecture rules enforced in the fast suite.
- [ ] Mutation testing gates critical modules (nightly), with a no-regression policy.
- [ ] Flaky tests quarantined with owners and expiry; retries tracked.
- [ ] CI publishes failure diagnostics (reports, logs, dumps).
