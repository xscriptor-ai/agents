# Build Tooling (Gradle, Maven, CI)

Scope: reliable, reproducible JVM builds: Gradle Kotlin DSL, version catalogs, toolchains, multi-module structure, dependency locking, and CI.

## Gradle baseline

| Item | Guidance |
| --- | --- |
| Version | Gradle 8.x/9.x; keep within the current supported line; verify upstream |
| DSL | Kotlin DSL (`build.gradle.kts`) is the default; Groovy DSL is legacy |
| Daemon JVM | Gradle 9 requires a JVM 17+ to run the daemon; build JVMs are separate |
| Wrapper | Always commit `gradlew`, `gradlew.bat`, `gradle/wrapper/*`; never rely on a system Gradle |
| Configuration cache | Enable and keep compatible; it is the largest CI speedup |
| Build cache | Local plus remote (CI) cache with stable keys |
| Repositories | `mavenCentral()` as primary; use repository content filtering and dependency verification |

```kotlin
plugins {
    java
    id("org.springframework.boot") version "x.y.z"
    id("io.spring.dependency-management") version "x.y.z"
}

java {
    toolchain { languageVersion = JavaLanguageVersion.of(21) }
}

tasks.test {
    useJUnitPlatform()
    maxParallelForks = (Runtime.getRuntime().availableProcessors() / 2).coerceAtLeast(1)
}

tasks.withType<JavaCompile>().configureEach {
    options.release = 21
    options.compilerArgs.addAll(listOf("-Xlint:all", "-Werror"))
}
```

Rules:

- Use `plugins { }` with explicit versions (or version catalog aliases); no `apply plugin:` or `buildscript` classpath unless unavoidable.
- Enable configuration cache (`org.gradle.configuration-cache=true`) and build cache; treat cache misses/incompatibilities as bugs.
- Avoid `doFirst`/`doLast` with mutable project state; use typed tasks and lazy APIs (`tasks.register`, `providers`, `layout`).
- Never resolve configurations at configuration time (`configurations.runtimeClasspath.get()` in task graph); let tasks do the work.
- Pin wrapper checksum (`distributionSha256Sum`) and verify it in CI.
- Keep build scripts small: shared logic goes into convention plugins, not copy-paste.

Anti-patterns:

- `clean` as a standard build step; it hides incremental build bugs and slows CI.
- `--no-daemon` everywhere (fine for one-shot containers, slow for developer machines).
- `allprojects { }`/`subprojects { }` blocks in modern builds; they break project isolation and configuration cache.
- Dynamic versions (`1.+`, `latest.release`) and changing modules (`-SNAPSHOT`) in release builds.

## Version catalogs

`gradle/libs.versions.toml`:

```toml
[versions]
kotlin = "2.x"
springBoot = "3.5.x"
junit = "5.x"

[libraries]
kotlin-stdlib = { module = "org.jetbrains.kotlin:kotlin-stdlib", version.ref = "kotlin" }
junit-jupiter = { module = "org.junit.jupiter:junit-jupiter", version.ref = "junit" }
assertj = { module = "org.assertj:assertj-core", version = "3.x" }

[bundles]
testing = ["junit-jupiter", "assertj"]

[plugins]
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
spring-boot = { id = "org.springframework.boot", version.ref = "springBoot" }
```

Rules:

- One catalog per repository, committed; no per-module version drift.
- Reference by alias (`libs.junit.jupiter`); never hardcode a version in a module script when the catalog has it.
- Use `bundles` for cohesive test/runtime sets, not for arbitrary grouping.
- Catalogs are for versions and coordinates, not logic. Logic belongs in convention plugins.
- Publish an internal platform/BOM for multi-repo organizations; catalogs do not cross repositories by themselves.
- Keep `[versions]` names meaningful (`springBoot`, not `v1`).

Anti-patterns:

- Mixed catalogs and literal versions in the same build.
- Catalog entries that duplicate a BOM already managed by the platform (`implementation(platform(...))` plus versions on managed artifacts).
- Using the catalog to pin transitive internals via forced versions.

## Toolchains and language levels

- Toolchains decouple the Gradle daemon JVM from the compiler JVM: `java.toolchain.languageVersion` and `kotlin { jvmToolchain(21) }`.
- Auto-provisioning via the Foojay resolver plugin; in air-gapped CI, provision JDKs in the image and configure `org.gradle.java.installations.paths`.
- For libraries, set `options.release` (Java) to the minimum supported version; Kotlin `jvmTarget` should match (e.g., target 17 bytecode while building on 21).
- Kotlin/Java mixed modules: align `jvmTarget` and Java `release`, enable `-Xjdk-release` for Kotlin when targeting older JDKs.
- Test on multiple toolchains in CI (current LTS and next feature release) without changing the primary build.
- Never compile with a JDK below the language level of the source; the compiler will refuse or emit subtly different code.

## Maven comparison

| Criterion | Gradle | Maven |
| --- | --- | --- |
| Model | Programmatic (Kotlin DSL), flexible | Declarative POM, convention-driven |
| Incremental builds | Strong (up-to-date checks, build cache) | Limited; whole-module rebuilds |
| Multi-module | Flexible, project isolation possible | Simple, predictable reactor |
| Performance | Better for large incremental builds | Slower; `mvnd` helps |
| Ecosystem | Gradle-first for Android/Kotlin, growing for JVM | Dominant in enterprise Java, strong tooling/IDE parity |
| Learning curve | Higher; scripts are code | Lower; XML boilerplate |
| Version | Gradle 8.x/9.x | Maven 3.9+; Maven 4.x line maturing (verify upstream) |

