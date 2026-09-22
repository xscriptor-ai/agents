# Migration and Modernization

Scope: moving JVM systems forward safely: Java 8/11/17 to 21+, Java-to-Kotlin, Spring Boot upgrades, GraalVM native images, and strangler-style modernization.

## Assessment first

Before touching versions, establish the baseline:

| Question | Evidence |
| --- | --- |
| What runs where? | Runtime inventory from deployment manifests, not memory |
| Which JDKs per service? | Build files, container images, base images |
| Which APIs are removed/deprecated? | `jdeps --jdk-internals`, `jdeprscan`, compiler warnings |
| Which dependencies are unsupported? | Dependency report plus upstream support windows |
| What is the test safety net? | Coverage of critical paths, integration tests, contract tests |
| What are the blast zones? | Public APIs, persisted data formats, serialized payloads, messaging schemas |

Rules:

- Migrate the smallest valuable increment, behind a seam, with measurable exit criteria.
- Never combine platform upgrade and feature work in one release; keep diffs reviewable.
- Have a rollback path for every step. If you cannot roll back, you cannot move fast.
- Automate the mechanical parts (OpenRewrite-style recipes) and review the rest by hand.

## Java 8/11/17 to 21+

### Code-level migrations

| Removed/changed | Replacement |
| --- | --- |
| `javax.*` EE APIs (on Jakarta stacks) | `jakarta.*` (JPA, Validation, Servlet, Mail, WebSocket) |
| Security manager | Platform sandboxing, container isolation; API is permanently disabled |
| `finalize()` | `Cleaner`, try-with-resources, explicit lifecycle |
| `sun.misc.Unsafe` memory access | `VarHandle`, `MethodHandles`, FFM (`java.lang.foreign`) |
| JAXB / JAX-WS / CORBA modules | Explicit dependencies or modern alternatives (Jackson XML, JAX-WS RI) |
| Nashorn | GraalJS or external JS execution |
| `Thread.stop/suspend/resume` | Interruption, cooperative cancellation |
| String templates | `String.format`, builders, templating libraries |
| 32-bit x86 runtime | 64-bit platform only on current releases |
| Non-generational ZGC | Generational ZGC (`-XX:+UseZGC` only) |
| CMS / old GC flags | G1 (default) or ZGC; strip obsolete flags from scripts |
| `--illegal-access=permit` | `--add-opens`/`--add-exports` per module, each tracked |

### Procedure

1. Update build tooling first (Gradle/Maven and plugins on a JDK-21-capable line, `./06-build-tooling.md`).
2. Compile with `--release 21` (or the target floor) and `-Xlint:all`; fix warnings before runtime testing.
3. Run `jdeps --jdk-internals`; every internal API reference becomes a task with an owner and replacement plan.
4. Run the full test suite on the new JDK before changing runtime flags.
5. Deploy to staging with production-like JVM flags; compare JFR profiles and GC logs against the old JDK.
6. Roll out canary; watch latency, GC pauses, thread counts, and error rates.
7. Only then adopt virtual threads, structured concurrency, or new language features — one change at a time.

### Adopting virtual threads during upgrade

- Audit for `synchronized` blocks around blocking calls; on JDK 21-23 these pin carriers. Replace with `ReentrantLock` before flipping executors.
- Remove thread-local request context or migrate to scoped values; measure thread-local usage growth.
- Replace fixed thread pools with virtual-thread-per-task executors, then re-check database pool sizes and downstream limits — the bottleneck moves (`./05-jvm-performance.md`).
- Verify pinning with JFR (`jdk.VirtualThreadPinned`) on the target JDK.
- Keep a fallback flag to revert to platform threads for one release.

### Common upgrade failures

| Symptom | Cause | Fix |
| --- | --- | --- |
| `NoClassDefFoundError: javax/...` | Stale dependency or generated code | Update to Jakarta artifacts; regenerate sources |
| Reflection `InaccessibleObjectException` | Strong encapsulation | Update library; temporary `--add-opens` with a task |
| Agent crashes / startup failure | Bytecode agent incompatible with new JDK | Update agent before upgrading the JDK |
| GC pauses changed drastically | Collector/flags differ from old defaults | Explicit collector choice and a new GC baseline |
| JIT/startup regression | Class data/AOT behavior changed | Warmup strategy, AOT cache, or native image (`./05-jvm-performance.md`) |
| Serialization incompatibility | Java serialization across versions | Move to JSON/Protobuf with explicit schemas |

