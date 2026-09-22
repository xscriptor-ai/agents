# Security

> Scope: npm supply chain, XSS and Trusted Types, CSP, secrets, SSRF, Node runtime hardening, and dependency policy for TypeScript projects.

Version floors (verify upstream; treat as minimums):

| Control | Availability | Notes |
| --- | --- | --- |
| npm provenance | registry feature | `npm publish --provenance` |
| npm trusted publishing | registry feature | OIDC, no long-lived token |
| `npm audit signatures` | npm 8.7+ | registry signature verification |
| Trusted Types | Chromium/Edge | Firefox/Safari partial; feature-detect |
| Node permission model | Node 22/24 | `--permission`, verify stability |
| `require(esm)` | Node 22.12+/23+ | reduces risky interop shims |

## 1. npm supply chain

The npm ecosystem is the largest attack surface in a TypeScript project. Treat package installation as executing untrusted code.

Baseline controls:

- Commit one lockfile per repo and install with a frozen lockfile (`pnpm install --frozen-lockfile`, `npm ci`). Never install without a lockfile in CI.
- Disable lifecycle scripts for untrusted contexts: `npm ci --ignore-scripts` (or pnpm's `onlyBuiltDependencies` allowlist). Re-enable per package only when needed and reviewed.
- Publish with provenance and/or trusted publishing (OIDC) so consumers can verify where artifacts came from; never keep long-lived publish tokens in CI variables.
- Run `npm audit`/`pnpm audit` and `npm audit signatures` in CI. Signatures verify registry transport, not package intent.
- Use a minimum release age / cooldown for automated updates (for example 3-7 days) so compromised releases are caught by the community before you install them.
- Review lockfile diffs in PRs: unexpected transitive additions, `postinstall` hooks, native gyp builds, and typosquats are the signals.
- Prefer packages with provenance, maintained release cadence, few transitive deps, and repository verification. Popularity is not trust.
- For high-risk environments, install through a proxy/registry mirror that enforces policy (Verdaccio, Artifactory, Socket-style scanning) and pin allowlists.

Known attack patterns to recognize: typosquats (`cross-env` lookalikes), dependency confusion (internal names not scoped), maintainer account takeover (new maintainer + immediate patch release), protestware, obfuscated postinstall payloads, and transitive packages that fetch at install time.

## 2. Dependency policy

| Decision | Policy |
| --- | --- |
| Adding a dependency | check size, maintenance, last release, transitive count, license |
| Update cadence | Renovate/Dependabot weekly with cooldown and grouped PRs |
| Security updates | fast-track, test, ship within the SLA |
| Major upgrades | scheduled, one per PR, with migration notes |
| Abandoned packages | vendor, fork under an owned scope, or replace |
| Internal packages | scoped names, registry allowlist, no typo surface |
| Dev-only tools | still audited; they run with your credentials |

Track a software bill of materials (SBOM) for shipped artifacts where compliance requires it (`npm sbom`, CycloneDX tooling).

## 3. XSS and Trusted Types

Rules:

- React/Vue/Svelte escape interpolated content by default; the danger is bypass APIs: `dangerouslySetInnerHTML`, `v-html`, `{@html}`, `innerHTML`, `insertAdjacentHTML`, `document.write`.
- Sanitize on the server when generating HTML, and again at render when the source is untrusted. Use a maintained sanitizer (DOMPurify) with an explicit allowlist of tags/attributes.
- Never interpolate URLs into `href`/`src` without scheme validation; `javascript:` and `data:` payloads are XSS.
- Prefer text content APIs for user data: `textContent`, not `innerHTML`.
- Trusted Types enforce this at the platform level: set a CSP `require-trusted-types-for 'script'` and create policies instead of strings. Feature-detect and keep sanitization as the fallback for engines without support.

```ts
const policy = window.trustedTypes?.createPolicy("app", {
  createHTML: (dirty) => DOMPurify.sanitize(dirty, { ALLOWED_TAGS: ["b", "i", "a"], ALLOWED_ATTR: ["href"] }),
});
el.innerHTML = policy ? policy.createHTML(userText) : DOMPurify.sanitize(userText);
```

Server-side rendering must apply the same sanitization; trusting "it comes from our API" fails when user content reached the API.

## 4. Content Security Policy

CSP is the second line of defense after correct escaping.

- Start with `Content-Security-Policy-Report-Only` plus a report endpoint; promote to enforcing once reports are clean.
- Prefer nonces or hashes over `unsafe-inline`. Frameworks can emit per-request nonces for their bootstrap scripts.
- `default-src 'self'; script-src 'self' 'nonce-<random>'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'` is a reasonable baseline.
- Add `strict-dynamic` when using modern bundlers and nonces; keep a host allowlist fallback for older browsers.
- Set `require-trusted-types-for 'script'` and `trusted-types` to the policy names you actually use.
- Keep the policy in middleware/headers so it applies to every response, including errors.

Other headers that belong with CSP: `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` minimizing features, HSTS with a long max-age once HTTPS is guaranteed, and `Cross-Origin-Opener-Policy`/`Cross-Origin-Resource-Policy` where isolation is needed.

## 5. Secrets

- Secrets live in a manager (Vault, AWS/GCP secrets, Doppler) or platform secret stores; never in the repo, images, or client bundles.
- Client-visible prefixes (`NEXT_PUBLIC_`, `VITE_`, `PUBLIC_`) are permanent disclosure. Document this and review any use.
- `.env*` files are git-ignored; `.env.example` documents keys without values. CI has no `.env`.
- Run secret scanning (gitleaks, TruffleHog) as a pre-commit hook and in CI, including history on first adoption.
- Rotate on any suspected exposure and on staff changes; prefer short-lived credentials (OIDC) over static cloud keys.
- Redact secrets in logs, error reports, and traces; configure the SDK scrubbers. Never log full request headers.

## 6. SSRF

Any server-side fetch of a user-controlled URL is an SSRF risk, including webhooks, image proxies, and URL previews.

Controls:

- Allowlist destination hosts (or public suffixes) rather than blocklisting `localhost`/private ranges; parse the URL and compare the resolved host after DNS.
- Resolve DNS yourself and connect to the validated IP, or use a proxy that enforces egress policy; this mitigates DNS rebinding.
- Block cloud metadata endpoints (`169.254.169.254`, equivalent v6) and link-local ranges.
- Enforce scheme (`https`), port allowlists, redirect limits, timeouts, and response size caps.
- Do not send credentials or internal headers to user-supplied destinations; strip auth on redirects.
- Prefer platform egress proxies (Cloudflare, AWS) when available; treat the app-level check as defense in depth.

```ts
const allowed = new Set(["api.stripe.com", "hooks.example.com"]);
const url = new URL(userInput);
if (url.protocol !== "https:" || !allowed.has(url.hostname)) throw new Error("blocked destination");
const res = await fetch(url, { redirect: "manual", signal: AbortSignal.timeout(5000) });
```

## 7. Node runtime hardening

| Risk | Control |
| --- | --- |
| Prototype pollution | validate/parse input; prefer `Object.create(null)` for maps; consider `--disable-proto=throw`; avoid recursive merge of untrusted objects |
| `eval`/`new Function` | banned by lint; no template-compiled user code |
| Command injection | `execFile`/`spawn` with argument arrays; never string-concatenated shell |
| Path traversal | resolve and verify the path stays under the intended root; reject `..`, absolute paths, symlink escapes |
| ReDoS | avoid unbounded regex on user input; prefer parsers or linear-time patterns; cap input length |
| JWT confusion | fix the algorithm allowlist; reject `none`; verify issuer/audience/expiry |
| Timing attacks | `crypto.timingSafeEqual` for token/key comparisons |
| Weak RNG | `crypto.randomUUID`/`randomBytes`, never `Math.random` for secrets |
| Unhandled rejections | fail fast on `unhandledRejection` in production processes |
| Excess privileges | run unprivileged; use the Node permission model (`--permission --allow-...`) or containers with read-only FS |
| Dependency native code | review gyp builds; prefer prebuilt, provenance-signed packages |

Cryptography defaults: use WebCrypto (`crypto.subtle`) or `node:crypto` primitives (AES-GCM, chacha20-poly1305, HKDF, Ed25519); never invent schemes; set TLS verification on (no `rejectUnauthorized: false`).

## 8. Web request security

- CSRF: SameSite cookies as the base case; add origin checks and per-session tokens for state-changing form posts. Server actions in frameworks need the same care.
- CORS: allowlist origins explicitly; never reflect arbitrary origins with credentials; keep preflight caching short.
- Cookies: `httpOnly`, `Secure`, `SameSite=Lax/Strict`, `Path=/`, scoped `Domain`, and `__Host-` prefix where applicable.
- Rate limit authentication, password reset, and expensive endpoints; return uniform errors to avoid user enumeration.
- Validate and normalize every request field per [06-backend-node](./06-backend-node.md); size-limit bodies and JSON depth.
- Log security-relevant events (login, permission change, key rotation) with actor and result, without secrets.

## 9. Secure defaults for new services

Apply these before writing feature code; retrofitting is where mistakes happen.

| Default | Setting |
| --- | --- |
| Error responses | generic message + request id; no stack traces, SQL, or paths |
| Source maps | uploaded to the error tracker, never served publicly |
| Debug endpoints | disabled in production; behind auth if they must exist |
| GraphQL | introspection off in production; depth and cost limits on |
| File uploads | type/size limits, store outside webroot, serve via signed URLs |
| Webhooks out | signed (HMAC) with replay protection; verify on ingress |
| Webhooks in | verify signatures before parsing business logic |
| Admin surfaces | separate auth tenant, IP allowlist where possible |
| Default credentials | none exist; first-run requires a setup token |
| Verbose banners | `x-powered-by` removed; version strings not exposed |

## 10. Incident response quick steps

1. Contain: revoke tokens/keys, disable the affected endpoint, roll back the release.
2. Preserve: snapshot logs, images, and the exact deployed lockfile before cleanup.
3. Assess: determine data accessed, users affected, and whether credentials or PII were exposed.
4. Eradicate: patch the root cause, rotate every credential the attacker could have read, and re-scan dependencies.
5. Communicate: notify according to policy and regulation; keep a public status note if customers are affected.
6. Learn: add a regression test and a CI gate for the class of issue, not just the instance.

## Anti-patterns

| Anti-pattern | Risk | Fix |
| --- | --- | --- |
| `dangerouslySetInnerHTML` with user data | XSS | sanitize + Trusted Types |
| Secrets in `NEXT_PUBLIC_`/`VITE_` env | permanent disclosure | server-only access |
| `npm install` without lockfile | supply-chain drift | frozen lockfile |
| `--ignore-scripts` only locally | inconsistent risk | allowlist built dependencies |
| Blocklist-based SSRF filter | bypass via DNS/redirects | allowlist + resolve + recheck |
| `exec("cmd " + input)` | command injection | `execFile` with args array |
| `jwt.verify` without algorithms | alg confusion | pin algorithms |
| Disabling TLS verification in prod code | MITM | fix certs |

## Checklist

- [ ] Lockfile committed; CI installs frozen; lifecycle scripts allowlisted.
- [ ] Provenance/trusted publishing for packages you publish; audit + signatures in CI.
- [ ] Update cooldown enabled; lockfile diffs reviewed.
- [ ] All HTML injection points sanitized; Trusted Types where supported.
- [ ] CSP enforced with nonces/hashes; report-only rollout done first.
- [ ] Secrets in a manager; client prefixes audited; scanners in pre-commit and CI.
- [ ] Outbound fetches allowlisted, redirect-limited, timeout-bounded.
- [ ] Prototype pollution, injection, traversal, and ReDoS reviewed in code paths that touch input.
- [ ] Cookies httpOnly/Secure/SameSite; CSRF and CORS policies explicit.
- [ ] Runtime runs with least privilege; unhandled rejections crash loudly.

Related: [06-backend-node](./06-backend-node.md) for request handling, [08-quality-tooling](./08-quality-tooling.md) for enforcing these rules in CI, [02-modules-build](./02-modules-build.md) for publishing safely.
