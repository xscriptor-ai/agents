# Security

OWASP MASVS-aligned mobile security: secure storage, transport, obfuscation, secrets, platform
integrity, and privacy for iOS and Android clients.

## Threat Model

Mobile clients are fully under the attacker's control: the binary can be decompiled, storage
inspected on a rooted/jailbroken device, traffic intercepted with a user-installed root CA, and
APIs called directly. Client-side checks raise cost; they never make an API safe.

Therefore:

- **The server enforces authorization.** Every endpoint validates the token, scopes, and object
  ownership. Client checks are UX, not security.
- **Assume secrets in the binary are public.** Obfuscation slows extraction; it does not prevent it.
- **Protect data by classification.** Credentials and health/payment data get hardware-backed
  storage and minimal retention; public catalog data does not need Fort Knox.
- **Log nothing sensitive.** Tokens, PII, and payload bodies stay out of logs, analytics, and
  crash breadcrumbs.

Reference framework: OWASP MASVS (verification standard), MASWE (weakness enumeration), and MASTG
(testing guide). Verify the current MASVS revision upstream; the v2 control groups are a good
checklist skeleton:

| Group | Focus |
|---|---|
| MASVS-STORAGE | Sensitive data at rest, backups, screenshots |
| MASVS-CRYPTO | Key management, algorithms, randomness |
| MASVS-AUTH | Authentication, session, biometrics |
| MASVS-NETWORK | TLS, pinning, cleartext |
| MASVS-PLATFORM | IPC, WebViews, deep links, permissions |
| MASVS-CODE | Platform usage, dependencies, update hygiene |
| MASVS-RESILIENCE | Tamper/integrity detection (defense in depth) |
| MASVS-PRIVACY | Data minimization, consent, telemetry |

## Secure Storage

| Data | iOS | Android |
|---|---|---|
| Tokens, keys | Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (or stricter) | Keystore-backed encryption; store ciphertext in DataStore/prefs |
| Small secrets needing biometric gate | Keychain access control with `SecAccessControl` | Keystore key with `setUserAuthenticationRequired(true)` |
| Structured local data (PII) | File protection class + SQLCipher/GRDB encryption | SQLCipher or `SQLiteDatabase` with support; encrypt sensitive columns |
| Cache/temp | Caches directory, excluded from backup | `cacheDir`, excluded from backup |
| Never | `UserDefaults`, plists, unencrypted files | `SharedPreferences`, plain files, external storage |

Notes:

- Android's `androidx.security:security-crypto` API (EncryptedSharedPreferences/EncryptedFile) was
  deprecated; do not start new code on it. Use Keystore directly or a maintained alternative, and
  verify the current recommendation upstream.
- Keychain items sync via iCloud if you choose a synchronizable accessibility class; for device-bound
  credentials use `ThisDeviceOnly` classes.
- Biometric prompts authenticate the user to unlock a key; they are not proof of identity to the
  server. Bind the unlocked secret to a server verification.
- Clear sensitive storage on logout, and mark views with `FLAG_SECURE` (Android) / avoid sensitive
  content in app switcher snapshots (iOS).

## Transport Security

- TLS 1.2+ everywhere, TLS 1.3 preferred; no cleartext exceptions in release.
  - Android: `networkSecurityConfig` with `cleartextTrafficPermitted="false"`; no user CA trust in
    release.
  - iOS: App Transport Security on; only scoped exceptions with justification.
- Certificate pinning: pin the leaf or intermediate public key (SPKI), always ship at least one
  backup pin, and have an update path before certificate expiry.
  - Pinning breaks when operations rotates certs without you; monitoring and a remote kill switch
    are mandatory if you pin.
  - Pinning does not stop a determined attacker on a compromised device; it raises interception cost.
- Do not disable hostname verification or accept all certificates, even in debug — use a debug
  pinning bypass with a release guard instead.
- Certificate transparency and platform trust stores give baseline protection without pinning; for
  most apps that is the right default.

## Authentication and Sessions

- OAuth 2.0/OIDC with PKCE for public clients; never ship a client secret in the app.
- Use platform browsers (`ASWebAuthenticationSession`/Custom Tabs) for web sign-in; embedded
  WebViews are discouraged and often blocked by providers.
- Short-lived access tokens plus rotating refresh tokens stored per secure storage rules.
- Refresh single-flight to avoid races; on refresh failure, sign out and clear local data.
- Biometrics unlock local credentials; the server still validates sessions.
- Logout must revoke server-side refresh tokens where supported, not just delete local state.
- Deep links: treat as untrusted input; never authorize a session from a link alone.

## Obfuscation and Reverse Engineering

- Android: R8 full mode with obfuscation; keep rules minimal and reviewed; upload the mapping file
  to crash reporting.
- iOS: Swift symbols are stripped in release; string obfuscation requires tooling and adds little
  against a motivated attacker. Prefer moving logic server-side.
- Avoid shipping API keys that grant privileges. Identify the client with Play Integrity / App
  Attest instead of a bundled secret.