Guidance:

- Choose one per repository; mixed Gradle/Maven builds add maintenance without benefit.
- Stay on Gradle if the repo is Kotlin/Android or needs custom logic; stay on Maven for conservative enterprise stacks where standards and stability dominate.
- Migrate only with a reason (build time, Kotlin support, custom logic); a working Maven build is not a problem to fix.
- Keep the wrapper (`mvnw`) committed and use `-B` (batch) and `-ntp` (no transfer progress) in CI.

## Multi-module builds

```
settings.gradle.kts
gradle/libs.versions.toml
build-logic/            # convention plugins (included build)
  src/main/kotlin/
app/
  build.gradle.kts
core-domain/
core-data/
adapters/web/
```

Rules:

- Prefer `build-logic` included build over `buildSrc` for convention plugins: faster, cacheable, testable.
- `settings.gradle.kts` declares `rootProject.name` and `include(...)`; keep a flat, explicit module list.
- Dependencies: `api` only when a type is exposed in public signatures; otherwise `implementation` to avoid leaky classpaths.
- No cyclic project dependencies. Extract shared abstractions downward, not sideways.
- Use BOM platforms (`platform("org.springframework.boot:spring-boot-dependencies:x.y.z")`) for aligned versions.
- Module boundaries mirror the architecture (`./01-java-core.md` for language-level structure); do not create modules for their own sake.
- Keep configuration cache and project isolation compatibility: no cross-project `project(":x")` access at configuration time.
- Version the whole repo together (monorepo) unless modules have genuinely independent release cadences.

Anti-patterns:

- God `build.gradle.kts` (hundreds of lines) duplicated across modules.
- `implementation project(":everything")` creating a de facto monolith.
- Modules that only exist to hold two classes.
- `buildSrc` used for application logic instead of build configuration.

## Dependency management and locking

- One version per dependency line across modules; resolve conflicts deliberately with constraints/platforms, not `force`.
- Investigate conflicts with `./gradlew dependencyInsight --dependency <group:artifact> --configuration runtimeClasspath`.
- Reproducible builds: enable dependency locking (`./gradlew dependencies --write-locks`), commit lockfiles, and use `--update-locks` only in reviewed changes.
- Enable dependency verification (`gradle/verification-metadata.xml`) with checksums/signatures for all resolved artifacts.
- Reject dynamic and changing versions in release configurations.
- Document the policy for transitive vulnerabilities: update cadence, exception process, and owner (`./09-observability-security.md`).
- For Maven, the dependency management section plus `flatten` for consumer POMs; Maven 4 separates build and consumer POMs (verify upstream).
- Publish SBOMs from the build (CycloneDX plugin) so consumers can scan without rebuilding.

Anti-patterns:

- `force` in resolution strategy without resolving upstream causes.
- Ignoring `dependencyUpdates` reports until they become upgrades under incident pressure.
- Locking only the app, not tests/tools, so CI still resolves floating versions.

## CI pipeline

```yaml
# Pseudocode shape, not tool-specific
steps:
  - restore caches (Gradle caches keyed by wrapper + lock hashes)
  - ./gradlew --build-cache check
  - ./gradlew test --tests ... on shards
  - ./gradlew pitest  (nightly, not per-commit)
  - ./gradlew dependencies --write-locks  (only in an explicit update job)
  - publish SBOM + artifacts (signed, from tagged commits)
```

Rules:

- Cache keys include the wrapper checksum, version catalogs, and lockfiles; never cache secrets.
- Use configuration cache and build cache; a warm remote cache should make unchanged modules near-instant.
- Split fast (unit/lint/ArchUnit) from slow (integration/Testcontainers/mutation) jobs; fail fast on the fast suite.
- Run test sharding/parallel forks to cut wall time; keep resource limits aligned with container CPU/memory.
- Matrix the JDK versions you support for compile/test, even if you publish from one.
- Publish only from tags; artifacts must be reproducible and signed; fail on snapshot/dynamic dependencies.
- Keep Gradle/Maven plugin versions pinned; build plugins are production code.
- Nightly jobs: mutation testing, dependency updates PRs, JDK-ea compatibility probes.

Anti-patterns:

- A single monolithic CI job that takes an hour; nobody iterates on it.
- Caching `build/` outputs without correct inputs; produces stale artifacts.
- Publishing from a developer machine or an unversioned branch.
- Treating CI configuration as untouchable; build times are a feature.

## Review checklist

- [ ] Wrapper committed, checksum pinned, single Gradle/Maven version across the repo.
- [ ] Kotlin DSL with typed tasks; configuration cache and build cache enabled.
- [ ] Version catalog is the single source of dependency versions; no dynamic versions.
- [ ] Toolchains declared; release bytecode level explicit and tested.
- [ ] Multi-module layout has no cycles; `api` vs `implementation` deliberate.
- [ ] Dependency locking and verification enabled for release builds.
- [ ] CI splits fast and slow suites, caches correctly, and publishes signed, reproducible artifacts.
- [ ] Build logic tested (convention plugins) and reviewed like application code.
