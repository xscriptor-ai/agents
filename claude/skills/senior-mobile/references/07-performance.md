# Performance

Startup, frame budgets and jank, memory, network, per-platform profiling, release-mode caveats, and
field monitoring for mobile apps.

## Budgets First

Performance work without a target becomes taste. Set budgets per app and enforce them in CI:

| Metric | Target | Notes |
|---|---|---|
| Cold start (TTID, interactive) | Platform-dependent; define and ratchet | Perfetto/MetricKit/Xcode Organizer |
| Warm start | Faster than cold; no regressions | Measure both |
| Janky frames | < 1% at 95th percentile | Android Vitals definition |
| Frame budget | 16.7 ms at 60 Hz; 8.3 ms at 120 Hz | Per-refresh-rate; high-refresh devices quantize |
| Frozen frames | < 0.1% | Frames > 700 ms |
| App size (download) | Team target, e.g. < 50 MB | App Bundle/App Store thinning |
| Memory (foreground peak) | Device-class dependent | OOM kills are store-tracked |
| Crash-free sessions | >= 99.5% | Definition of done |
| Network payload per screen | Define per API | Bytes and request count on first render |

Budgets are floors for acceptance, not aspirations; any regression beyond noise reopens the change.

## Startup

Startup is what the user feels before the first useful frame: process launch, runtime init,
dependency setup, session restore, first data, first render.

Phases:

1. **Process start** — dylib/framework loading (iOS), class loading and Application init (Android).
2. **Runtime init** — JS engine and bundle load (RN), Flutter engine init, KMP framework load.
3. **App init** — DI graph, SDK setup, config, migrations.
4. **First screen** — auth check, local data read, first render.
5. **Data** — network fetch completes and replaces placeholders.

Techniques:

- Defer non-critical SDK init until after first frame; use startup tasks with declared dependencies
  (Android App Startup, iOS `Task` priorities, lazy imports).
- Avoid disk and network on the launch path; read the session from memory/Keychain only.
- Keep the launch storyboard/window frameless then render progressively.
- Precompute migrations; never block launch on a long migration — run offline with a migration UX.
- Reduce binary/framework count: fewer dynamic frameworks (iOS), avoid unnecessary services.
- For RN: enable Hermes, avoid large synchronous module init, use RAM bundles where appropriate.
- For Flutter: delay plugin registration and avoid heavy `main()` work.
- Measure both cold and warm; clearing caches manually is more realistic than reinstall loops.

## Jank and Frame Budgets

At 60 Hz a frame has 16.7 ms; at 120 Hz, 8.3 ms. Misses appear as jank or frozen frames. Work
belongs on background threads; the UI thread only builds and draws.

Common causes by platform:

| Platform | Typical jank sources |
|---|---|
| SwiftUI | Heavy `body`, unstable IDs, image decode on main, layout thrash, expensive formatters |
| Android/Compose | Recomposition storms, unstable params, main-thread DB/JSON, layout in draw pass |
| React Native | JS thread re-renders, bridge calls, non-Reanimated animations, long lists without virtualization |
| Flutter | Expensive build/layout, unbounded constraints, raster thread saturation, custom shaders |

Fixes:

- Move work off the UI thread: Kotlin coroutines with proper dispatchers, Swift `Task`/actors,
  RN native/worklet code, Flutter isolates.
- Virtualize lists with stable keys and item recycling; keep row `build`/`body` cheap.
- Cache images and decode at display size; never decode full-resolution in a scroll.
- Drive animations on the render/UI thread (Reanimated worklets, Compose animation APIs, Core
  Animation/`withAnimation`, Flutter implicit animations).
- Avoid allocations in hot loops and per-frame closures.
- Instrument first: Perfetto/JankStats (Android), Instruments Core Animation (iOS), Hermes profiler
  (RN), DevTools timeline (Flutter).

## Memory

Mobile kills processes under pressure; the foreground app must stay well below budget. Watch for:

- **Leaks**: retained Activities/ViewControllers, undisposed listeners/controllers, closures
  capturing owners, static caches of contexts.
- **Image memory**: bitmaps are width x height x 4 bytes; downsample to the display size.
- **Unbounded caches**: LRU with explicit limits; clear on trim/memory warning.
- **Large object graphs**: streaming responses instead of loading everything.
- **Fragmentation/alloc churn**: pooling for high-frequency buffers.

Tools: Android Studio Memory Profiler + LeakCanary; Xcode Instruments Allocations/Leaks + MetricKit;
Flutter DevTools memory + `leak_tracker`; RN Hermes heap snapshots and native profilers.

Handle memory warnings: release caches, drop large previews, and persist state so restoration is
cheap. Test on a low-RAM device class, not just a flagship.

