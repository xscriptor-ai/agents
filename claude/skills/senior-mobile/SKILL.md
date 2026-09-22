---
name: senior-mobile
description: 'Mobile platform reference pack (2026): cross-platform framework selection
  (native, React Native/Expo, Flutter, Kotlin Multiplatform, MAUI), iOS (Swift 6 concurrency,
  SwiftUI, SwiftData) and Android (Kotlin 2, Jetpack Compose) architecture, offline-first
  data and sync engines with conflict resolution, startup/jank/memory performance,
  mobile security against OWASP MASVS, and release engineering across App Store and
  Google Play with fastlane/EAS and CI/CD. Use when choosing a mobile stack, designing
  or reviewing an iOS or Android app, implementing offline sync or background work,
  debugging startup time, jank, memory, or app size, hardening secure storage, TLS,
  and secrets, handling permissions and privacy, or shipping builds through store
  review, staged rollouts, and crash reporting.'
---

# Mobile

Reference pack for building, reviewing, and shipping mobile applications in 2026. It covers the
whole delivery path: how to pick a stack, how to architect iOS and Android apps, how data survives
a bad network and a backgrounded process, how the app stays fast and secure on mid-range hardware,
and how a build reaches a store without breaking.

The pack is framework-aware but not framework-locked: Swift/SwiftUI, Kotlin/Compose, React Native
with Expo, Flutter, and Kotlin Multiplatform appear side by side. Treat named libraries as examples
of a category. Version numbers are floors or ranges; when an API, limit, or store policy matters,
verify upstream.

## Non-Negotiable Core Rules

1. **Pick the stack once, explicitly, against a written decision matrix.** Re-litigating frameworks
   mid-project is the most expensive mobile mistake. Record the choice, the constraints, and the
   exit cost in an ADR.
2. **Design for the device, not the simulator.** Mid-range Android, small batteries, spotty networks,
   low storage, and interrupted sessions are the default; the flagship on Wi-Fi is the exception.
3. **Offline is a state, not an error.** Every read path should render something from local data;
   every write path should queue, reconcile, and show sync status. Assume the network is absent first.
4. **The main thread renders; everything else moves off it.** Disk, network, JSON, image decode,
   crypto, and database work belong off the UI thread on every platform.
5. **Own the lifecycle.** Processes are killed, background work is throttled, permissions are
   revoked, and OS versions drop APIs. Persist through `onPause`/scene disconnect, not just on exit.
6. **Continuous frames are a hard requirement.** Nail the frame budget for the device refresh rate
   (16.7 ms at 60 Hz, 8.3 ms at 120 Hz) and measure in release mode on real hardware.
7. **Secure storage is the only storage for credentials.** Keychain on iOS, Keystore-backed storage
   on Android; never `SharedPreferences`, `UserDefaults`, plists, or plain files for tokens.
8. **Secrets do not ship in the binary.** Anything bundled can be extracted. Server-side keys stay
   server-side; client identifiers are public by definition.
9. **Minimize permissions and justify each one.** Request in context, degrade when denied, and never
   gate the core experience on an optional permission.
10. **Measure startup, memory, and crash-free rate in the field, not only in the lab.** Store vitals
    and crash reporting are part of the definition of done.
11. **Accessibility and localization are correctness.** Screen readers, dynamic type, contrast,
    reduced motion, RTL, and plural rules are built in, not retrofitted.
12. **Automate the release path.** Signing, versioning, notes, screenshots, and uploads are code in
    CI; a release that only one person can perform is a bus factor of one.
13. **Keep platform APIs first choice.** Widgets, live activities, notifications, share sheets,
    biometrics, and background schedulers have system behavior users expect; wrappers leak.

## Decision Tables

### Stack at a glance

| Option | Language / UI | Sharing | Best for | Weak spots |
|---|---|---|---|---|
| Native | Swift + SwiftUI; Kotlin + Compose | None | Flagship, platform-deep, performance-critical | Two codebases, highest cost |
| React Native + Expo | TypeScript + RN views | 80-95% (logic + UI) | Product teams with web/TS skills, fast iteration | Native module edges, JS runtime limits |
| Flutter | Dart + own renderer | ~100% | Pixel-identical UI, custom design systems | Larger binary, Dart hiring, platform fidelity gaps |
| Kotlin Multiplatform | Kotlin shared core; Compose or native UI | Logic 100%, UI optional | Existing native apps, shared domain/data layers | iOS toolchain maturity; CMP still evolving |
| .NET MAUI | C# + XAML | ~100% | Microsoft-centric enterprise and LOB apps | Smaller ecosystem, iOS/Android rough edges |

### When native wins

