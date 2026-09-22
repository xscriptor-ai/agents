# React Native

The New Architecture, Expo tooling, navigation, native modules, EAS pipelines, and the performance
pitfalls that decide whether a React Native app feels native.

## Version Floor and Architecture

In 2026, the New Architecture is the default for new React Native apps: Fabric (renderer),
TurboModules (native modules), and JSI (synchronous host calls), with Hermes as the engine. The
legacy bridge remains through an interop layer for unmigrated libraries only. New apps should not
enable legacy mode. Verify the current React Native, React, and Expo SDK versions upstream; Expo
releases a new SDK on a regular cadence and RN majors land several times a year.

Practical floors: TypeScript everywhere, Hermes on both platforms, Fabric-compatible dependencies,
and React 19-era semantics (automatic batching, transitions, `use` and Suspense patterns where the
framework supports them).

## Project Setup: Expo vs Bare

**Expo is the default recommendation** for most apps. It provides:

- `expo` package with modules for camera, location, notifications, secure storage, and more.
- Config plugins and Continuous Native Generation (CNG): `ios/` and `android/` are generated from
  `app.json`/`app.config.ts`, so they stay out of version control.
- EAS Build/Submit/Update for cloud builds, store uploads, and OTA updates.
- Expo Router for file-based routing on top of React Navigation.

Choose **bare React Native** (or eject via `expo prebuild` with a committed native project) only
when a dependency requires manual native edits that no config plugin covers, or when the team owns
a large existing native project.

```bash
# New app, TypeScript, Expo Router by default
npx create-expo-app@latest my-app
cd my-app && npx expo start
```

Rules:

- Never commit generated `ios/` and `android/` unless you have explicitly opted out of CNG.
- Pin the Expo SDK; upgrade through the recommended `expo install --fix` path rather than bumping
  packages ad hoc.
- Keep one package manager and lockfile; the Metro resolver and native autolinking depend on it.

## Expo Router

File-based routing where the filesystem is the nav graph. Layouts compose, groups organize, and
dynamic segments map to params.

```
app/
  _layout.tsx          # root stack, providers, auth gate
  (tabs)/
    _layout.tsx        # tab bar
    index.tsx          # /
    feed.tsx           # /feed
  user/[id].tsx        # /user/:id
  +not-found.tsx
```

```tsx
// app/user/[id].tsx
import { useLocalSearchParams, router } from "expo-router";

export default function UserScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { data, isPending, error } = useUser(id);
  if (isPending) return <Spinner />;
  if (error) return <ErrorView error={error} onRetry={refetch} />;
  return <UserProfile user={data} onBack={() => router.back()} />;
}
```

Rules:

- Auth gating lives in a layout with redirects; never render protected screens then redirect.
- Use typed routes so route names and params are checked at build time.
- Deep links map to routes automatically; validate params defensively.
- Keep screens thin: data fetching and business logic in hooks/services, not components.

## Data and State

