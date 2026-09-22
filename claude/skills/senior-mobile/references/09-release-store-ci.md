# Release, Stores, and CI

Signing, build automation with fastlane/EAS, store requirements, staged rollouts, crash reporting,
and CI/CD for iOS and Android releases.

## Release Pipeline Shape

```
commit -> CI build (debug + tests)
       -> CI signed release artifacts
       -> upload to internal track / TestFlight
       -> QA + internal validation
       -> staged rollout (Play) / phased release (App Store)
       -> monitoring window -> full rollout
       -> post-release review and cleanup
```

Rules:

- Every release is built by CI from a tagged commit; no local builds with personal credentials.
- Artifacts are immutable and archived with symbols/mappings and their source commit.
- The same binary that passed QA is the one promoted to production; no rebuild-per-track.
- Release notes, screenshots, and metadata live in version control where the tooling supports it.
- One owner per release, with a documented checklist and a rollback decision point.

## Versioning

- Use semantic versioning for user-facing `versionName`/`CFBundleShortVersionString`, and a
  monotonic integer build number for `versionCode`/`CFBundleVersion`.
- Never reuse a build number: stores and crash reporting treat it as identity.
- Drive build numbers from CI (run number or commit count); avoid manual increments.
- Keep a changelog per release; internal notes explain risk and testing done, not just features.
- Hotfix versions increment patch and build; do not rewrite history on a published version.

## iOS Signing and Submission

Components:

- Apple Developer Program membership and App Store Connect access.
- Development and distribution certificates; provisioning profiles per bundle ID and capability.
- An App Store Connect API key for automation (issuer ID, key ID, `.p8` private key) with minimal
  roles.
- App ID capabilities (push, associated domains, keychain sharing, app groups) declared in the
  project and the portal.

Automation options:

- **fastlane match** for certificate/profile management: one encrypted repo, CI reads it with a
  deploy key, new machines onboard without portal clicking.
- **Xcode-managed signing with cloud signing** via `xcodebuild -allowProvisioningUpdates` using the
  API key for simple setups.
- `xcodebuild archive` then `xcodebuild -exportArchive` with an `ExportOptions.plist`; or fastlane
  `gym` plus `pilot`/`deliver` for TestFlight and metadata.

Rules:

- Certificates and keys never live on developer laptops as the source of truth.
- Profiles are regenerated when capabilities change; treat "no profiles available" as a config bug,
  not a manual task.
- TestFlight builds expire; automate a rolling beta rather than uploading by hand.

## Android Signing and Submission

Components:

- Keystore with the upload key; Play App Signing holds the app signing key (recommended; required
  for new apps and App Bundles).
- `signingConfigs` wired from environment/CI secret store; the keystore is never committed.
- Play Console service account with JSON credentials for API automation (Gradle Play Publisher or
  fastlane supply).

Rules:

- Back up the upload keystore and credentials in a team secret store with documented recovery. Lost
  upload keys can be reset with Play support; lost app signing keys are unrecoverable without it.
- Build App Bundles (`.aab`); Play generates per-device splits. APKs are for local testing or
  distribution outside Play.
- Target the current required API level; the deadline advances annually and blocks uploads when
  missed. Verify the current requirement upstream.
- Align native libraries to the required page size (16 KB requirement for recent Android versions);
  check all `.so` files and third-party SDKs. Verify the current deadline upstream.
- Review manifest changes each release: permissions, exported components, foreground service types,
  and data safety declarations must match behavior.

## Store Requirements (verify current policies upstream)

| Area | iOS | Android |
|---|---|---|
| Privacy | App Privacy labels, privacy manifest, ATT where applicable | Data Safety form, permission declarations |
| Account | Account deletion in-app if accounts can be created | Account deletion requirement |
| Payments | In-app purchase for digital goods; entitlements for external purchase in some regions | Play Billing for in-app digital goods; regional rules vary |
| Sign-in | Sign in with Apple when other third-party sign-ins exist | No equivalent universal rule |
| Content | Age ratings, UGC moderation, reporting/blocking | Content rating, UGC policy, families policy |
| Tracking | ATT prompt before tracking | Advertising ID policies, consent requirements |
| EU DSA | Trader status and contact info required for distribution | Developer verification and trader declarations |
| Review | Human review with App Review Guidelines; rejections need a resolution path | Automated plus policy review; appeals and policy status |

Practical notes:

- Review times vary; never plan a marketing date that depends on same-day approval.
- Keep demo accounts and review notes current; reviewers must reach every feature.
- Rejections are usually metadata/privacy mismatches, not bugs. Fix the mismatch, respond factually,
  and avoid resubmitting unchanged.
- Pre-review with `fastlane precheck`-style checks and internal review of screenshots, keywords,
  and privacy answers.

## Build Automation

### fastlane

```ruby
# Fastfile (sketch)
lane :beta do
  match(type: "appstore", readonly: true)
  build_app(scheme: "App", export_method: "app-store")
  upload_to_testflight(skip_waiting_for_build_processing: true)
end
```

- `match` for iOS signing; `supply` for Play uploads with metadata and screenshots.
- Keep lanes small and composable; secrets come from CI environment.
- Use `deliver` for metadata/screenshots; store them in the repo for review.

### EAS (React Native/Expo)

```bash
eas build --platform all --profile production --non-interactive
eas submit --platform android --latest --non-interactive
```

