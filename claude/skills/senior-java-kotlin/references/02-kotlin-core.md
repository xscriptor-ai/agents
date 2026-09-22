# Kotlin Core (2.x, K2)

Scope: idiomatic Kotlin 2.x on the JVM: null safety, data/sealed classes, extensions, scope functions, coroutines, Flow, channels, and multiplatform orientation.

## Compiler baseline

| Item | Status |
| --- | --- |
| K2 frontend | Default since Kotlin 2.0; single compiler for all targets |
| Language version | Pin per module (`languageVersion`, `apiVersion`); avoid straddling majors in one build |
| Toolchain | `jvmToolchain(21)` or newer; Kotlin can emit older bytecode targets via `jvmTarget` |
| Explicit API mode | Enable for libraries (`explicitApi()`) so public declarations have explicit visibility and types |
| Warnings | Treat as errors in CI (`allWarningsAsErrors`) after a burn-down |
| KSP | Preferred over kapt for annotation processing (Room, Hilt, Dagger); kapt is legacy and slow |
| Preview features | Opt in per module and document; do not enable globally |

Compatibility rules:

- Kotlin metadata is forward-only: older compilers cannot read classes produced by newer ones. Keep the compiler version at or above the highest library metadata version.
- Java interop should assume JSpecify-annotated Java boundaries (`@NullMarked`) to avoid platform types (see `./01-java-core.md` and `./10-migration-modernization.md`).
- Keep `kotlin-stdlib` aligned with the compiler; mixing remote compiler versions across modules is a common source of cryptic errors.

## Null safety

Null safety is the primary reason to choose Kotlin. Use it fully.

```kotlin
data class User(val id: Long, val email: String, val phone: String?)

fun normalize(user: User): String =
    user.phone?.trim()?.takeIf { it.isNotEmpty() } ?: "unknown"

fun requireEmail(user: User) {
    val email = requireNotNull(user.email.takeIf { it.contains('@') }) {
        "invalid email for user ${user.id}"
    }
    send(email)
}
```

Idioms and rules:

- `?.`, `?:`, `takeIf`, `takeUnless`, `let` are the daily tools. Prefer `?: error(...)`/`requireNotNull` over `!!`.
- `!!` is acceptable only where a precondition was already enforced and the invariant is locally obvious; every `!!` is a review flag.
- Platform types from Java (`String!`) have unknown nullability. Eliminate them at the boundary: annotate Java APIs with `@NullMarked`/`@Nullable`, or wrap in `Objects.requireNonNull`.
- `lateinit` is for framework-injected mutable fields only; not for constructor-optional state. `Delegates.notNull()` is for primitives.
- Prefer sealed results or `Result` over nullable plus exceptions for business outcomes; use exceptions for programming errors.
- Smart casts work after `is` checks and null checks, but fail across mutable `var` captured in closures or custom getters; use local `val` copies.
- Collection nullability: `List<String?>` versus `List<String>?` are different; be deliberate in APIs.
- `firstOrNull`, `singleOrNull`, `associateByNotNull` avoid nullable-losing conversions; measure `first { }` usage in hot paths (throws).

Anti-patterns:

- `!!` sprinkled to silence the compiler; it converts compile-time safety into runtime crashes.
- Using `lateinit` to avoid constructor parameters in tests; inject dependencies instead.
- Returning `null` where an empty collection or a sealed `NotFound` is clearer.
- Trusting platform types in public API signatures.

## Data and sealed classes

```kotlin
sealed interface UiState {
    data object Loading : UiState
    data class Ready(val items: List<Item>) : UiState
    data class Failed(val cause: Throwable) : UiState
}

data class OrderLine(val sku: String, val qty: Int, val unitPrice: Money) {
    init { require(qty > 0) { "qty must be positive" } }
    val total: Money get() = unitPrice * qty
}
```

Rules:

- `data class` gives `equals/hashCode/copy/toString/componentN`. Properties declared outside the primary constructor are excluded from `equals`; do not rely on them for identity.
- Never put mutable arrays or mutable collections in a data class without defensive copies; `equals` will surprise you.
- `data object` (stable since 1.9) for singletons with value equality; do not use `object` with manual `equals`.
- Sealed interfaces are preferred over sealed classes for hierarchies that need multiple inheritance shapes.
- Exhaustive `when` over a sealed hierarchy replaces `else`; adding a variant should break compilation at every decision point.
- Value classes (`@JvmInline value class UserId(val raw: Long)`) prevent primitive mixups with zero allocation in most paths; note boxing when used generically or as nullable.
- Nested sealed hierarchies keep domain states local to their feature module.

Anti-patterns:

- Sealed classes with a catch-all `else` branch; you lose exhaustiveness.
- Data classes for JPA/Hibernate entities: generated `equals/hashCode` and mutability fight the persistence model (see `./04-persistence.md`).
- Copying large data classes in hot loops; `copy` is shallow but still allocates and re-validates `init` blocks.

## Extension functions and properties

```kotlin
fun String.maskEmail(): String {
    val at = indexOf('@')
    return if (at <= 1) "***" else "${first()}***${substring(at)}"
}

val Instant.isWeekend: Boolean
    get() = dayOfWeek in setOf(DayOfWeek.SATURDAY, DayOfWeek.SUNDAY)
```

Rules:

- Extensions are static dispatch: they are resolved at compile time by the receiver's declared type, not overridden at runtime. Do not use them to fake polymorphism.
- Keep extensions close to the type they enrich or in a feature module; wildcard import of a general extensions package hurts discoverability.
- For libraries, use `@JvmName` to control the generated static name and avoid clashes; `@JvmStatic` on companion functions for Java ergonomics.
- `inline` + `reified` enables type checks and avoids lambda allocation, but inlined public functions become part of the ABI; recompilation of consumers is required on change.
- Extensions cannot access private members; if you need internals, the function belongs in the type.
- Avoid extension functions on `Any`, `Unit`, or overly generic receivers; they pollute all call sites.

Anti-patterns:

- `fun <T> T.toX()` chains that read like DSL but hide control flow.
- Extension properties with side effects; properties imply cheap, side-effect-free access.
- Building a parallel "utility" library of extensions that shadows standard library semantics (`String.add`, `List.concat`).

## Scope functions

| Function | Receiver | Returns | Typical use |
| --- | --- | --- | --- |
| `let` | `it` | lambda result | Null checks, mapping a value, local scoping of a name |
| `run` | `this` | lambda result | Compute a value from an object; block with last expression |
| `with` | `this` (arg) | lambda result | Multiple members of a non-null object without repetition |
| `apply` | `this` | receiver | Configure an object during construction/builder |
| `also` | `it` | receiver | Side effects (logging, validation) in a chain |

Rules:

- One scope function per chain, at most; nested `let/run/apply` pyramids are a readability failure.
- Do not use `also` for mutation that changes meaning; side effects should be obvious.
- `run` on a nullable receiver (`user?.run { ... }`) is idiomatic for "if present, do several things".
- `with` for reads, `apply` for writes.

Anti-patterns:

- `x?.let { ... } ?: throw ...` where `requireNotNull` reads better.
- Using `apply` on objects that have no builder semantics; it hides the real construction logic.
- Mixing `it` and `this` lambdas in the same expression.

## Coroutines

Structured concurrency is the core rule: every coroutine has a parent scope, and a scope does not complete until its children do.

```kotlin
class UserService(
    private val users: UserClient,
    private val orders: OrderClient,
    private val scope: CoroutineScope,
) {
    suspend fun profile(id: Long): Profile = coroutineScope {
        val user = async { users.get(id) }
        val orders = async { orders.forUser(id) }
        Profile(user.await(), orders.await())
    }

    fun refreshInBackground(id: Long) {
        scope.launch { runCatching { profile(id) }.onFailure(log::warn) }
    }
}
```

Rules:

- `suspend` functions must be main-safe: switch to `Dispatchers.IO` (or a dedicated dispatcher) around blocking work; never block the caller's dispatcher.
- `runBlocking` is only for `main()` and tests; never inside a coroutine or a server request handler.
- Use `coroutineScope { }` for fan-out that must fail as a unit; `supervisorScope { }` when sibling failures must not cancel each other.
- Install an exception strategy at the boundary: `CoroutineExceptionHandler` on root launches, or catch inside `launch` (an uncaught exception in a child cancels the parent).
- `CancellationException` must always be rethrown; catching it generically breaks structured cancellation and timeouts.
- Timeouts: wrap with `withTimeout`/`withTimeoutOrNull`; prefer deadline propagation over nested ad-hoc timeouts.
- Dispatchers are not for thread affinity; do not assume `Dispatchers.Default` runs on a specific thread (use `newSingleThreadContext` only when truly needed, and close it).
- `Dispatchers.IO` has a bounded parallelism (tens of threads by default); for large blocking fan-outs prefer a virtual-thread dispatcher via `Executors.newVirtualThreadPerTaskExecutor().asCoroutineDispatcher()` (see `./01-java-core.md`, `./05-jvm-performance.md`).
- Coroutine context elements propagate; avoid storing mutable state in contexts. Use `ThreadLocal` only around blocking library calls that require it.
- Cancellation is cooperative: tight CPU loops must check `ensureActive()`/`isActive`; blocking calls must be interruptible.

Testing coroutines:

- `runTest` with `StandardTestDispatcher`/`TestScope` virtual time; never `runBlocking` in tests.
- Inject dispatchers; never hardcode `Dispatchers.IO` in classes under test.
- Use Turbine for Flow assertions (see `./07-testing.md`).

Anti-patterns:

- `GlobalScope.launch` anywhere: unstructured, untracked work.
- `async` on the same dispatcher as an immediate `await`, gaining no concurrency.
- Catching `Throwable` and swallowing `CancellationException`.
- Blocking inside `Dispatchers.Default` (the CPU pool starves).

## Flow

Cold flows are lazy streams; hot flows (`StateFlow`, `SharedFlow`) are shared state/events.

```kotlin
fun search(query: Flow<String>): Flow<List<Result>> =
    query
        .debounce(250)
        .distinctUntilChanged()
        .flatMapLatest { q -> flow { emit(api.search(q)) } }
        .catch { e -> emit(emptyList()) }
        .flowOn(Dispatchers.IO)

val state: StateFlow<UiState> = searchFlow
    .map<_, UiState> { UiState.Ready(it) }
    .stateIn(scope, SharingStarted.WhileSubscribed(5_000), UiState.Loading)
```

Rules:

- Build cold flows with `flow { }` and `channelFlow { }` for concurrent emission; keep them side-effect free until collected.
- `flowOn` changes the upstream context; operators before it run on the new dispatcher. Do not use `flowOn` on `SharedFlow`/`StateFlow`.
- Context preservation: you cannot emit from a different context inside `flow { }`; use `channelFlow`/`flowOn`/`withContext` correctly.
- `flatMapLatest` cancels superseded work, ideal for search/autocomplete. `flatMapMerge` for fan-out, `flatMapConcat` for ordering.
- Hot sharing: `stateIn` for UI state, `shareIn` for shared side-effect streams. Understand `SharingStarted.Eagerly`/`Lazily`/`WhileSubscribed` lifetime semantics.
- `StateFlow` conflates and always has a value; it is not an event bus. For one-shot events use `Channel` with `receiveAsFlow` or an explicit event queue.
- Backpressure: `buffer`, `conflate`, `collectLatest` are different tools; `conflate` drops intermediate values, `collectLatest` cancels slow collectors.
- Exceptions in flows terminate collection; place `catch` before terminal operators and consider `retryWhen` for transient upstream failures.
- Never collect a cold flow multiple times expecting shared work; convert with `shareIn`/`stateIn`.

Anti-patterns:

- `MutableStateFlow` exposed publicly; expose `StateFlow` and keep mutation private.
- Using Flow for request/response when a simple `suspend` function suffices.
- `collect` inside `launch` on a UI scope without lifecycle awareness (see `./08-android.md`).