## Network

- Reduce requests: batch, aggregate, and prefetch on interaction.
- Compress: gzip/br for text, modern image formats (AVIF/WebP) at display dimensions.
- Cache: HTTP caching with ETags, plus a local store/view cache; never refetch unchanged data.
- Keep payloads small: field selection, pagination, delta sync; avoid over-fetching screens' worth
  of data.
- Timeouts and retries: explicit small timeouts, exponential backoff with jitter, retry idempotent
  operations only.
- Optimize for constrained networks (high RTT, packet loss) not just bandwidth; measure on a
  throttled profile.
- On failure, render local data instead of an empty error screen ([./06-data-offline-sync.md](./06-data-offline-sync.md)).

## Profiling per Platform

| Platform | Tools |
|---|---|
| iOS | Instruments (Time Profiler, Allocations, Leaks, App Launch, Core Animation, Energy), Xcode Organizer metrics, MetricKit |
| Android | Android Studio Profiler, Perfetto/systrace, Macrobenchmark + Baseline Profiles, JankStats, Play Console Android Vitals |
| React Native | Hermes sampling profiler, React DevTools Profiler, Perfetto, Instruments, Flipper (if retained) |
| Flutter | DevTools Performance/Memory, timeline events, `--profile` builds, Impeller traces, `flutter build --analyze-size` |
| Cross | Firebase Performance Monitoring, Sentry Performance, custom RUM with startup/frame markers |

Method:

1. Reproduce on a real mid-range device in profile/release mode.
2. Measure baseline; capture traces, not impressions.
3. Form one hypothesis at a time; change one variable.
4. Re-measure on the same device and scenario; keep a record.
5. Move the improvement into CI (Macrobenchmark, startup markers, bundle-size checks).

## Release-Mode Caveats

- Debug builds disable optimizations, add verification, and represent nothing: never profile them.
- Android: R8 obfuscation changes timings; test release builds with the same keep rules as
  production. Baseline Profiles change startup materially — generate and ship them.
- iOS: Swift whole-module optimization and `-O` change performance; profile release scheme builds
  with symbols. Thermal throttling on long sessions skews results.
- Flutter: `--profile` is close to release but disables some compiler passes; final validation is
  `flutter build --release`.
- RN: dev mode uses the debug JS engine without Hermes bytecode; a development build with the dev
  client is still not release. Test with `--variant release`.
- Hermetic conditions (fresh install, cleared cache, airplane mode toggles) change results; document
  the scenario with the number.

## Field Monitoring

- Android Vitals (ANRs, crashes, startup, jank) and Play Console release metrics.
- MetricKit and Xcode Organizer for iOS launch, hang, memory, and energy diagnostics.
- Crash reporting with performance traces (Crashlytics, Sentry, New Relic); symbol/mapping upload
  is mandatory for readable reports.
- RUM markers for app-specific milestones (login screen ready, feed rendered, checkout complete).
- Segment by device class and OS version; aggregate hides the devices that need work.
- Alert on regressions per release with thresholds; tie alerts to dashboards reviewers check.

## Anti-Patterns

- Optimizing without a budget or baseline.
- Profiling debug builds.
- Moving work between threads without measuring (thread ping-pong and contention are real).
- Caching everything forever; memory grows silently until the OS kills the app.
- Assuming the network is fast because the office Wi-Fi is.
- Chasing a single benchmark number while ignoring thermal throttling and sustained use.
- Deferring performance to "after launch" — startup and jank are shaped by architecture.
- Ignoring app size and download conversion.

## Checklist

- [ ] Startup, frame, memory, size, and crash budgets written and ratcheted in CI.
- [ ] Cold and warm start measured on a mid-range device in release.
- [ ] Jank measured with platform tools and Android Vitals/MetricKit in the field.
- [ ] Lists virtualized; images decoded at display size and cached with limits.
- [ ] Network calls reduced, cached, compressed, and resilient with timeouts/backoff.
- [ ] Memory warnings and leaks handled; low-RAM device tested.
- [ ] Release-mode profiling performed on both platforms before shipping.
- [ ] Symbol/mapping uploads automated for crash reports.
- [ ] Regression alerts configured per release track.

## Cross-Links

- Platform specifics: [./02-ios.md](./02-ios.md), [./03-android.md](./03-android.md)
- Framework specifics: [./04-react-native.md](./04-react-native.md), [./05-flutter.md](./05-flutter.md)
- Offline reads that survive bad networks: [./06-data-offline-sync.md](./06-data-offline-sync.md)
- Security overhead tradeoffs (pinning, obfuscation): [./08-security.md](./08-security.md)
- Rollouts and monitoring gates: [./09-release-store-ci.md](./09-release-store-ci.md)