- `eas.json` profiles define distribution and env; secrets in EAS or CI.
- EAS Update handles OTA JS changes within policy; native changes require a new build.
- Version and build numbers managed via `app.json`/remote versioning; keep them monotonic.

### Gradle/Xcode directly

- `./gradlew bundleRelease` with R8, resource shrinking, and signing from env.
- `xcodebuild archive` + `-exportArchive`; use `-resultBundlePath` to archive diagnostics.
- Cache Gradle and CocoaPods/SwiftPM between CI runs; cache invalidation is a common source of
  flaky builds.

## CI/CD

Recommended shape:

| Stage | Runs on | Purpose |
|---|---|---|
| Lint/typecheck | Every PR, Linux | Fast feedback (ktlint/detekt, swiftlint/swift-format, eslint/tsc, dart analyze) |
| Unit tests | Every PR | Domain logic with coverage on critical modules |
| Build (both platforms) | Every PR to main | Toolchain drift detection; produce debug/dev artifacts |
| Instrumented/E2E | Merge queue or nightly | Device-level regressions; keep the matrix small |
| Release build | Tag or manual | Signed artifacts, changelog, upload to internal track |
| Rollout | Manual gate | Staged percentages and monitoring windows |

Rules:

- macOS runners are required for iOS builds; budget cost and cache aggressively.
- CI holds signing material in a secrets manager with least privilege; rotate on personnel change.
- Builds must be reproducible enough to rerun a tag; pin toolchain versions (Xcode, Gradle, AGP,
  JDK, Flutter/Expo SDK).
- Fail fast on lint and tests, but never let a flaky test silently disable a gate; quarantine with
  a ticket.
- Artifact retention: keep release artifacts, symbol files, and mapping files as long as crash
  reports reference them.

## Staged Rollouts and Monitoring

- Play: start at a small percentage (for example 5-10%), watch Android Vitals and crash-free rate
  for 24-72 hours, then increase. Halt immediately on regressions.
- App Store: phased release over 7 days; pause when crash or hang metrics rise.
- Define go/no-go criteria before rollout: crash-free sessions, ANRs/hangs, startup P90, business
  KPIs, support volume.
- Monitor during the window; an unwatched rollout is not staged, it is delayed.
- Freeze changes and deploys to backend dependencies during the rollout window to keep causality.
- Keep a rollback plan: halt rollout for native, hotfix branch for critical defects, OTA rollback
  where the framework allows it.

## Crash Reporting and Observability

- Install crash reporting before the first beta: Crashlytics, Sentry, or equivalent.
- Upload symbols (`dSYM`), ProGuard/R8 mappings, and source maps on every build; automate it.
- Configure grouping, breadcrumbs without PII, and user context that respects privacy.
- Track non-fatal errors, ANRs/hangs, and startup traces, not just crashes.
- Alert to a monitored channel with clear ownership; wire alerts to the on-call rotation.
- Verify symbolication with a test crash per release candidate.

## Hotfix and Rollback

| Situation | Action |
|---|---|
| JS/asset-only bug in RN/Expo | OTA update on a rollback-safe runtime version, or republish a previous update |
| Native bug, low severity | Fix in the next scheduled release; document workaround |
| Native crash or data-loss bug | Halt rollout, ship hotfix patch as fast as review allows, consider remote kill switch |
| Backend incompatibility | Feature-flag off server-side immediately; clients should degrade, not crash |
| Bad store metadata | Update metadata without a binary where the store allows |

Requirements for this to work: features behind flags, server-side kill switches, version gates for
APIs, and backward-compatible APIs for at least one version back.

## Release Checklist

- [ ] Version and build numbers incremented monotonically.
- [ ] CI built the artifact from a tagged commit; archive retained with symbols.
- [ ] Tests, lint, and typechecks green; no quarantined failures unaccounted for.
- [ ] Privacy labels/Data Safety and permission declarations reviewed against actual behavior.
- [ ] Store metadata, screenshots, and review notes current.
- [ ] Rollout plan with percentages and go/no-go thresholds agreed.
- [ ] Crash reporting and performance monitoring active for the new version.
- [ ] Rollback/kill-switch plan documented and tested.
- [ ] On-call aware of the release window and monitoring channel.
- [ ] Post-release review scheduled; cleanup of flags and dead code after full rollout.

## Anti-Patterns

- Manual signing on a laptop as the only path to release.
- Rebuilding per track, so QA tested a different binary than production.
- Uploading `.apk` when the store expects `.aab` (or vice versa).
- Ignoring target API or page-size deadlines until uploads fail.
- 100% rollout immediately with no monitoring.
- Shipping OTA updates that change native behavior or violate store policy.
- No mapping/symbol upload, producing useless crash reports.
- Release without a rollback or kill-switch path.
- Treating store review as a formality and planning a launch date that depends on approval.
- Letting one person hold all credentials and knowledge.

## Cross-Links

- Security gates before shipping: [./08-security.md](./08-security.md)
- Performance gates: [./07-performance.md](./07-performance.md)
- Offline compatibility across versions: [./06-data-offline-sync.md](./06-data-offline-sync.md)
- Stack and build tooling: [./01-cross-platform-decision.md](./01-cross-platform-decision.md), [./04-react-native.md](./04-react-native.md)
- Platform release details: [./02-ios.md](./02-ios.md), [./03-android.md](./03-android.md)