## Channels

Channels are hot, buffered hand-off primitives for 1:1 or many-producer/consumer communication.

```kotlin
fun produceEvents(scope: CoroutineScope): ReceiveChannel<Event> =
    scope.produce(capacity = 64) {
        while (isActive) send(nextEvent())
    }
```

Rules:

- Prefer Flow unless you need multiple consumers of the same stream or explicit capacity semantics.
- Capacities: `RENDEZVOUS` (default), `BUFFERED`, `CONFLATED`, `UNLIMITED`, or a fixed size. `UNLIMITED` is a memory leak waiting for a busy producer.
- `Channel` is single-consumer by default; `fan-out` distributes elements across consumers. Use `BroadcastChannel`-style sharing via `shareIn` for multiple collectors.
- Close channels in `finally`; iterate with `for (e in channel)` so closure ends the loop.
- `select`/`onReceive` for multiplexing; `produce` for producer-side structured lifetime.

Anti-patterns:

- Using a channel as an unbounded queue between subsystems; use a real broker or bounded Flow with backpressure.
- Leaking producer coroutines by not tying them to a scope.
- Sending from multiple threads without a capacity that matches the consumer rate.

## Multiplatform overview

Kotlin Multiplatform (KMP) shares Kotlin business logic across JVM/Android/iOS/JS/Wasm/native targets.

| Concern | Approach |
| --- | --- |
| Platform differences | `expect`/`actual` declarations, source sets (`commonMain`, `androidMain`, `iosMain`) |
| Networking | Ktor client with per-platform engines |
| Serialization | kotlinx.serialization (compiler plugin); avoid reflection-based JSON in common code |
| Persistence | SQLDelight (common SQL) or Room KMP where supported; platform-specific KV stores via expect/actual |
| UI sharing | Compose Multiplatform for shared UI where the product allows it; keep platform-native where it does not |
| iOS interop | Objective-C/Swift export; suspend functions map to completion handlers, generics and sealed classes have bridging limits (see also `./08-android.md`) |
| Concurrency model | Kotlin/Native memory model is the modern relaxed model; still avoid sharing mutable state without synchronization |
| Build | Gradle multiplatform plugin; pin Kotlin and library versions together; expect longer compile times and bigger CI matrices |

Guidance:

- Share logic with a stable API, not everything. Platform-specific UX code stays native.
- Keep the common API surface small; every shared abstraction is a compatibility promise.
- Test common code with `commonTest` and platform-specific tests for actual implementations.
- Verify library compatibility with your Kotlin version before adopting KMP in a product.

## Interop and annotation quick reference

| Annotation | Effect |
| --- | --- |
| `@JvmStatic` | Companion/object member exposed as static |
| `@JvmField` | Property exposed as a field, no accessors |
| `@JvmOverloads` | Generate overloads for default arguments |
| `@JvmName` | Rename generated JVM member |
| `@Throws` | Declare checked exceptions for Java callers |
| `@JvmInline` | Value class |
| `@OptIn` | Acknowledge experimental API usage |
| `fun interface` | SAM interface usable with lambdas |

Anti-patterns:

- Publishing Kotlin APIs whose Java view is unusable (default arguments, inline classes, sealed classes).
- Relying on Kotlin's `internal` for security; it maps to public with name mangling.
- Using `@JvmOverloads` on Android `View` subclasses without checking constructor inheritance.

## Review checklist

- [ ] No `!!` without a documented nearby invariant.
- [ ] Platform types eliminated at Java boundaries.
- [ ] Coroutines tied to structured scopes; no `GlobalScope`.
- [ ] `CancellationException` always rethrown; timeouts on all external calls.
- [ ] Flows have defined sharing, backpressure, and error handling.
- [ ] Channels bounded and closed, or replaced with Flow.
- [ ] Explicit API mode and `allWarningsAsErrors` on for libraries.
- [ ] KMP only where the sharing payoff is concrete and tested on all targets.
