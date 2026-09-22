# Flutter

Impeller rendering, Dart 3 language practice, state management, isolates, platform channels,
performance, and widget-level testing.

## Version Floor and Toolchain

Target the current stable Flutter channel (never `beta` for releases) with Dart 3.x. Impeller is
the default renderer on iOS and Android for modern devices; the legacy Skia path is a fallback for
older hardware and some platforms. Verify current support matrices upstream before relying on any
renderer behavior. Use `flutter analyze` with `flutter_lints` (or stricter) and treat warnings as
errors in CI.

Rules:

- Pin the Flutter SDK per repo (FVM or the version in CI) so engines and generated code match.
- Keep `pubspec.lock` committed for applications.
- Prefer stable plugins with recent releases and platform support; audit before adoption.
- Do not mix multiple state-management paradigms in one app.

## Dart 3 Language Practice

- Sound null safety everywhere; avoid `!` outside invariants you assert in tests.
- Records, patterns, and switch expressions for destructuring and exhaustive handling.
- Sealed classes for state machines and results; exhaustiveness is compiler-checked.
- Extension types and `final class` for zero-cost wrappers.
- `async`/`await` plus `Stream` for async; `FutureBuilder`/`StreamBuilder` only for simple cases.

```dart
sealed class FeedState {
  const FeedState();
}
final class FeedLoading extends FeedState { const FeedLoading(); }
final class FeedReady extends FeedState {
  const FeedReady(this.items);
  final List<Item> items;
}
final class FeedFailed extends FeedState {
  const FeedFailed(this.message);
  final String message;
}
```

## Rendering: Impeller and the Frame Pipeline

Flutter builds a widget tree, then an element tree, then a render tree, then layers, then paints
with Impeller. Each frame runs build, layout, paint, and raster on the UI thread and raster thread.

Performance implications:

- Build cost is per-widget; keep `build` pure and cheap.
- Layout is the most expensive phase; avoid unbounded constraints and deep nesting.
- Repaint only what changed; `RepaintBoundary` isolates expensive subtrees.
- Impeller compiles shaders ahead of time; custom fragment shaders via `FragmentProgram` are
  supported but add pipeline variance — measure before adopting.
- Avoid `Opacity`/`ClipRRect`/blur in scrolling content; use `AnimatedOpacity`, cached clips, and
  image shadows instead.

## State Management

Choose one primary approach and enforce it.

| Approach | Shape | Best for |
|---|---|---|
| Riverpod | Providers, compile-safe DI + state | Most apps; testable, no BuildContext coupling |
| Bloc | Events to states, explicit transitions | Complex flows, auditable state machines |
| Provider / InheritedWidget | Minimal dependency passing | Small apps, libraries |
| Signals / ValueNotifier | Fine-grained reactivity | Leaf-level state, performance-sensitive UI |

Riverpod sketch:

```dart
@riverpod
class Feed extends _$Feed {
  @override
  Future<List<Item>> build() => ref.watch(feedRepositoryProvider).fetch();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(feedRepositoryProvider).fetch());
  }
}
```

Rules:

- UI reads state and calls notifiers; it does not contain business logic.
- Dependencies are injected through providers and overridden in tests.
- Keep global state for cross-cutting concerns only (auth, theme, connectivity); feature state is
  scoped and disposed with the feature.
- Never hold `BuildContext` in async logic across awaits (`use_build_context_synchronously`).

## Navigation

- `go_router` for declarative, URL-addressable routes with deep linking, redirects, and shell
  routes (tabs).
- Typed route classes for parameters; validate and normalize path/query arguments.
- Auth redirects in a single `redirect` callback; never render protected screens and pop.
- Keep navigation decisions in one place; widgets navigate by invoking intents, not by embedding
  route strings everywhere.

```dart
final router = GoRouter(
  redirect: (context, state) {
    final signedIn = ref.read(authProvider).isSignedIn;
    final atLogin = state.matchedLocation == '/login';
    if (!signedIn) return atLogin ? null : '/login';
    return atLogin ? '/' : null;
  },
  routes: [
    GoRoute(path: '/', builder: (c, s) => const HomeScreen()),
    GoRoute(path: '/user/:id', builder: (c, s) => UserScreen(id: s.pathParameters['id']!)),
  ],
);
```

## Isolates and Concurrency

Dart runs one event loop per isolate; the main isolate renders UI and must stay responsive.

- Use `Isolate.run` for one-shot CPU-heavy work (parsing, image processing, crypto).
- Use long-lived isolates with ports for repeated work; `compute()` is the simple one-shot helper.
- Keep payloads small: isolates copy memory unless using `TransferableTypedData` or `Isolate.exit`.
- `dart:ffi` runs on the calling isolate; a blocking native call still blocks the UI unless moved
  to an isolate or `NativeCallable.listener`.
