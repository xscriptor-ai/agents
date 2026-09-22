# Android (Kotlin, Jetpack Compose)

Scope: modern Android development: Compose UI, lifecycle/ViewModel architecture, Room, coroutines, performance, testing, and release engineering.

## Build baseline

| Item | Guidance |
| --- | --- |
| minSdk | 24+ in practice; raise deliberately, tracking device share/data |
| targetSdk | Track the annual Play requirement; new apps and updates must target the then-current API level |
| compileSdk | Latest stable at release time; required for new APIs |
| Kotlin | 2.x with K2; keep Kotlin, AGP, and KSP versions compatible |
| AGP | Current stable line; verify the compatibility matrix upstream |
| Compose | Compose BOM for aligned versions; do not pin individual `androidx.compose.*` versions |
| Version catalog | `gradle/libs.versions.toml` for all versions (`./06-build-tooling.md`) |
| KSP | Preferred for Room/Hilt over kapt |

Rules:

- Do not guess AGP/Kotlin compatibility; run the compiler/AGP matrix check on every upgrade.
- Keep `compileSdk` ahead of `targetSdk`; downgrading is painful.
- Use build types (`debug`, `release`) and product flavors only when they carry real differences; flavor proliferation breaks test matrices.
- `release` builds enable R8, resource shrinking, and a strict lint baseline.
- Keep the app module thin; feature modules separate concerns and improve build times with configuration cache.

## Jetpack Compose

Compose is a declarative UI toolkit: functions describe UI from state; the runtime recomposes when observed state changes.

```kotlin
@Composable
fun UserList(items: List<User>, onSelect: (User) -> Unit) {
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        items(items, key = { it.id }) { user ->
            Text(
                text = user.name,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onSelect(user) }
                    .padding(16.dp),
            )
        }
    }
}
```

Core rules:

- UI is a function of state. No UI mutation, no side effects during composition.
- Hoist state: pass values down, events up. Stateful composables are acceptable only as small wrappers around stateless ones.
- `remember` caches values across recompositions; `remember(key)` invalidates when the key changes. Never store mutable state in plain fields of a composable.
- `derivedStateOf` for expensive computations depending on other state; do not use it for trivial expressions.
- `LaunchedEffect(key)` for launching suspend work tied to the composition; `DisposableEffect` for cleanup; `rememberCoroutineScope` for user-triggered work.
- `rememberUpdatedState` for lambdas captured by long-lived effects.
- Stability: mark data classes `@Immutable`/`@Stable` where appropriate; unstable parameters cause unnecessary recomposition. Enable Compose compiler metrics to find offenders.
- Strong skipping (default in recent Compose compiler versions) reduces the need for manual stability annotations, but measuring still matters for hot screens.
- `LazyColumn`/`LazyRow`: always provide stable `key`s; never nest scrollables in the same direction; prefer `items(list, key = ...)` over `itemsIndexed` without keys.
- Avoid reading state in high-level composables when only a leaf needs it; narrow reads reduce recomposition scope.
- `Modifier` order matters. Layout and draw modifiers apply in order; put size/padding/clickable deliberately.
- Previews: small, stateless, multiple states (loading/error/empty); `@PreviewParameter` for variant data.

Anti-patterns:

- Running network or database calls directly in composables.
- Using `GlobalScope` in UI; use `rememberCoroutineScope` or ViewModel scope (`./02-kotlin-core.md`).
- Deeply nested composable hierarchies with no extraction; split for readability and skippability.
- Passing `NavController` deep into the tree; pass lambdas/events instead.
- Using `@Composable` getters for expensive computed values without `derivedStateOf`.

## Architecture: lifecycle, ViewModel, state

```kotlin
sealed interface UiState {
    data object Loading : UiState
    data class Ready(val users: List<User>) : UiState
    data class Failed(val message: String) : UiState
}

@HiltViewModel
class UserViewModel @Inject constructor(
    private val repo: UserRepository,
) : ViewModel() {
    private val state = MutableStateFlow<UiState>(UiState.Loading)
    val uiState: StateFlow<UiState> = state.asStateFlow()

    init { refresh() }

    fun refresh() {
        viewModelScope.launch {
            state.value = UiState.Loading
            state.value = runCatching { UiState.Ready(repo.users()) }
                .getOrElse { UiState.Failed("Could not load users") }
        }
    }
}

@Composable
fun UserScreen(vm: UserViewModel = hiltViewModel()) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    when (val s = state) {
        UiState.Loading -> LoadingIndicator()
        is UiState.Ready -> UserList(s.users, vm::onUserSelected)
        is UiState.Failed -> ErrorMessage(s.message, onRetry = vm::refresh)
    }
}
```

