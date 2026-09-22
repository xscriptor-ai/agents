# Cross-Platform Decision

Choosing a mobile stack across native, React Native/Expo, Flutter, Kotlin Multiplatform, and MAUI,
with cost, risk, and exit criteria.

## Deciding Well Is Mostly About Constraints

Framework debates fail when they optimize for benchmarks nobody can feel. The decision is driven by
five real constraints:

1. **Team** — what languages the team already writes fluently and can hire for.
2. **Cost** — total engineering cost over 2-3 years, including platform-specific work and upgrades.
3. **Performance** — the worst realistic case (cold start, lists, camera, animation), not the median.
4. **Ecosystem** — SDKs for payments, maps, analytics, ads, BLE, media, and niche hardware.
5. **Time-to-market** — how fast the first meaningful release ships and how fast iteration continues.

Everything else (code sharing percentage, hot reload, "write once") is a means to one of those five.

## Sharing Models, Not Frameworks

Understand the axis before comparing products.

| Model | What is shared | Typical stacks |
|---|---|---|
| Native-native | Nothing (two codebases) | SwiftUI + Compose |
| Shared logic only | Domain, data, networking, persistence | Kotlin Multiplatform, .NET shared libraries |
| Shared logic + UI | Logic plus screen definitions | Flutter, React Native, .NET MAUI, Compose Multiplatform |
| Shared UI only | Unusual; hybrid shells | Web views, embedded mini-apps |

Rule of thumb: the further down the table, the higher the visible fidelity risk and the more you
depend on the framework's escape hatches to reach native behavior.

## Decision Matrix

Score each option 1-5 for the project's actual needs, then weight. A worked example:

| Criterion (weight) | Native | RN + Expo | Flutter | KMP | MAUI |
|---|---|---|---|---|---|
| Existing team skills (25%) | Swift/Kotlin needed | TS reuse | Dart needed | Kotlin reuse | C# reuse |
| Time to first release (20%) | Slowest (2 codebases) | Fast | Fast | Medium | Medium |
| UI fidelity to platform (15%) | Perfect | Approximate | Custom, consistent | Depends on UI layer | Approximate |
| Performance worst case (15%) | Best | Good with new arch | Very good | Near-native | Good |
| Library and SDK coverage (15%) | Complete | Very broad, gaps at hardware edges | Broad, some gaps | Kotlin/JVM ecosystem | Smallest |
| Hiring and long-term cost (10%) | Two roles | One web-ish role | One niche role | One Kotlin role | One .NET role |

Do not carry a score table into the ADR without the reasoning; the reasoning is what survives
personnel changes.

## Framework Notes (2026)

### Native — Swift/SwiftUI and Kotlin/Compose

Apple ships annual OS releases; Android ships yearly API levels plus monthly security patches.
Native gets new platform capabilities on day one (widgets, Live Activities, App Intents, predictive
back, health, wearables). Cost is two codebases and duplicated feature work, offset by lower risk
at the edges and better long-term maintainability for platform-deep apps.

Choose native when the product's differentiation is a platform capability, not the shared CRUD
shell around it.

### React Native + Expo

One TypeScript codebase for iOS, Android, and often web. Expo provides a managed toolchain: EAS
Build, Submit, and Update, config plugins, and prebuild for native projects. The New Architecture
(Fabric renderer, TurboModules, JSI) has been the default for new apps for years; the old bridge
is legacy and shrinking. The main risks are native module gaps and JS-runtime-dependent performance
on low-end Android — always test there.

Choose RN + Expo when the team is already TypeScript-strong, the app is content/CRUD/commerce
shaped, and fast iteration with OTA updates matters more than platform-native flourishes.

### Flutter

Dart with its own rendering engine (Impeller) draws every pixel, so UI is identical across
platforms and highly controllable. Strong for design-heavy apps, dashboards, and teams that want a
single deterministic UI layer. Costs: a larger binary than native or RN, Dart hiring pool, and
platform fidelity that must be explicitly implemented (Cupertino widgets, platform channels).
Web and desktop targets exist but are secondary for most product work.

Choose Flutter when pixel consistency and custom motion/design are core, or when the app targets
many form factors with one UI investment.

### Kotlin Multiplatform (KMP)

Share business logic, networking, persistence, and optionally UI (Compose Multiplatform) while
keeping SwiftUI/Compose for platform-specific screens. Excellent fit for an existing native app
adopting sharing incrementally, especially Android-first teams. iOS interop is stable but adds
build complexity; expect to own Gradle-to-Xcode integration and framework distribution.

Choose KMP when you want native UI with maximum shared logic, or when Android is the primary
business and iOS must follow quickly.

### .NET MAUI

For Microsoft-centric organizations with C# skills and LOB backends. Good tooling integration with
Visual Studio and Azure; smaller third-party ecosystem and more frequent need for custom renderers
or handlers at the platform edges.

