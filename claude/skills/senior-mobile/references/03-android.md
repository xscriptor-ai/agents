# Android

Kotlin 2, Jetpack Compose, lifecycle and ViewModel, persistence, networking, performance, and
testing for Android apps built on current AGP and SDK levels.

## Version Floor and Toolchain

Build with the current stable Android Gradle Plugin, Kotlin 2.x with the K2 compiler, and the
Compose BOM rather than pinned artifact versions. `minSdk` should cover the product's real device
floor; `targetSdk` must meet the Play target API requirement (it advances yearly — verify the
current deadline upstream). Compose is the default UI toolkit; the View system remains for legacy
code and some widgets/accessibility edge cases.

## Kotlin 2 and Language Practice

- K2 compiler: faster builds and real compiler plugins (Compose compiler ships with Kotlin now).
- Coroutines + `Flow` for async: `viewModelScope`, `StateFlow` for UI state, `SharedFlow` for
  events; never expose `MutableStateFlow`.
- Sealed interfaces/enums model UI state, results, and navigation events.
- `@Immutable`/`@Stable` annotations and immutable data classes let Compose skip recomposition.
- Avoid platform types leaking from Java; annotate or wrap third-party APIs.

```kotlin
sealed interface UiState {
    data object Loading : UiState
    data class Ready(val items: List<Item>) : UiState
    data class Failed(val message: String) : UiState
}
```

## Jetpack Compose Architecture

### State and recomposition

- State hoisting: composables take values and emit events; state lives in the ViewModel or a
  state holder, not deep in the tree.
- Prefer `rememberSaveable` for state that must survive process death (form input, selection).
- Derived values: `derivedStateOf` for expensive computations from frequently changing state;
  `remember(key)` to memoize.
- Avoid reading state in composition that only affects layout/draw; use lambdas and
  `Modifier.drawWithContent`/`graphicsLayer` for animation-driven changes.
- Keys in `LazyColumn` must be stable and unique; never index-only for reorderable data.

```kotlin
@Composable
fun FeedScreen(vm: FeedViewModel, onItemClick: (String) -> Unit) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    when (val s = state) {
        is UiState.Loading -> LoadingRow()
        is UiState.Failed -> ErrorRow(s.message, onRetry = vm::refresh)
        is UiState.Ready -> LazyColumn {
            items(s.items, key = { it.id }) { item ->
                FeedRow(item, onClick = { onItemClick(item.id) })
            }
        }
    }
}
```

### Side effects

| Effect | Use for |
|---|---|
| `LaunchedEffect(key)` | Suspend work tied to a key (load, observe) |
| `rememberCoroutineScope` | User-triggered launches from callbacks |
| `DisposableEffect` | Register/unregister listeners, lifecycle observers |
| `produceState` | Convert non-Compose sources into state |
| `snapshotFlow` | Turn Compose state into a flow for business logic |

Never launch coroutines directly inside a composable body; use the effects above.

### Lifecycle and ViewModel

- `ViewModel` holds screen state and survives configuration changes; it does not hold Activity,
  View, or Context references (use `AndroidViewModel` only when a context is truly required).
- Collect UI state with `collectAsStateWithLifecycle` so collection stops when the view is stopped.
- Model events as one-shot effects (channels/shared flows) rather than consumable state booleans.
- `SavedStateHandle` for minimal state needed after process death; large data is refetched.
- Predictive back: opt in, handle back with `BackHandler` where behavior differs, and support
  gesture previews; never block back navigation without a strong reason.

### Navigation

- Navigation Compose with type-safe, serializable routes (Kotlin serialization) rather than string
  URLs.
- One nav graph per feature plus an app graph; pass IDs, not whole models, between destinations.
- Deep links declared in the graph; validate arguments and fall back safely.
- Do not put navigation logic in composables; emit destination events from the ViewModel.

### Dependency Injection

- Hilt for most apps (compile-time safety, Android lifecycle integration); Koin or manual
  constructor injection for small apps.
- Scope correctly: `@Singleton` for app services, ViewModel-scoped for screen state; avoid holding
  app context in long-lived objects.
- Inject dispatchers (`@IoDispatcher`, `@DefaultDispatcher`) so tests can substitute test
  dispatchers.

### Persistence