Rules:

- `collectAsStateWithLifecycle` (lifecycle-aware) over `collectAsState`; collection stops when the UI is not visible.
- ViewModel holds UI state and orchestrates use cases; it must not hold `Context`, `View`, or `Activity`.
- One `StateFlow<UiState>` per screen is a clean default; avoid splintering into many flows.
- One-off events (navigation, snackbar) via `Channel` + `receiveAsFlow`, or an explicit event state consumed by the UI; never `SharedFlow` with replay for one-shot effects.
- Layers: UI → domain (use cases) → data (repositories/sources). Keep Android types out of domain.
- DI with Hilt: `@HiltViewModel`, `@Inject` constructors, modules for external types; scope bindings deliberately (`@Singleton` for repositories, no scoping for stateless things).
- Navigation: typed routes, arguments parsed at the boundary, single source of truth for deep links.
- Configuration changes recreate the UI but not the ViewModel; keep process-death restoration in mind (`SavedStateHandle` for critical state).
- Saveable state: `rememberSaveable` for transient UI state that must survive process death.

Anti-patterns:

- Android framework types in repositories/domain; use cases should be JVM-testable.
- Business logic in composables or Activities.
- Catching exceptions in UI and showing raw messages; map to user-facing strings in the ViewModel.
- Using `LiveData` for new code; `StateFlow` is the modern default.
- Leaking `Context` by storing it in singletons; inject `@ApplicationContext`.

## Room

```kotlin
@Entity(tableName = "users")
data class UserEntity(
    @PrimaryKey val id: Long,
    val name: String,
    val syncedAt: Instant?,
)

@Dao
interface UserDao {
    @Query("SELECT * FROM users ORDER BY name")
    fun observeAll(): Flow<List<UserEntity>>

    @Upsert
    suspend fun upsert(users: List<UserEntity>)

    @Transaction
    @Query("SELECT * FROM users WHERE id = :id")
    suspend fun findWithOrders(id: Long): UserWithOrders?
}
```

Rules:

- Entities mirror database rows; keep domain models separate when shapes diverge.
- KSP (`ksp(libs.androidx.room.compiler)`) not kapt.
- Return `Flow` for observable queries and `suspend` for one-shot operations.
- Migrations: prefer explicit `Migration` objects with `@Database(exportSchema = true)` and checked-in schemas; auto-migrations for simple additive changes only.
- Never use `fallbackToDestructiveMigration()` in release builds.
- `@Transaction` for multi-table writes and for queries that must be consistent across relations.
- Index foreign keys and columns used in `WHERE`/`ORDER BY`; test query plans for hot queries.
- Type converters for `Instant`, enums, and value classes; keep them deterministic and null-safe.
- Test DAOs against an in-memory database, and also run migrations against a real file-backed database in tests.
- Room KMP exists for sharing data layers; verify feature parity before committing (`./02-kotlin-core.md`).

Anti-patterns:

- Doing joins in Kotlin loops instead of SQL; N+1 on device is worse than on server.
- Main-thread database access (Room blocks/throws).
- Storing large blobs in the database; use files and keep paths.
- Ignoring schema export; you lose migration verification in CI.

## Coroutines on Android

- `viewModelScope` and `lifecycleScope` are the structured scopes; they cancel with their owner.
- Main-safety: suspend functions must move blocking work to `Dispatchers.IO` internally; callers stay on `Dispatchers.Main`.
- `repeatOnLifecycle(Lifecycle.State.STARTED)` for collecting flows in Activities/Fragments; Compose uses `collectAsStateWithLifecycle`.
- `Dispatchers.Default` for CPU work; never block it with I/O.
- WorkManager for deferrable, guaranteed work (sync, uploads); coroutine workers support suspend functions and constraints.
- Foreground services are for user-visible ongoing work; background restrictions (Doze, App Standby) apply — do not fight them.
- Cancellation is cooperative; long loops in workers/services must check `isActive`.
- Avoid `runBlocking` on the main thread in app code; use it only in `main()` and in tests.

Anti-patterns:

- Launching unstructured coroutines in `onCreate` with `GlobalScope`.
- Collecting flows without lifecycle awareness (battery drain, crashes after destruction).
- Doing I/O in `Dispatchers.Main.immediate`.
- Using `Thread.sleep` or busy loops in UI-adjacent code.

