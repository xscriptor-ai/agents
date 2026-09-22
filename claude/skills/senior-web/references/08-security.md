# Web Security

Browser-side security: CSP and Trusted Types, CORS, cookies, CSRF, XSS defenses, third-party
scripts, security headers, and supply-chain hygiene.

## Threat Model First

For every interface, enumerate: who sends data, who can read it, who can mutate it, and what the
browser trusts. The browser is a hostile execution environment: any script on the origin has full
access to DOM, storage, and authenticated requests to that origin. Most web vulnerabilities are
failures to keep attacker-controlled content from becoming code, or trusting the client with
authorization decisions.

Never trust: URL parameters, form fields, `localStorage` contents, postMessage data, third-party
API responses, or JWT claims you did not verify. Always enforce authorization server-side on every
request.

## XSS: Contexts and Defenses

XSS is injected markup/script execution. Defend in depth:

1. **Framework escaping** — modern frameworks escape interpolated text by default. Do not fight it.
2. **Avoid raw HTML sinks** — `innerHTML`, `dangerouslySetInnerHTML`, `v-html`, `insertAdjacentHTML`.
   If you need rich text, sanitize with a maintained library (DOMPurify or equivalent) on the server
   or before insertion, and keep it updated.
3. **Trusted Types** — enforce at runtime via CSP:

```
Content-Security-Policy:
  require-trusted-types-for 'script';
  trusted-types default dompurify;
```

Trusted Types turns DOM XSS sinks into runtime errors unless values pass a policy. Adopt
report-only first, fix sinks, then enforce. This is the strongest available defense for DOM-based
XSS.

4. **Output encoding by context** — HTML text, attribute, URL, CSS, and JS contexts need different
   encoding; templating engines handle it when you do not bypass them.
5. **URL handling** — validate scheme (`https:`, `mailto:`) before putting user data in `href` or
   `src`; block `javascript:` and `data:` where not needed.

## Content Security Policy

CSP is the primary mitigation for XSS and data exfiltration. Start report-only, iterate, then
enforce.

```
Content-Security-Policy:
  default-src 'self';
  script-src 'self' 'nonce-RANDOM' 'strict-dynamic';
  style-src 'self' 'unsafe-inline';
  img-src 'self' data: https://cdn.example.com;
  font-src 'self';
  connect-src 'self' https://api.example.com;
  frame-ancestors 'none';
  base-uri 'none';
  form-action 'self';
  object-src 'none';
  upgrade-insecure-requests;
  report-uri /csp-report; report-to csp-endpoint
```

Guidance:
- **Nonces** (per-response random) over hashes for server-rendered apps; `'strict-dynamic'` lets
  nonced scripts load further scripts so you can drop allowlists.
- **Never** ship `'unsafe-eval'`; avoid `'unsafe-inline'` in `script-src` entirely.
- `style-src 'unsafe-inline'` is a pragmatic compromise for many UI libraries; prefer nonces/hashes
  when feasible.
- Lock down `base-uri`, `form-action`, `object-src`, and `frame-ancestors` in every policy; these
  prevent entire attack classes.
- Use **report-to/report-uri** to catch violations before enforcement; monitor the reports.
- Meta-tag CSP is inferior to header CSP (no `frame-ancestors`, `report-uri`); use headers.
- CSP cannot stop all exfiltration (e.g. via allowed connect endpoints). Combine with
  `connect-src` restrictions and server-side validation.

## Security Headers Baseline

```
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
Content-Security-Policy: <see above>
Permissions-Policy: geolocation=(), camera=(), microphone=(), payment=(self)
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp   # only if you need crossOriginIsolated
frame-ancestors 'none' (via CSP)             # clickjacking
```

- HSTS after you are confident all subdomains are HTTPS; preload is effectively permanent.
- COOP/COEP enable `crossOriginIsolated` (SharedArrayBuffer, high-resolution timers) but break
  cross-origin embeds unless they opt in with CORP/CORS. Apply deliberately.
- `Permissions-Policy` disables powerful features you do not use, shrinking the attack surface.
- Set headers at the CDN/edge as well as the origin; origin-only headers can be bypassed on cached
  or error responses.

## Cookies

```
Set-Cookie: session=...; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=...; Domain=example.com
```

| Attribute | Rule |
|---|---|
| `HttpOnly` | Always for session/auth cookies; blocks JS theft via XSS |
| `Secure` | Always; cookies never travel over plain HTTP |
| `SameSite` | `Lax` default; `Strict` for sensitive actions; `None` only with `Secure` for genuine cross-site needs |
| `Path` | Tightest practical; `/` for session cookies is common |
| `Max-Age`/`Expires` | Session cookies for auth; long-lived only for non-sensitive prefs |
| Prefixes | `__Host-` requires Secure + Path=/ + no Domain; `__Secure-` requires Secure |

- Keep tokens out of `localStorage`; prefer `HttpOnly` cookies for sessions, with CSRF protection.
- Rotate session identifiers on login and privilege change.
- Consider partitioned cookies (`Partitioned`, CHIPS) for embedded cross-site contexts; unsupported
  browsers ignore them, so test your embed flow.
- Clear cookies server-side on logout (`Max-Age=0`) and invalidate the session record.

## CSRF

CSRF abuses ambient credentials (cookies) to make authenticated requests from another origin.