## Java to Kotlin migration

Strategy: bidirectional interop means you can migrate module by module without a rewrite.

- Start with new code in Kotlin; migrate existing classes only when you touch them substantially.
- Order: leaf utilities → domain → services → controllers. Avoid mixing both languages in one class.
- Nullability at boundaries: annotate Java APIs with JSpecify (`@NullMarked`) so Kotlin sees real nullable types instead of platform types. Until then, treat platform types as nullable and enforce at the boundary (`./02-kotlin-core.md`).
- Convert DTOs/value objects to data classes first; they are mechanical and high-value.
- Replace static utility classes with extension functions or top-level functions; keep Java call sites working with `@JvmStatic`/`@JvmName`.
- Keep framework annotations working: Spring opens classes with the Kotlin plugin; JPA entities stay Java if the mapping is complex.
- Checked exceptions: Kotlin has none; Java callers of `suspend` functions need adapters or `runBlocking` only at edges.
- Wire tests at the same time; Kotlin tests can call Java code and vice versa. Use the same test runner where possible.
- Maintain a shared formatting/lint setup so both languages stay consistent.
- Track the K1→K2 compiler migration: remove `-language-version 1.9`, re-run builds, fix new diagnostics; K2 changes some inference and variance behavior.

Pitfalls:

- `!!` and platform types hiding nullability debt: add `requireNotNull` at Java boundaries with meaningful messages.
- Converting entities to `data class` breaks Hibernate; do not.
- Kotlin default arguments and overloads produce surprising Java APIs; use `@JvmOverloads` deliberately.
- SAM conversions in Kotlin differ from Java; check lambda-to-interface conversions at boundaries.
- Mixed collections mutability expectations: Kotlin's read-only interfaces do not stop Java mutating the underlying list.

## Spring Boot upgrades

### 2.7 → 3.x (the Jakarta jump)

- Baseline moves to Java 17; `javax.*` becomes `jakarta.*` everywhere (imports, dependencies, generated sources, test fixtures, messaging).
- Configuration: migrate `spring.config` handling, remove deprecated `application.properties` keys flagged by the Boot property migrator; enable `spring.config.import` for external config.
- Security: `WebSecurityConfigurerAdapter` is gone; lambda DSL only; adapters and `authorizeRequests` removed. Rewrite security configuration explicitly.
- Actuator: endpoint and property renames; health details defaults changed; expose surface minimized.
- Trailing slash matching default changed; path matching strategy changed. Review controller mappings.
- Observability: Micrometer/OTel integration and observations replace older Sleuth patterns.
- Procedure: upgrade dependencies to Spring Boot 3 line, fix compile errors (mostly imports and config), run tests, then review runtime property deprecations from the migration report.

### 3.x → 4.x (Framework 7)

- Framework 7 and Jakarta EE 11; JSpecify null-safety at the framework boundary; some modules renamed or split. Read the official migration guide; verify changes upstream.
- Removed/deprecated APIs from the 3.x line are gone; fix deprecation warnings before upgrading (that work is the upgrade).
- HTTP clients: `RestTemplate` remains but new code uses `RestClient`; HTTP interfaces are the default for typed clients.
- New capabilities (API versioning, resilience annotations, problem details) are optional; adopt after the core upgrade is green.
- Kotlin support requires a compatible Kotlin 2.x version; align the Spring and Kotlin plugins.
- Testing: slice annotations and `@MockitoBean`-style replacements evolve; update test configuration with the same care as production configuration.

### Upgrade mechanics

- Use OpenRewrite/automated recipes for the mechanical 80%: imports, property renames, security DSL shapes. Review all changes; recipes are not clairvoyant.
- Upgrade dependencies in waves; keep the dependency-management BOM as the single version source.
- Keep a `spring-boot-properties-migrator` classpath run (3.x) or review the property report to catch silently ignored configuration.
- Remove temporary compatibility shims as soon as the build is green; otherwise they become permanent debt.
- Test against the future major line early (a branch in CI) so the eventual upgrade is boring.

## GraalVM native and JVM AOT

| Option | Benefit | Cost |
| --- | --- | --- |
| Standard JVM | Peak throughput, full dynamic behavior | Slow cold start, higher memory |
| JVM AOT caches (class-loading and method profiling AOT in recent JDKs) | Faster startup, no closed-world constraints | Build/cache management, JDK-version coupling |
| GraalVM native image | Fastest startup, lowest memory for small services/CLI | Closed-world constraints, slower peak, longer builds, more testing |