- Never share mutable state across isolates; pass immutable messages.
- Platform channels are asynchronous by nature and do not solve CPU work on the Dart side.

```dart
final parsed = await Isolate.run(() => parseLargeJson(rawBytes));
```

## Platform Channels and Plugins

Options, preferred order:

1. Maintained pub.dev package for the capability.
2. `MethodChannel`/`EventChannel` via Pigeon for typed, code-generated bindings (no string keys).
3. `dart:ffi` for C libraries and performance-critical native calls.
4. Federated plugin with separate Android/iOS implementations for reusable native surfaces.

Rules:

- Always generate bindings with Pigeon for new channels; hand-written string method names rot.
- Handle `PlatformException` and `MissingPluginException` explicitly; degrade gracefully.
- Channel calls are async and add latency; batch hot-path calls or move to FFI.
- Test channels with mocks/fakes and at least one integration test per platform.
- Keep native Kotlin/Swift code minimal and standard-conformant; Flutter does not excuse platform
  conventions such as Android foreground-service types or iOS background modes.

## Performance

- **Startup**: defer non-critical plugin registration, avoid heavy work in `main()`, use
  `WidgetsFlutterBinding.ensureInitialized()` only when needed, and measure with `flutter run
  --profile` and DevTools timeline.
- **Jank**: profile with the DevTools performance page; look for long build/layout/paint events and
  raster thread saturation; use `--trace-skia`/Impeller traces where needed.
- **Lists**: `ListView.builder`/`SliverList` with stable keys; `addAutomaticKeepAlives` only when
  required; image decode with `cacheWidth`/`cacheHeight`.
- **Images**: `cached_network_image` or `Image.network` with `cacheWidth`; avoid full-resolution
  decodes in grids.
- **App size**: `flutter build appbundle --analyze-size`; remove unused assets and fonts; split
  ABI/per-ABI artifacts; tree-shake icons (`--tree-shake-icons`).
- **Memory**: watch image cache (`imageCache.maximumSizeBytes`), dispose controllers, and use
  DevTools memory profiling for leaks (undisposed `AnimationController`, listeners, streams).
- Release-mode caveat: `--profile` disables some optimizer passes; final numbers come from
  `flutter build --release` on real devices. Debug builds are not representative at all.

## Testing

| Level | Tooling |
|---|---|
| Unit | `test` package, `mocktail`/`mockito`, `fake_async` for time |
| Widget | `flutter_test`, `pumpWidget`, semantics finders |
| Golden | `matchesGoldenFile` with pinned fonts and devices |
| Integration | `integration_test` package on device/emulator |
| Lint | `flutter analyze`, custom lint rules, formatting in CI |

Rules:

- Widget tests assert user-visible behavior via finders and semantics, not private members.
- Golden tests are valuable but need deterministic fonts (bundle a test font) and generation on
  the CI platform; otherwise they flake across machines.
- Integration tests cover critical journeys (login, purchase, offline recovery); keep the suite
  small.
- Use `ProviderScope(overrides: [...])` to fake repositories in widget tests.

## Anti-Patterns

- Business logic in widgets; `setState` used for app-wide state.
- Creating providers, controllers, or futures inside `build` (recreated every frame).
- Unbounded `Column` inside `SingleChildScrollView` with many children instead of slivers.
- `Opacity`/`ClipRRect`/`BackdropFilter` on scrolling content without measuring.
- Heavy JSON parsing on the main isolate.
- Channel string keys duplicated in Dart and native code instead of Pigeon.
- Ignoring `dispose` for controllers, subscriptions, and focus nodes.
- Judging performance from debug builds.

## Checklist

- [ ] Flutter SDK pinned; `flutter analyze` clean and formatted in CI.
- [ ] One state-management approach; providers overridable in tests.
- [ ] Navigation centralized with deep links and typed params.
- [ ] Isolates used for CPU-heavy work; no blocking calls on the UI isolate.
- [ ] Channels generated via Pigeon; platform exceptions handled.
- [ ] Profile builds measured for startup, scroll jank, and memory on a mid-range device.
- [ ] Golden tests deterministic; integration tests cover critical journeys.
- [ ] All controllers/listeners disposed; leaks checked in DevTools.

## Cross-Links

- Stack choice: [./01-cross-platform-decision.md](./01-cross-platform-decision.md)
- React Native alternative: [./04-react-native.md](./04-react-native.md)
- Offline and sync: [./06-data-offline-sync.md](./06-data-offline-sync.md)
- Performance method: [./07-performance.md](./07-performance.md)
- Security requirements: [./08-security.md](./08-security.md)
- Shipping: [./09-release-store-ci.md](./09-release-store-ci.md)