- Anti-debugging and tamper checks are deterrents; combine with server-side anomaly detection rather
  than relying on them.

## Platform Integrity and Device Compromise

| Control | What it proves | Limits |
|---|---|---|
| Play Integrity API | App binary, device, and account verdicts | Attestation is probabilistic; server policy needed |
| App Attest (iOS) | Request comes from a genuine app instance on genuine hardware | Requires server assertion validation |
| Jailbreak/root detection | Device is likely modified | Bypassed on real threats; false positives on power users |
| Emulator detection | Environment heuristics | Developers and QA use emulators; never hard-block silently |

Rules:

- Treat all signals as risk scores combined server-side, not binary gates.
- Define policy per action: browsing may ignore root; payments and health data may require strong
  integrity and step-up authentication.
- Provide a support path for false positives; users on rooted devices are still customers.
- Never store the decision only on the device; the server re-evaluates.

## WebViews, IPC, and Deep Links

- Prefer native UI over WebViews for anything authenticated. If you must:
  - Disable JavaScript where possible; never expose native bridges to untrusted content.
  - Restrict navigation to an allowlist; block `file://`, `content://`, and arbitrary custom schemes
    from loaded pages.
  - Keep cookies out of the WebView for app sessions; use a separate auth flow.
- Deep links and app links:
  - Validate and canonicalize every parameter; never pass raw URLs into WebView loads or file paths.
  - Prefer verified App Links / Universal Links over custom schemes (other apps can claim schemes).
  - Avoid intent redirection: never proxy an Intent/URL to an exported component based on
    untrusted input.
- Exported Android components: require permissions or explicit intent filters; set `android:exported`
  precisely; validate all incoming data.
- iOS URL schemes and universal links: validate the host and path; do not auto-login from link data.

## Privacy and Permissions

- Request the minimum permissions, at the moment of use, with a rationale; handle denial and
  "don't ask again"/restricted states without blocking the app.
- iOS: purpose strings must be accurate; privacy manifests (`PrivacyInfo.xcprivacy`) declare data
  collection and required-reason APIs; App Privacy labels must match what you actually collect.
- Android: Data Safety form must match behavior; permission declarations in the manifest are
  visible; foreground service types must be justified.
- Third-party SDKs collect data you are responsible for; inventory them and keep the store forms
  accurate.
- Consent for tracking where required (ATT on iOS, regional rules); do not fingerprint as a
  fallback for denied tracking.
- Analytics events: no PII, no free-text user content, no tokens.

## Dependency and Supply Chain

- Pin versions and use lockfiles; review new dependencies for maintainership and permissions.
- Remove abandoned SDKs; a stale analytics or ad library is both a vulnerability and a store risk.
- Track SDK update deadlines (target API requirements, 16 KB page size alignment on Android, privacy
  manifest requirements on iOS) and verify current dates upstream.
- Reproducible builds and signed artifacts: verify checksums; build release artifacts only in CI.

## Testing

- Static: SAST for the app code, secret scanning in the repo, dependency scanning (SCA).
- Dynamic: proxy interception (mitmproxy/Proxyman), storage inspection on a rooted device, binary
  analysis, deep-link fuzzing.
- MASVS/MASTG test cases mapped to product risks; automate what is stable, do the rest pre-release.
- Server-side authorization tests are the highest-value security tests; client testing does not
  substitute.

## Anti-Patterns

- Secrets and API keys bundled in the app.
- Trusting a client-provided "isPremium" or "isAdmin" flag.
- Certificate pinning with no backup pin or rotation plan.
- Root detection that blocks paying users with no support path.
- Logging tokens, PII, or full responses.
- Custom crypto; rolling your own KDF or "encryption" scheme.
- Encrypting the database but leaving the key next to it.
- WebView bridges exposed to remote content.
- Backup enabled for token storage.
- Treating MASVS as a one-time audit rather than a recurring checklist.

## Checklist

- [ ] Token/credential storage uses Keychain/Keystore with strict accessibility.
- [ ] Cleartext disabled in release; pinning decision documented with backup pins and rollback.
- [ ] OAuth PKCE with platform browser; no client secrets in the binary.
- [ ] R8/obfuscation enabled; mapping upload automated.
- [ ] Integrity signals evaluated server-side per action, with false-positive support path.
- [ ] Deep links and exported components validate untrusted input.
- [ ] Privacy manifests/labels and Data Safety match actual collection.
- [ ] Dependency and secret scanning in CI.
- [ ] MASVS checklist reviewed for the release; findings tracked to closure.

## Cross-Links

- Storage and background details: [./06-data-offline-sync.md](./06-data-offline-sync.md)
- Platform code paths: [./02-ios.md](./02-ios.md), [./03-android.md](./03-android.md)
- Framework code paths: [./04-react-native.md](./04-react-native.md), [./05-flutter.md](./05-flutter.md)
- Performance cost of pinning/obfuscation: [./07-performance.md](./07-performance.md)
- Store privacy and integrity requirements: [./09-release-store-ci.md](./09-release-store-ci.md)