Choose native when:

- Startup and memory dominate the business case: serverless, scale-to-zero, CLI tools, batch functions, edge.
- The dependency graph is compatible: Spring AOT hints exist, no dynamic agents, no runtime bytecode generation, no JIT-dependent hot loops.
- You can afford to run the full integration suite against the native binary and to maintain the build.

Do not choose native for:

- Long-running CPU-heavy services where peak throughput matters more than startup.
- Applications depending on dynamic proxies, deep reflection, or libraries without hints.
- Teams without capacity to debug native-image build failures.

Procedure:

1. Modernize the JVM build first; native is a second pipeline, not a substitute for upgrades.
2. Add Spring AOT (`processAot`) and native build plugins; fix hint gaps with `@RegisterReflectionForBinding`, `RuntimeHintsRegistrar`, or library updates.
3. Run contract and integration tests against the native binary in CI.
4. Measure honestly: cold start, warm throughput, RSS, p99 under load, build time.
5. Keep the JVM build as a fallback path; use the same configuration and tests.

Anti-patterns:

- Native image as a rewrite; it is a packaging change.
- Ignoring reflection failures until production; exercise every endpoint in tests.
- Assuming native is universally faster; it is often slower at peak and always slower to build.

## Strangler patterns for monoliths and frameworks

| Pattern | Shape | Use when |
| --- | --- | --- |
| Facade/proxy | New code routes to old and new implementations by feature/tenant | Incremental extraction without client changes |
| Branch by abstraction | Introduce an interface; implement old and new behind it; switch at runtime | Replacing a subsystem in place |
| Event interception | Tap domain events to mirror data into the new implementation | Read-side migration with backfill |
| Parallel run | Execute old and new, compare outputs, fail safe | High-risk logic replacement requiring validation |
| Expand/contract | Dual-write, backfill, switch reads, stop writes, remove old | Data/schema migrations (`./04-persistence.md`) |

Sequencing guidance:

- Define seams by business capability, not by technical layer; extracting a "UserService" while orders and billing share the same tables recreates the monolith.
- Data ownership first: decide which system owns each table before splitting behavior. Shared database writes are the main failure mode.
- Migrate reads before writes; consumers can fall back to the old path while the new one proves itself.
- Feature flags for routing; every flag has an owner and a removal date.
- Dual-write is a temporary hazard: reconcile continuously and have a single cutover authority.
- Monitor the seam: latency, error rate, and divergence between old and new paths.

Anti-patterns:

- Big-bang rewrite with no production feedback until the end.
- Distributed monolith: many services deployed together with synchronous coupling and shared schemas.
- Dual writes without reconciliation or a cutover plan.
- Migrating technology without a business capability boundary.

## Rollout, verification, and rollback

- Canary or blue/green for runtime and dependency changes; compare error rate, latency, GC, and saturation against baseline.
- Dark launch new paths (execute but discard results) to validate load behavior before exposing them.
- Feature flags with kill switches; default off for new risky paths.
- Error budgets: stop the migration when the budget is exhausted; continue when the service is healthy.
- Keep the previous artifact runnable and deployable until the new path is proven for a full business cycle.
- Document rollback steps in the release, including data migration reversibility (or forward-fix strategy when not reversible).

## Modernization anti-patterns

- Version bumps with no test/observability safety net.
- Combining JDK, framework, and language upgrades in one release.
- Permanent `--add-opens`/shim layers with no owner.
- Rewriting in Kotlin/another framework to avoid fixing design problems.
- Migrating to microservices before defining data ownership.
- Assuming preview APIs are stable across JDK upgrades.

## Migration checklist

- [ ] Inventory and dependency report complete; ownership assigned.
- [ ] Target JDK/framework/language versions pinned and CI matrix updated.
- [ ] Removed API usage (`jdeps`, `jdeprscan`) resolved or explicitly tracked.
- [ ] `javax` to `jakarta` (and other renames) applied mechanically, reviewed manually.
- [ ] Test suite green on the new platform; contract tests included.
- [ ] Performance baseline compared (JFR, GC logs, p99 under load) before/after.
- [ ] Each increment behind a seam with a rollback path and canary rollout.
- [ ] Native/AOT decision made with measured startup and throughput data, not ideology.
