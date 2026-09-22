# iOS

Swift 6 concurrency, SwiftUI architecture, navigation, persistence, networking, performance, and
testing for iOS apps built on current Xcode toolchains.

## Version Floor and Toolchain

Target the two most recent major iOS releases for new apps; support the oldest version the product
requires and verify against Apple's current SDK. Swift 6 language mode with strict concurrency is
the default for new code in 2026. Use Xcode's current stable release; beta Xcode is for adapter
work, not releases. Always verify SDK availability and deprecations upstream — iOS deprecates APIs
aggressively and App Store review enforces current SDK builds.

## Swift 6 Concurrency

Swift 6 makes data-race safety a compile-time concern. The core model:

- `async`/`await` with structured concurrency (`TaskGroup`, `async let`) for parallel work.
- Actors isolate mutable state; `@MainActor` isolates UI state.
- `Sendable` marks types safe to cross isolation boundaries; value types and immutable references
  are the easy cases.
- `Task` and task cancellation propagate through structured scopes; handle `CancellationError`.

```swift
actor ImageCache {
    private var store: [URL: Data] = [:]
    func data(for url: URL) -> Data? { store[url] }
    func insert(_ data: Data, for url: URL) { store[url] = data }
}

@MainActor
@Observable
final class FeedModel {
    private(set) var items: [Item] = []
    private let client: APIClient

    init(client: APIClient) { self.client = client }

    func load() async {
        do {
            items = try await client.feed()
        } catch is CancellationError {
            // view disappeared; keep previous state
        } catch {
            // surface error state
        }
    }
}
```

Rules:

1. Prefer `async` functions over completion handlers and GCD. Keep `DispatchQueue` only for legacy
   interop; do not mix queues and actors without a documented boundary.
2. Annotate view models and UI-touching types `@MainActor`; do the heavy work in nonisolated
   functions or actors and hand back `Sendable` values.
3. `Task { @MainActor in ... }` from a view action; cancel long tasks when the view disappears.
4. Avoid unstructured `Task.detached`; it drops priority and cancellation context.
5. Migrate incrementally: enable strict concurrency per target, fix warnings, then per module. Use
   `@preconcurrency import` only as a temporary bridge, with a removal ticket.
6. Async sequences (`for await`) are the idiomatic way to consume streams (notifications, sockets,
   observation).

### Anti-patterns in concurrency

- Singletons with mutable state accessed from several threads without isolation.
- `@unchecked Sendable` used to silence the compiler rather than wrapping state in an actor.
- Blocking the main actor with synchronous disk or network calls.
- Fire-and-forget tasks that outlive their screen and mutate stale state.
- Using `Task.sleep` for debouncing when `.task(id:)` or observation already models the dependency.

## SwiftUI Architecture

- **Model layer** — plain `Sendable` structs/enums, no view imports. Codable for transport.
- **State layer** — `@Observable` classes (Observation framework) for screen models; `@State`
  owns them, `@Bindable` binds into controls. Prefer local state over global stores.
- **View layer** — small views, formatting and layout only; no business logic in `body`.
- **Services** — protocols injected via initializer or an environment key; avoid singletons in
  views so previews and tests can substitute fakes.

```swift
struct UserListView: View {
    @State private var model = UserListModel(client: .live)
    var body: some View {
        List(model.users) { user in
            NavigationLink(value: user) { UserRow(user: user) }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}
```

Principles:

- One source of truth per state; derive the rest with computed properties.
- Keep `body` cheap: no allocations of heavy formatters; cache `NumberFormatter`/`DateFormatter`.
- View identity is performance: avoid changing `id` values on every render, and use
  `Identifiable` entities with stable IDs in `ForEach`.
- Split screens into small `View` structs; the compiler can only diff what is isolated.

### Navigation

- `NavigationStack` with a typed `path` for push/pop; `navigationDestination(for:)` per type.
- Model the path as an array of enums or `Codable` routes so deep links and state restoration map
  to navigation without view callbacks.
- Sheets and full-screen covers hold their own small navigation stacks; do not nest stacks
  arbitrarily.
- Deep links: parse URL into route, then set the path; keep one router for app-wide destinations.

```swift
enum Route: Hashable { case user(User.ID), settings }

@Observable final class Router {
    var path: [Route] = []
    func handle(_ url: URL) { /* map url to Route, replace or append */ }
}

NavigationStack(path: $router.path) {
    HomeView()
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .user(let id): UserView(id: id)
            case .settings: SettingsView()
            }
        }
}
```