## Performance

- Baseline profiles: generate with Macrobenchmark and ship in the app to improve startup and jank; refresh per release.
- Macrobenchmark for cold/warm startup, jank, and scroll; Microbenchmark for CPU paths.
- Startup: defer initialization (App Startup library), avoid heavy `Application.onCreate` work, lazy-initialize DI singletons where safe.
- Compose: check recomposition counts with the layout inspector/compiler metrics; fix unstable types and broad state reads.
- R8 full mode in release; keep rules minimal and justified; map files archived for crash deobfuscation.
- Resource shrinking and image formats (WebP/AVIF), vector drawables, per-density assets.
- Lists: paging library for large data sets, stable keys, prefetch distance tuning only with measurement.
- Network: coalesce requests, cache with HTTP semantics (OkHttp cache, ETag), respect data saver.
- Concurrency: keep database and network off the main thread; batch writes with transactions.

Anti-patterns:

- Optimizing without Macrobenchmark numbers; "looks smoother" is not evidence.
- Blocking startup to preload everything.
- Holding wakelocks/frequent wakeups.
- Huge `remember` computations on every recomposition instead of `derivedStateOf`.

## Testing

| Layer | Tooling |
| --- | --- |
| Unit (JVM) | JUnit 5/Kotest, Turbine for flows, fakes for repositories |
| Compose UI | `createAndroidComposeRule`, semantics-based assertions |
| Screenshot | Paparazzi (JVM) or Roborazzi for host-side/screenshot tests |
| Robolectric | Android APIs on the JVM for fast integration-ish tests |
| Instrumentation | `AndroidJUnitRunner`, Espresso for legacy views, Hilt test rules |
| Performance | Macrobenchmark module (non-debuggable release-like variant) |

Rules:

- Keep the majority of tests in the JVM suite; UI tests are for UI behavior and integration wiring.
- Compose tests assert on semantics (`onNodeWithText`, `onNodeWithTag`), not internal state.
- Use test tags for stable selectors; avoid matching on display strings for critical flows.
- Hilt tests replace modules (`@TestInstallIn`, `@UninstallModules`) instead of service locators.
- Turbine for `Flow` emission assertions with virtual time in `runTest`.
- Screenshot tests catch visual regressions; review golden image diffs like code.
- Macrobenchmark requires `profileable`/release-like builds; do not benchmark debug builds.
- No sleeps; use Compose test clock and idling resources.

Anti-patterns:

- Tests that depend on device animations/locale/network.
- Mocking Android framework classes instead of using Robolectric or fakes.
- Only manual QA for release-critical flows; automate at least startup, login, and checkout.

## Release engineering

- Signing: Play App Signing with an upload key; never commit keystores/secrets; rotate and document.
- App Bundle (AAB) for Play; APKs only for side-loaded/enterprise cases.
- R8 mapping files uploaded for deobfuscated crash reports; archive each release's mapping.
- Staged rollouts (1% → 5% → 20% → 100%) with crash/ANR gates from Play vitals or your crash reporter.
- Play Integrity for abuse-sensitive features; treat signals as inputs, not sole gates.
- Privacy: Data safety declarations match actual data collection; permission rationale and minimization; no advertising IDs without consent where required.
- Versioning: `versionCode` strictly increasing, `versionName` semantic; automate from CI.
- CI: build AAB, run unit + Robolectric + screenshot tests, lint, upload to internal track, then promote. Keep a release checklist and an emergency rollback/halt plan.
- Observability: crash-free rate, ANR rate, startup and jank metrics per version (`./09-observability-security.md`).

Anti-patterns:

- Shipping release builds without R8 due to reflection/keep-rule issues.
- Manual, undocumented release steps.
- Ignoring staged rollout metrics until 100%.
- Permissions requested "just in case".

## Review checklist

- [ ] targetSdk tracks the current Play requirement; compileSdk latest stable.
- [ ] Compose state hoisted; no side effects in composition; stable keys in lists.
- [ ] ViewModel owns screen state; framework types kept out of domain/data.
- [ ] Room: KSP, explicit migrations, schema exported, no destructive fallback in release.
- [ ] Coroutines lifecycle-aware; WorkManager for deferrable work.
- [ ] Baseline profiles and Macrobenchmark run each release.
- [ ] JVM-heavy test suite; Compose tests semantics-based; screenshots reviewed.
- [ ] Release automation: signing, mapping upload, staged rollout, rollback plan.