| Need | Choice |
|---|---|
| Relational app data | Room (KSP, flows from DAO; supports KMP targets now) |
| Small preferences/flags | DataStore (Preferences or Proto) |
| Tokens/credentials | Keystore-wrapped encryption + DataStore; never plain prefs |
| Files/media | App storage with scoped storage APIs; `MediaStore` for shared media |
| Cross-platform local DB | SQLDelight or Room KMP |

Room rules: DAOs return `Flow` for observed queries; transactions for multi-table writes; schema
export on so migrations are checked into version control and tested; `fallbackToDestructiveMigration`
never ships.

### Networking

- Retrofit + OkHttp (or Ktor client for KMP) with kotlinx.serialization or Moshi.
- One OkHttp client per app; interceptors for auth, headers, logging (debug only), and retry.
- Token refresh must be single-flight to avoid parallel refresh storms; exclude auth endpoints from
  the authenticator to prevent loops.
- Timeouts are explicit; connect/read/write defaults are inappropriate for slow networks.
- Map transport errors to domain errors at the data layer; UI never sees `IOException` directly.

### Performance

- **Startup**: minimize `Application.onCreate`, lazy-init libraries, avoid disk/network there;
  use App Startup for ordered initialization, baseline profiles and Macrobenchmark to measure.
- **Jank**: Compose recomposition scope is the unit of cost; make state reads as local as possible,
  stabilize parameters, and use `LazyColumn` with stable keys and content types.
- **Images**: Coil with proper sizing and crossfade off for lists; request the display size, not
  the source size.
- **Background work**: WorkManager with constraints and unique work names; expedited work only for
  user-visible tasks; respect Doze and battery restrictions.
- **Size**: R8 with resource shrinking, per-ABI splits or App Bundles, remove unused locales/density
  assets; measure with the APK Analyzer.
- **Memory**: avoid Activity leaks via static references; use LeakCanary in debug; watch bitmap
  cache sizes; handle `onTrimMemory`.
- Enable R8 full mode and verify keep rules for reflection/serialization; obfuscation mapping must
  be uploaded for readable crash reports.

### Testing

| Level | Tooling |
|---|---|
| Unit | JUnit 5 or 4, kotlin.test, Turbine for flows, coroutines-test |
| Compose UI | `createComposeRule`, semantics assertions, `waitUntil`/idling resources |
| Integration | Room in-memory, MockWebServer for API, Hilt test runner |
| Screenshot | Roborazzi/Paparazzi for deterministic screenshots in JVM tests |
| End-to-end | Instrumented tests on device/emulator in CI (limited matrix) |

Rules: test ViewModels without Android framework classes; fake repositories with flows; run
instrumented tests on at least one API level; keep E2E suites small and stable.

### Anti-Patterns

- Passing `Context` into ViewModels or long-lived objects.
- `collectAsState()` without lifecycle awareness in screens.
- Launching coroutines in composable bodies or `init` blocks that outlive the screen.
- Giant ViewModels that own networking, caching, formatting, and navigation.
- `GlobalScope` for anything.
- One mutable state object mutated from multiple places without a single reducer.
- Ignoring process death; state that vanishes on low-memory kill.
- `fallbackToDestructiveMigration` in production.
- Using the View system for new feature UI when Compose is already the stack.

### Checklist

- [ ] Immutable UI state, single state owner, events modeled explicitly.
- [ ] No coroutine launched from composition without an effect.
- [ ] Room schema versioned, exported, and migration-tested.
- [ ] Network layer: single client, typed errors, single-flight refresh.
- [ ] Baseline profile generated and Macrobenchmark startup/jank tracked in CI.
- [ ] WorkManager jobs constrained, unique, and observable.
- [ ] Accessibility: content descriptions, touch targets, TalkBack pass on core flows.
- [ ] Release build with R8 verified; mapping file uploaded to crash reporting.
- [ ] Handles process death for critical screens.

## Cross-Links

- Stack choice: [./01-cross-platform-decision.md](./01-cross-platform-decision.md)
- iOS counterpart: [./02-ios.md](./02-ios.md)
- Offline and sync: [./06-data-offline-sync.md](./06-data-offline-sync.md)
- Performance method: [./07-performance.md](./07-performance.md)
- Security requirements: [./08-security.md](./08-security.md)
- Shipping: [./09-release-store-ci.md](./09-release-store-ci.md)