Defenses, in order of strength:
1. **SameSite=Lax/Strict** on session cookies kills the common form-post and fetch vectors.
2. **Origin/Referer validation** on state-changing requests; reject mismatches.
3. **Anti-CSRF tokens** — synchronizer token per session/form, or signed double-submit cookie.
   Verify on every unsafe method (`POST`, `PUT`, `PATCH`, `DELETE`).
4. **Custom header requirement** (`X-Requested-With` or a CSRF header) plus CORS makes cross-origin
   requests non-simple and therefore preflighted — useful defense in depth, not sufficient alone.
5. **Re-authentication** for sensitive operations (password change, payment, email change).

Anti-patterns: relying only on `Origin` header (proxies can strip it), GET requests that mutate
state, and CSRF tokens that are never rotated or tied to the session.

## CORS

CORS is a browser-enforced *response reading* policy, not a server-side security boundary. Requests
still hit your server.

- Allowlist exact origins; never reflect arbitrary `Origin` values with `Access-Control-Allow-Credentials: true`.
- Wildcards (`*`) are invalid with credentials.
- Preflight (`OPTIONS`) must return `Access-Control-Allow-Methods` and `-Headers` matching actual
  use; cache with `Access-Control-Max-Age`.
- `Access-Control-Allow-Credentials: true` means cookies flow; combine with CSRF defenses.
- Do not expose internal APIs to `*`; scope read access per resource and require authz.
- WebSocket connections are not subject to CORS; validate the `Origin` header server-side.

## Third-Party Scripts and Embeds

Third-party scripts run with full page privileges. Every tag is a potential supply-chain compromise,
performance problem, and privacy leak.

- **Minimize**: prefer server-side integrations over client tags; negotiate contracts with vendors
  who require JS.
- **SRI** for fixed-version assets: `integrity="sha384-..." crossorigin="anonymous"`. Note SRI does
  not work with dynamically generated scripts; vendors must support versioned URLs.
- **CSP** to constrain allowed script origins; `strict-dynamic` plus nonces for your own code, and
  avoid broad allowlists of tag managers.
- **Sandboxing**: load untrusted widgets in `<iframe sandbox="allow-scripts ...">` on a separate
  origin; never `allow-scripts allow-same-origin` for untrusted content.
- **Iframes**: set `allow`, `referrerpolicy`, `loading="lazy"`, and CSP `frame-src`/`frame-ancestors`.
- **Audit** tags quarterly: remove dead vendors, check data flows, verify consent gating.

## postMessage and Cross-Window Communication

- Always specify `targetOrigin` when posting; never `"*"` for sensitive data.
- Always validate `event.origin` (and `event.source` where possible) before acting on messages.
- Treat message payloads as untrusted: validate shape and values.
- Do not use postMessage to pass tokens between origins you do not control.

## Authentication and Session Surfaces

- Password flows: use `autocomplete` correctly, allow paste, support password managers, rate-limit
  attempts, check breached-password lists server-side.
- Prefer **passkeys/WebAuthn** for new consumer and workforce apps; they resist phishing. Provide
  recovery paths.
- OAuth/OIDC: use Authorization Code + PKCE; validate `state`/`nonce`; never put tokens in URLs;
  store refresh tokens server-side where possible.
- JWT: verify signature, `iss`, `aud`, `exp`, `nbf`; treat claims as untrusted for authorization
  unless freshly checked server-side; keep lifetimes short.
- Session fixation: rotate IDs on login; logout must invalidate server-side, not just clear cookies.
- Rate-limit login, registration, password reset, and OTP endpoints; use generic responses to avoid
  account enumeration.

## Supply Chain

- Commit lockfiles; build with `npm ci`/`pnpm install --frozen-lockfile`; review lockfile diffs.
- Pin GitHub Actions to commit SHAs; enable Dependabot/Renovate with grouping and CI gating.
- Verify provenance/attestations where registries support them; prefer packages with reproducible
  builds.
- Generate an SBOM; monitor advisories and have a patch SLA by severity.
- `postinstall` scripts execute arbitrary code: use `--ignore-scripts` where possible or allowlist
  packages needing them.
- Do not load remote code at runtime (remote script URLs, dynamic `import()` of arbitrary origins).

## Anti-Patterns

- `innerHTML` with server data "because it is trusted" (until a CMS editor is compromised).
- CSP with `'unsafe-inline' 'unsafe-eval'` — decorative rather than protective.
- Session tokens in `localStorage`.
- `Access-Control-Allow-Origin: *` with credentials, or reflecting `Origin`.
- CSRF token in a cookie only, with no double-submit verification.
- Secret API keys in client bundles; anything shipped to a browser is public.
- `target="_blank"` without `rel="noopener noreferrer"`.
- Disabling TLS verification or mixed-content allowances in production builds.
- Client-side authorization ("hide the button") without server enforcement.

## Checklist

- [ ] CSP enforced with nonces, no `unsafe-inline`/`unsafe-eval` in `script-src`; reports monitored.
- [ ] Trusted Types report-only adopted, then enforced for DOM sinks.
- [ ] Session cookies `HttpOnly; Secure; SameSite=Lax` (or stricter) with `__Host-` prefix.
- [ ] CSRF protection on all unsafe methods; Origin checked.
- [ ] CORS allowlists exact origins; credentials only with explicit origins.
- [ ] All security headers set and verified on cached and error responses.
- [ ] Third-party scripts SRI-pinned, sandboxed, and audited.
- [ ] Secrets never in client bundles; authz enforced server-side per request.
- [ ] Dependencies locked, scanned, and patchable within a defined SLA.