Choose MAUI when the organization is a .NET shop and the app is line-of-business rather than
consumer-scale.

## Non-Obvious Cost Drivers

| Cost | Where it bites |
|---|---|
| Platform SDK gaps | A required bank/health/BLE SDK exists only natively; you write the module or the screen natively |
| Upgrade cadence | Framework majors, OS betas, store target-API deadlines each force work |
| Design divergence | iOS and Android interaction conventions require per-platform UI work regardless of stack |
| Accessibility | Screen-reader semantics often need per-platform implementation |
| Team topology | One team owning both platforms can bottleneck; two teams erode code sharing |
| Toolchain ownership | Custom native builds, signing, and CI for each target |

## When Native Wins (hard signals)

- A core feature is only exposed through a native SDK with no maintained wrapper.
- The app is performance-bounded: camera pipelines, audio DSP, games, AR, ML on device.
- Platform presence matters: widgets, watch, TV, auto, App Intents, share extensions.
- Accessibility, security, or regulatory requirements demand first-party APIs.
- The app is long-lived and platform-specific polish is a competitive advantage.

## When Cross-Platform Wins (hard signals)

- Screens are data-driven and conventional: lists, forms, detail pages, checkout, chat.
- A single small team must ship both platforms and web from one skill set.
- Iteration speed dominates: OTA updates, shared design system, one release train.
- The product is an internal or B2B app where 95% fidelity is indistinguishable.

## Greenfield vs Brownfield

| Situation | Recommended path |
|---|---|
| New app, small TS team | React Native + Expo |
| New app, design-led, multi-form-factor | Flutter |
| New app, platform-deep, dedicated teams | Native |
| Existing native app, duplicate logic hurting | KMP for shared core, keep native UI |
| Existing native app, one screen at a time | Embed RN or Flutter module in a native shell |
| Existing .NET organization | MAUI, with a native fallback plan for edge features |

Brownfield rule: introduce sharing behind a stable boundary (repositories, domain services), prove
it for a release, then expand. Never rewrite the shell first.

## Exit Cost and Lock-In

Before committing, answer:

- What is the migration path if the framework loses support?
- Which native modules would we have to rewrite?
- How much UI is framework-specific versus standard?
- Can we keep the domain layer portable (plain models, interface boundaries)?
- What is the realistic cost to move to native per screen?

Keep domain models free of framework types (no UI imports, no ORM annotations leaking everywhere)
so the expensive part — business logic and tests — survives a stack change.

## Common Anti-Patterns

- **Benchmark-driven choice.** Picking by synthetic startup numbers rather than hiring, SDK access,
  and iteration speed.
- **Sharing percentage as a goal.** 100% sharing often means the worst platform experience wins.
- **Ignoring the native module tax.** Every gap becomes custom platform work; estimate it upfront.
- **Skipping a spike.** Not building one hard screen (camera, map, heavy list) before committing.
- **One-team ownership of both platforms without platform specialists.** Review quality drops at
  OS-specific behavior and edge cases.
- **Re-platforming for its own sake.** A rewrite with no product driver usually ships the same app
  later and worse.
- **Choosing on hot-reload demos.** Iteration speed matters, but production performance and store
  compliance decide renewal.

## Migration Notes

- From web-only to mobile: start cross-platform (RN/Expo or Flutter) unless platform depth is core.
- From RN old architecture to New Architecture: migrate dependencies first, then enable per-module;
  see [./04-react-native.md](./04-react-native.md).
- From a native app to shared logic: extract domain and data layers into a KMP module and keep the
  UI native; see [./02-ios.md](./02-ios.md) and [./03-android.md](./03-android.md).
- Never migrate UI and data at the same time; one axis per release.

## Decision Checklist

- [ ] Written constraints: team skills, hiring plan, budget horizon, deadline.
- [ ] One hard screen prototyped in the leading candidate.
- [ ] Required third-party SDKs verified on each candidate platform.
- [ ] Performance target defined against a mid-range device, not a flagship.
- [ ] Platform-specific UI budget estimated (interaction conventions, accessibility).
- [ ] Release automation story validated (signing, CI, store accounts).
- [ ] Exit cost and portability boundary documented in an ADR.
- [ ] Decision reviewed after the first release, with criteria to revisit.

## Cross-Links

- Platform depth: [./02-ios.md](./02-ios.md), [./03-android.md](./03-android.md)
- Framework execution: [./04-react-native.md](./04-react-native.md), [./05-flutter.md](./05-flutter.md)
- Data strategy regardless of stack: [./06-data-offline-sync.md](./06-data-offline-sync.md)
- Non-functional gates: [./07-performance.md](./07-performance.md), [./08-security.md](./08-security.md), [./09-release-store-ci.md](./09-release-store-ci.md)