| Concern | Recommended |
|---|---|
| Server state (fetch/cache/invalidate) | TanStack Query (or the framework's equivalent) |
| Small global client state | Zustand or `useSyncExternalStore` |
| Form state | React Hook Form or controlled local state |
| Fast key/value persistence | `react-native-mmkv` (sync JSI reads) |
| Structured local data | SQLite (expo-sqlite, Drizzle ORM) |
| Sensitive values | `expo-secure-store` / Keychain + Keystore |

Rules:

- Server cache is not client state: do not copy query results into a global store; let the cache
  own it and subscribe with selectors.
- MMKV is fast but plaintext by default; enable encryption for anything sensitive and use
  SecureStore for credentials.
- Persist only what you can rehydrate: schema-version the client store and handle migrations.

## Native Modules

Write a native module when a capability has no maintained library: Bluetooth edge protocols, a
vendor SDK, platform widgets, or heavy synchronous math that JSI enables.

Options, in order of preference:

1. Existing Expo module or community package compatible with the New Architecture.
2. Expo Modules API (Swift/Kotlin) for new modules — less boilerplate and Swift/Kotlin first.
3. TurboModule via codegen — full control for bare projects.
4. Legacy bridge module — only for interop with unmigrated dependencies; plan removal.

```ts
// native module surface stays small and typed
import { requireNativeModule } from "expo-modules-core";

const BatteryInfo = requireNativeModule("BatteryInfo");
export const getLevel = (): number => BatteryInfo.getLevel();
```

Rules:

- Keep the JS surface minimal; return plain serializable data, not opaque handles.
- Never block the JS thread with synchronous JSI calls that do I/O.
- Every native module needs unit tests on the native side and a typed TS wrapper.
- Budget native module work explicitly; it is where cross-platform schedules slip.

## EAS: Build, Submit, Update

```bash
eas build --platform ios --profile production
eas submit --platform ios --latest
eas update --branch production --message "fix checkout copy"
```

Rules:

- `eas.json` defines profiles (`development`, `preview`, `production`) and channels; keep
  development builds with the dev client, previews internal-distribution, production store-signed.
- **OTA updates may only change JS/asset content**, never native code, permissions, or store
  metadata. Apple and Google allow JavaScript updates within policy bounds but a change that
  affects the app's primary purpose or native behavior must go through review.
- Always keep a rollback story: EAS Update lets you republish a previous compatible update; native
  builds still require store review.
- Runtime versions gate which native builds can receive an update; bump when native modules change.
- Signing credentials live in the EAS credential store or CI secrets, never in the repo.

## Performance Pitfalls

React Native performance is mostly about what runs on the JS thread and how often React renders.

| Pitfall | Fix |
|---|---|
| Re-rendering whole lists | Memoized row components, stable keys, `FlashList` for large lists |
| Inline objects/functions in hot props | `useCallback`/`useMemo` where they cross memo boundaries |
| Context value recreated each render | Split contexts, memoize values, use selectors |
| Heavy JSON parsing on JS thread | Parse in a native module or move to a worker/native layer |
| Large images in list cells | Request sized images, cache with `expo-image` or FastImage |
| Animations on JS driver | Use Reanimated (UI thread) with worklets and gesture handler |
| Startup work in module scope | Lazy-import screens; defer non-critical init |
| Bundle growth | Enable RAM bundles/Hermes bytecode, tree-shake, audit imports |
| Slow first render after navigation | Prefetch data on interaction, use `React.startTransition` |

Profiling: React DevTools profiler for render churn, the Hermes sampling profiler for JS CPU,
Perfetto/Android Studio for native frames, and Xcode Instruments for iOS. Always profile a release
build: dev builds add enormous overhead.

## Testing

| Level | Tooling |
|---|---|
| Unit | Jest, React Native Testing Library (user-centric queries) |
| Integration | RNTL with mocked network (MSW) and a test store |
| End-to-end | Maestro (simple flows) or Detox (deep native control) |
| Type safety | TypeScript strict, `tsc --noEmit` in CI |
| Lint/format | ESLint with the RN config, Prettier |

Rules: test hooks and services, not implementation details; keep E2E to critical journeys; run E2E
on one iOS and one Android target to control CI cost.

## Upgrade Strategy

- Upgrade one minor at a time on RN; read the changelog and the New Architecture compatibility
  list before bumping.
- Expo SDK upgrades bundle RN, React, and module versions; use the official upgrade command and fix
  warnings before adding features.
- Native build upgrades: Gradle, AGP, Kotlin, Xcode, CocoaPods; keep a CI job that builds both
  platforms on every PR to catch toolchain drift early.
- Freeze dependency upgrades before a release branch; upgrade after the release, not during.

## Anti-Patterns

- Fighting the New Architecture by leaving libraries on the legacy bridge indefinitely.
- Committing generated native folders while pretending to use CNG.
- Putting server data in Zustand/Redux instead of the query cache.
- Business logic in components; screens with lifecycle-dependent side effects.
- OTA updates used to push policy-violating changes.
- Profiling in dev mode and concluding performance is fine.
- One gigantic `app/` route tree with shared mutable state across tabs.
- `AsyncStorage` for large datasets or secrets.

## Checklist

- [ ] New Architecture enabled; all native deps Fabric-compatible.
- [ ] Expo SDK and RN versions pinned; CI builds both platforms on PRs.
- [ ] Router structure documented; auth gating in layouts; typed routes enabled.
- [ ] Server state in a query cache; persistence schema versioned.
- [ ] Secrets in SecureStore; MMKV encrypted where used.
- [ ] Lists virtualized with stable keys; animations on the UI thread.
- [ ] OTA policy, runtime version, and rollback procedure documented.
- [ ] Release-mode profiling for startup, lists, and navigation.

## Cross-Links

- Stack choice: [./01-cross-platform-decision.md](./01-cross-platform-decision.md)
- Flutter alternative: [./05-flutter.md](./05-flutter.md)
- Offline and sync: [./06-data-offline-sync.md](./06-data-offline-sync.md)
- Performance method: [./07-performance.md](./07-performance.md)
- Security requirements: [./08-security.md](./08-security.md)
- Shipping with EAS: [./09-release-store-ci.md](./09-release-store-ci.md)