| Signal | Why native |
|---|---|
| Widgets, watch, TV, CarPlay/Android Auto, App Intents | First-class SDK access and release cadence |
| Camera, audio, BLE, AR, ML accelerators | Direct access to platform frameworks and hardware |
| Latency-critical UI (games, camera pipelines, drawing) | No bridge or second runtime in the path |
| Accessibility and platform conventions are product requirements | Native semantics for free |
| Long-lived app with dedicated per-platform teams | Lowest long-term platform friction |

### Data layer at a glance

| Need | Local store | Notes |
|---|---|---|
| Relational, queries, migrations | SQLite (Room, GRDB, Drift, SQLDelight) | Default for structured app data |
| Small key/value, flags, prefs | DataStore, MMKV, `NSUserDefaults` (non-sensitive) | Never for tokens |
| Large blobs | Files + metadata index | Keep blobs out of the database |
| Document sync with a backend | Sync engine (PowerSync, Electric, Couchbase Lite, Firestore) | Buy sync before building it |
| Ephemeral cache | In-memory LRU + disk cache | Has an owner, TTL, and invalidation rule |

### Release readiness gates

| Gate | Check |
|---|---|
| Correctness | Crash-free sessions >= 99.5% on the beta track |
| Performance | Startup, frame, and memory budgets verified in release on real devices |
| Security | MASVS checklist passed; no secrets in the bundle; pinning decision recorded |
| Privacy | Store privacy labels/data safety form match actual collection |
| Rollback | Staged rollout plan, kill switch, and hotfix path defined |
| Automation | CI builds, signs, and uploads from a clean checkout |

## Reference Index

| File | Scope | Load when |
|---|---|---|
| [references/01-cross-platform-decision.md](./references/01-cross-platform-decision.md) | Framework comparison across team, cost, performance, ecosystem, time-to-market; native-win signals; hybrid and migration paths | Choosing or reviewing a mobile stack, brownfield adoption, build-vs-buy on sharing |
| [references/02-ios.md](./references/02-ios.md) | Swift 6 strict concurrency, SwiftUI architecture and navigation, SwiftData/Core Data, URLSession, Instruments, Swift Testing | Writing or reviewing iOS code, concurrency bugs, persistence, launch and energy issues |
| [references/03-android.md](./references/03-android.md) | Kotlin 2, Jetpack Compose, lifecycle and ViewModel, Hilt, Room/DataStore, Retrofit/Ktor, baseline profiles, testing | Writing or reviewing Android code, recomposition problems, process death, startup regressions |
| [references/04-react-native.md](./references/04-react-native.md) | New Architecture (Fabric, TurboModules, JSI), Expo Router, native modules, EAS build/update, performance pitfalls | Working in a React Native/Expo codebase, native module work, OTA and build pipeline questions |
| [references/05-flutter.md](./references/05-flutter.md) | Impeller, state management, isolates, platform channels and Pigeon, performance, widget and golden testing | Working in Flutter, rendering and jank issues, isolate and channel design, Dart architecture |
| [references/06-data-offline-sync.md](./references/06-data-offline-sync.md) | Local storage choices, sync engines, outbox patterns, conflict resolution, background sync, offline UX | Building offline-first features, choosing a sync engine, debugging divergent or lost writes |
| [references/07-performance.md](./references/07-performance.md) | Startup, frame budgets and jank, memory, network, per-platform profiling, release-mode caveats, field monitoring | Diagnosing slow launch, dropped frames, leaks, OOMs, or setting performance budgets |
| [references/08-security.md](./references/08-security.md) | OWASP MASVS/MASWE, secure storage, TLS and pinning tradeoffs, obfuscation, secrets, integrity and root detection | Threat modeling, credential storage, transport hardening, privacy and permission review |
| [references/09-release-store-ci.md](./references/09-release-store-ci.md) | Signing, fastlane/EAS, store requirements, staged rollouts, crash reporting, CI/CD pipelines and hotfixes | Setting up release automation, store submission, rollouts, or responding to a bad release |

## How to Use This Pack

- Start from the decision tables, then load only the references the task needs; do not load all nine
  by default.
- New app or stack choice: load 01 first, then the chosen platform reference.
- Feature work with a backend: pair the platform reference with 06 (offline/sync) early.
- Before any release: load 07 (performance), 08 (security), and 09 (release) as a checklist pass.
- References cross-link with relative paths such as `./06-data-offline-sync.md`; follow them when a
  topic borders another domain.

## Port

- **Port id** — `skill://senior/mobile` (version in `metadata.port-version`).
- **Kind** — read-only reference pack; no side effects, no tools, no scripts required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "mobile" })` in OpenCode; Claude Code reads
     `<skills-dir>/mobile/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the
     degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers
  reference it as `load skill senior-mobile (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major.