### Persistence

| Need | Choice |
|---|---|
| New app, moderate model, iOS-first | SwiftData (`@Model`, `ModelContainer`, `@Query`) |
| Complex migrations, shared store, mature tooling | Core Data with an `NSPersistentContainer` |
| Relational with SQL control and cross-platform | GRDB (SQLite) |
| Small settings | `UserDefaults` / `@AppStorage` (never secrets) |
| Tokens and credentials | Keychain with an accessibility class |
| Files and media | FileManager, app container, exclude caches from backup |

Rules:

- SwiftData is fast to adopt but treat the schema as a migration contract from day one; version it
  and test lightweight plus custom migrations before shipping model changes.
- Do not put large blobs in the database; store file references.
- All database access happens off the main actor for large reads/writes; SwiftData `ModelContext`
  is not `Sendable` — pass `PersistentIdentifier` across actors and refetch.
- `@Query` is convenient but unbounded; paginate or filter for large datasets.
- Back up, then migrate; never mutate a schema and hope the store opens.

### Networking

- `URLSession` async APIs with `Codable`; define one `APIClient` actor per service.
- Inject `URLSessionConfiguration` so tests can use a stub protocol or `URLProtocol`.
- Handle cancellation, 401 refresh with a single-flight token refresh, and retry with exponential
  backoff plus jitter for idempotent GETs only.
- Pin only with a documented key-rotation plan; pinning without a backup pin bricks the app when a
  certificate rotates — see [./08-security.md](./08-security.md).
- Use background `URLSession` for uploads/downloads that must survive app suspension.

### Performance

- Launch: keep `application(_:didFinishLaunchingWithOptions:)` trivial; defer work to first frame.
  Measure with Instruments' App Launch template and Xcode Organizer's launch metrics.
- Lists: `LazyVStack`/`List` with stable identity; avoid nested lazy containers in scroll views.
- Images: decode off the main thread, downsample to display size, cache with `NSCache` or a library.
- Memory: watch retain cycles in closures (`[weak self]` where appropriate), and image caches;
  use Instruments' Leaks and Allocations, plus MetricKit for field data.
- Energy: batch network calls, avoid high-frequency timers, let the system coalesce background work.
- Release builds differ: Swift optimizations, `-O`, and no debug overhead. Profile release builds
  with a release scheme and `dSYM` symbols available.

### Testing

- **Swift Testing** (`@Test`, `#expect`, `#require`, parameterized tests) for unit and integration
  tests in new code; XCTest remains for UI tests and legacy suites.
- Test domain logic without UI; use protocol fakes, not network stubs, where possible.
- UI tests: XCUITest for critical flows only (login, purchase, onboarding); keep them few and stable
  with accessibility identifiers.
- Snapshot tests for design-system components can catch regressions but need strict tolerance and
  device pinning to avoid flakiness.
- Test concurrency: `async` tests with timeouts, and actors behind protocols.

### Anti-Patterns

- Massive view models that mix networking, persistence, and formatting.
- `try!`/force unwraps in shipping code; `fatalError` on recoverable paths.
- Doing work in `init` or `body` that should be a `.task`.
- Ignoring cancellation, then updating UI after the user left the screen.
- Storing tokens in `UserDefaults`.
- Using Debug builds to judge battery, startup, or frame performance.
- Depending on undocumented behavior of the OS; verify against the SDK.

### Checklist

- [ ] Strict concurrency enabled; no `@unchecked Sendable` without justification.
- [ ] Screens have a single state owner and injected dependencies.
- [ ] Navigation is driven by typed routes; deep links and restoration verified.
- [ ] Persistence schema versioned; migration tested with existing data.
- [ ] Network layer handles cancellation, auth refresh, and retry policy.
- [ ] Release build profiled for launch, scroll, and memory on a real device.
- [ ] Critical flows covered by UI tests; domain covered by unit tests.
- [ ] Accessibility labels, dynamic type, and VoiceOver pass on core screens.

## Cross-Links

- Stack choice: [./01-cross-platform-decision.md](./01-cross-platform-decision.md)
- Android counterpart: [./03-android.md](./03-android.md)
- Offline and sync: [./06-data-offline-sync.md](./06-data-offline-sync.md)
- Performance method: [./07-performance.md](./07-performance.md)
- Security requirements: [./08-security.md](./08-security.md)
- Shipping: [./09-release-store-ci.md](./09-release-store-ci.md)
