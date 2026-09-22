---
name: senior-java-kotlin
description: JVM reference pack for Java 21-25, Kotlin 2.x with K2, Spring Boot 3.5+/4.x,
  persistence, JVM performance, Gradle/Maven, testing, Android/Compose, observability,
  security, and migrations. Use when writing, reviewing, tuning, or modernizing Java
  or Kotlin services and libraries; when choosing JVM frameworks, build tooling, concurrency
  model, or GC strategy; when diagnosing JVM production incidents; or when planning
  Java, Kotlin, Spring Boot, or Android upgrades.
---

# Java / Kotlin

Production reference for JVM work: Java 21-25 language features and runtime, Kotlin 2.x with the K2 compiler, Spring Boot, persistence, performance, build tooling, testing, Android, observability/security, and migration paths. Content targets the state of the ecosystem in 2026. The LTS floor is Java 21; Java 25 is the current LTS line; feature releases ship every six months, so verify the current release upstream before pinning.

## Version floors

| Component | Floor | Notes |
| --- | --- | --- |
| Java | 21 (LTS) | New code should not target below 21. Java 25 is the current LTS; 26/27 are feature releases. |
| Kotlin | 2.0 (K2) | K2 is the only supported compiler frontend going forward; prefer 2.1+ for tooling maturity. |
| Spring Boot | 3.5 (maintenance) / 4.x (current) | Boot 3.x requires Java 17; the 4.x line moves to Framework 7 and Jakarta EE 11. Verify exact versions upstream. |
| Jakarta EE | 10 / 11 | `javax.*` is dead on these lines; all imports are `jakarta.*`. |
| Hibernate | 6.6+ / 7.x | Hibernate 7 aligns with Jakarta Persistence 3.2. Verify support matrix upstream. |
| Gradle | 8.x / 9.x | Kotlin DSL is the default; a JVM 17+ toolchain runs the daemon. |
| Android | minSdk 24+ | `targetSdk` must track the annual Play requirement; AGP and Kotlin at latest stable. |
| Coroutines | 1.9+ | Structured concurrency semantics are stable; check dispatcher/API additions per minor. |

## Non-negotiable core rules

1. **Constructor injection only.** No field injection, no `@Autowired` on fields, no service locator. It keeps dependencies explicit, immutable, and testable.
2. **Immutability by default.** Records, Kotlin `val`, `data class`, sealed hierarchies, immutable collections. Mutability is a deliberate, documented choice.
3. **Validate at boundaries, trust internals.** Jakarta Validation on controllers, messaging consumers, and `@ConfigurationProperties`; domain logic assumes already-valid input.
4. **Know your threads.** Never block an event loop; never assume a request is on a platform thread. Reactive only when the workload justifies it (`./references/03-spring-boot.md`).
5. **One unit of work, one transaction, declared at the service boundary.** No HTTP calls, no messaging, no file I/O inside an open transaction (`./references/04-persistence.md`).
6. **Production schemas change only through versioned migrations.** `ddl-auto=update` is forbidden outside tests (`./references/04-persistence.md`).
7. **Every remote call has a timeout, every pool has a bound.** HTTP clients, DB pools, executors, and queues without limits are outage generators.
8. **Observability is part of the definition of done.** Health, metrics, traces, and structured logs with correlation IDs ship with the feature (`./references/09-observability-security.md`).
9. **Virtual threads remove thread scarcity, not backpressure.** Pool what is genuinely scarce: DB connections, file handles, downstream quotas (`./references/05-jvm-performance.md`).
10. **Measure before tuning.** Percentiles over averages, JFR and async-profiler over intuition, JMH for microbenchmarks, load tests for macro behavior.
11. **Pin and lock everything.** Toolchains, dependency versions, and checksums; builds must be reproducible and reviewable (`./references/06-build-tooling.md`).
12. **Tests are deterministic.** No `Thread.sleep`, no order dependence, no shared mutable fixtures; use Testcontainers for real dependencies (`./references/07-testing.md`).
13. **Secrets and PII never touch logs, dumps, or artifacts.** Secrets come from a managed store with rotation (`./references/09-observability-security.md`).
14. **Treat deprecations as deadlines.** Track compiler warnings, `jdeprscan`, and removal JEPs; never add new usage of APIs slated for removal (`./references/01-java-core.md`, `./references/10-migration-modernization.md`).
15. **Prefer incremental migration behind seams.** Big-bang rewrites of Java, Kotlin, or Spring upgrades fail; use the strangler patterns (`./references/10-migration-modernization.md`).

## Decision tables

### Language and platform

| Situation | Choose | Avoid |
| --- | --- | --- |
| Greenfield JVM service, team fluent in Kotlin | Kotlin 2.x with K2 | Kotlin as a "Java with less typing" without learning null safety and coroutines |
| Library consumed by Java and Kotlin clients | Java 21+ records/sealed types | Kotlin-only APIs leaking coroutines, default arguments, or `Unit`-returning SAMs |
| Existing Java service, small team | Stay on Java, upgrade to 21+ | Rewriting to Kotlin for its own sake |
| Shared Kotlin/Android/iOS product logic | Kotlin Multiplatform | Forcing KMP where platform-native code is small |
| New code in a mixed repo | Kotlin modules with JSpecify-annotated Java boundaries | Mixed mutability/null conventions without enforcement |

### Web and API stack

| Workload | Choose | Notes |
| --- | --- | --- |
| CRUD, blocking JDBC/JPA, typical service | Spring MVC on virtual threads | Simplest correct model; virtual threads handle concurrency (`./references/03-spring-boot.md`) |
| High-fanout streaming I/O, non-blocking drivers, backpressure | WebFlux | Requires an end-to-end reactive stack; never mix blocking JDBC on event loops |
| Internal synchronous RPC | MVC or gRPC; `RestClient` for calls | Prefer HTTP interfaces (`@HttpExchange`) over hand-rolled clients |
| Startup-sensitive (serverless, CLI, scale-to-zero) | Spring AOT or GraalVM native image | Budget for reflection/resource hints and integration test cost (`./references/10-migration-modernization.md`) |
| Simple, few dependencies, cold-path batch | Plain Java/Kotlin, no framework | Frameworks cost startup and memory |

### Persistence

| Situation | Choose | Notes |
| --- | --- | --- |
| Rich domain model, CRUD plus relationships | JPA/Hibernate | Watch N+1 and lazy loading (`./references/04-persistence.md`) |
| Reporting, analytics, dynamic filters, SQL-first | jOOQ | Type-safe SQL without JPQL contortions |
| Append-only/event/streaming writes | Plain JDBC or jOOQ | ORM dirty checking adds nothing |
| Multi-DB enterprise deployments | Liquibase | XML/YAML changelogs and rollback support |
| SQL-first, single-DB, DBA-reviewed migrations | Flyway | Immutable versioned SQL scripts |

### Runtime and GC

| Situation | Choose | Notes |
| --- | --- | --- |
| Latency SLOs, large heaps (tens of GB) | Generational ZGC | Allocation rate is the real tuning lever (`./references/05-jvm-performance.md`) |
| Balanced default web service | G1 (default) | Tune only with JFR evidence |
| Batch/throughput, pause-insensitive | Parallel GC | Highest throughput, long pauses |
| CPU-bound work | Platform threads sized to cores | Virtual threads add overhead without benefit |
| Blocking I/O fan-out (JDBC, HTTP) | Virtual threads | Eliminates thread-pool tuning; keep DB pools sized to the database |

## Reference index

| File | Scope | Load when |
| --- | --- | --- |
| [`references/01-java-core.md`](references/01-java-core.md) | Java 21-25: records, sealed types, pattern matching, virtual threads, structured concurrency, scoped values, sequenced collections, deprecations and removals | Writing or reviewing modern Java; deciding on preview features; planning Java upgrades |
| [`references/02-kotlin-core.md`](references/02-kotlin-core.md) | Kotlin 2.x/K2: null safety, data/sealed classes, extensions, scope functions, coroutines, Flow, channels, multiplatform | Writing Kotlin; designing coroutine-based async; mixed Java/Kotlin codebases |
| [`references/03-spring-boot.md`](references/03-spring-boot.md) | Spring Boot 3.5+/4.x: DI, configuration, MVC vs WebFlux, validation, error handling, security, actuators, AOT/native | Building or reviewing Spring services; choosing web stack or upgrading Boot |
| [`references/04-persistence.md`](references/04-persistence.md) | JPA/Hibernate, jOOQ, transactions, N+1 and fetch strategies, Flyway/Liquibase, pooling, caching | Modeling data access; fixing lazy-loading or transaction bugs; choosing an ORM vs SQL layer |
| [`references/05-jvm-performance.md`](references/05-jvm-performance.md) | JIT, GC selection (G1, generational ZGC, Shenandoah), JFR, heap sizing, thread vs virtual-thread scaling, profiling | Tuning production JVM; diagnosing latency, memory, or CPU incidents |
| [`references/06-build-tooling.md`](references/06-build-tooling.md) | Gradle Kotlin DSL, version catalogs, toolchains, Maven comparison, multi-module builds, locking, CI | Setting up or repairing builds; migrating Maven builds; speeding up CI |
| [`references/07-testing.md`](references/07-testing.md) | JUnit 5, Kotest, MockK/Mockito, Testcontainers, ArchUnit, PIT mutation testing, CI test strategy | Writing tests; making CI reliable; adding contract, architecture, or mutation coverage |
| [`references/08-android.md`](references/08-android.md) | Jetpack Compose, lifecycle/ViewModel, Room, coroutines, performance, testing, release | Building Android apps; reviewing Compose or Room code; preparing Play releases |
| [`references/09-observability-security.md`](references/09-observability-security.md) | Micrometer, OpenTelemetry, structured logging, authn/authz patterns, secrets, supply chain, hardening | Adding observability; implementing auth; preparing security or supply-chain review |
| [`references/10-migration-modernization.md`](references/10-migration-modernization.md) | Java 8/11/17 to 21+, Kotlin migration, Spring Boot upgrades, GraalVM native, strangler patterns | Planning upgrades; modernizing legacy JVM systems; choosing native images |

## How to use this pack

1. Read this file, then load only the references the task needs.
2. Follow cross-links inside references for adjacent topics; every link is relative and local to this pack.
3. Treat version ranges as floors and ranges, not pins. Confirm the current releases and support windows upstream before locking a version line.
4. Prefer the checklists at the end of each reference as review gates.

## Port

- **Port id** — `skill://senior/java-kotlin` (version in `metadata.port-version`).
- **Kind** — read-only reference pack; no side effects, no tools required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "java-kotlin" })` in OpenCode; Claude Code reads `<skills-dir>/java-kotlin/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers reference it as `load skill senior-java-kotlin (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major.
