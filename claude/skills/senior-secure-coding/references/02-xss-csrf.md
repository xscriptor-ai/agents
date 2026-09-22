# XSS and CSRF

Scope: preventing script execution and cross-site request forgery in browser-facing code through context-aware output encoding, sink discipline, Trusted Types, CSP, cookies, CSRF tokens, and CORS.

## Threat Model

The browser is a hostile execution environment: any script running on the origin has full access to
the DOM, storage, and authenticated requests to that origin. XSS is the failure to keep
attacker-controlled content from becoming code; CSRF is the failure to distinguish a request the
user intended from one another site caused the browser to send. Both are authorization problems at
heart, so no client-side check is ever sufficient. For platform-level browser security depth, see
[../../web/SKILL.md](../../web/SKILL.md).

Never trust: URL parameters, form fields, `localStorage`, `postMessage` payloads, DOM text,
third-party API responses, or unverified JWT claims. Always enforce authorization server-side on
every request.

## Output Encoding by Context

Encode at the point of output, with the encoder for that exact context. One value often needs
several encodings in one document (for example a URL inside an HTML attribute inside JavaScript).

| Context | Encoding | Notes |
|---|---|---|
| HTML text | HTML entity encoding (`& < > " '`) | Framework templates do this by default |
| HTML attribute | Attribute encoding plus quoted values | Always quote; never write unquoted attributes |
| URL / query parameter | Percent-encoding | `encodeURIComponent`-equivalent; validate scheme |
| JavaScript string | Script-safe encoding (`\uXXXX`, JSON serialize) | Never inject into script blocks if avoidable |
| CSS | Validate against a value pattern; avoid `expression`/`url()` with user data | CSS injection can exfiltrate data |
| JSON response | Proper JSON serializer with correct `Content-Type` | Avoid HTML sniffing with `nosniff` |
| XML | XML entity encoding | Avoid building XML by concatenation |
| Shell/SQL/LDAP | Parameterization, not encoding | See [./01-injection.md](./01-injection.md) |
| CSV | Quote fields; neutralize leading `= + - @` | Prevents spreadsheet formula injection |
| HTTP headers | Strip/encode CR/LF | Prevents response splitting and header forgery |

Framework auto-escaping is the primary defense; do not fight it. Explicitly unescaped output is
where bugs concentrate.

## Dangerous Sinks

| Sink | Language / framework | Safe alternative |
|---|---|---|
| `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `document.write` | DOM | `textContent`, `createElement`, `setAttribute` |
| `dangerouslySetInnerHTML` | React | Render text; sanitize if HTML is required |
| `v-html` | Vue | Interpolation; sanitize for rich text |
| `[innerHTML]`, `bypassSecurityTrustHtml` | Angular | Standard binding; avoid bypass APIs |
| `{@html ...}` | Svelte | Text interpolation |
| `eval`, `new Function`, string `setTimeout` | JS | Parse data, never execute it |
| jQuery `.html()`, `.append()` with strings | jQuery | `.text()`, DOM nodes |
| `element.setAttribute("onclick", ...)` | DOM | `addEventListener` |
| `src`/`href` with user data | DOM | Validate scheme (`https:`, `mailto:`); block `javascript:`, `data:` |
| WebView `loadDataWithBaseURL` / similar | Mobile | Escape or load from trusted origin |

DOM XSS sources include `location`, `document.referrer`, `window.name`, `postMessage` events, and
storage. Trace them to sinks; frameworks do not protect DOM flows the same way they protect
server-rendered templates.

## Rich Text and Sanitization

If the product requires HTML from users:

- Sanitize with a maintained allowlist library (DOMPurify or equivalent) and pin it; sanitizer
  bypasses are a recurring CVE class.
- Prefer sanitizing on the server when content is rendered server-side, or sanitize at the last
  step before insertion in the client; do not trust previously-sanitized storage blindly.
- Allowlist tags and attributes; drop `script`, `style`, `iframe`, event handlers, and `javascript:`
  URLs. Consider `rel="noopener noreferrer"` on user links and `target` restrictions.
- Keep a CSP as the backstop because sanitizers will occasionally fail.

## Trusted Types

Trusted Types turns DOM XSS sinks into runtime errors unless the value passes a policy. It is the
strongest available defense for DOM-based XSS in Chromium-based browsers and should be adopted with
a fallback report-only phase.

```
Content-Security-Policy:
  require-trusted-types-for 'script';
  trusted-types default dompurify;
```

- Roll out in report-only first, collect violations, fix sinks, then enforce.
- Define narrow policies; do not create a passthrough policy (`value => value`) that nullifies the
  protection.
- Use the DOMPurify adapter policy rather than hand-rolled HTML building.
- Treat `trusted-types` enforcement as progressive enhancement; other engines ignore the directive.
  Verify current browser support upstream before making it a hard requirement.

## Content Security Policy

CSP is defense in depth and the main mitigation for exfiltration via injected script. Start
report-only, iterate, enforce. For the full browser treatment see
[../../web/SKILL.md](../../web/SKILL.md).

```
Content-Security-Policy:
  default-src 'self';
  script-src 'self' 'nonce-RANDOM' 'strict-dynamic';
  style-src 'self';
  img-src 'self' data: https://cdn.example.com;
  font-src 'self';
  connect-src 'self' https://api.example.com;
  frame-ancestors 'none';
  base-uri 'none';
  form-action 'self';
  object-src 'none';
  upgrade-insecure-requests;
  report-to csp-endpoint
```

- Prefer per-response nonces (or hashes for static inline) over allowlists; `'strict-dynamic'`
  removes the need to enumerate script hosts.
- Never ship `'unsafe-eval'`; avoid `'unsafe-inline'` in `script-src`. If inline styles are
  unavoidable during migration, isolate them in `style-src` and plan removal.
- Always set `base-uri`, `form-action`, `object-src`, and `frame-ancestors`; they close entire
  attack classes.
- Use `report-to` (with `Report-To`/`Reporting-Endpoints`) to collect violations before enforcing.
- CSP does not stop exfiltration to an allowed endpoint; restrict `connect-src` and validate data
  server-side.

## Security Headers Baseline

```
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
Content-Security-Policy: <see above>
Permissions-Policy: geolocation=(), camera=(), microphone=(), payment=(self)
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp   # only when crossOriginIsolated is needed
```

HSTS preload is effectively permanent; confirm every subdomain is HTTPS first. COOP/COEP enable
`crossOriginIsolated` but break cross-origin embeds unless they opt in. Set headers at the edge as
well as the origin so cached and error responses cannot omit them.

## Cookies

```
Set-Cookie: __Host-session=...; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=...
```

| Attribute | Rule |
|---|---|
| `HttpOnly` | Always for session/auth cookies; blocks theft via XSS |
| `Secure` | Always; never send auth cookies over plain HTTP |
| `SameSite` | `Lax` default; `Strict` for sensitive flows; `None` only with `Secure` for genuine cross-site needs |
| `Path` | Tightest practical; session cookies commonly `/` |
| `Max-Age`/`Expires` | Session cookies for auth; long-lived only for non-sensitive preferences |
| Prefix | `__Host-` for session cookies (requires `Secure`, `Path=/`, no `Domain`); `__Secure-` otherwise |

- Keep tokens out of `localStorage`/`sessionStorage`; prefer `HttpOnly` cookies plus CSRF defense.
- Rotate the session identifier on login, logout, and privilege change; invalidate server-side.
- Consider `Partitioned` (CHIPS) only for real embedded cross-site contexts; unsupported browsers
  ignore it, so test the embed flow.
- Clear cookies server-side on logout (`Max-Age=0`) and delete the session record.

## CSRF

CSRF exists wherever the browser attaches credentials automatically (cookies, HTTP auth, mTLS,
IP-based auth). Token-based APIs with `Authorization` headers are naturally resistant if tokens are
not also accepted from cookies.

| Defense | Strength | Notes |
|---|---|---|
| Synchronizer token | Strong | Per-session or per-request token, compared server-side, tied to the session |
| Double-submit cookie | Medium | Only if the cookie is signed/HMACed; naive double-submit is bypassable via subdomains |
| `SameSite=Lax`/`Strict` | Strong baseline | Not all flows tolerate `Strict`; `None` removes the protection |
| Origin/Referer check | Good secondary | Compare to allowlist; fail closed when absent on state-changing requests |
| Fetch Metadata (`Sec-Fetch-Site`, `Sec-Fetch-Mode`) | Good secondary | Reject `cross-site` on non-GET APIs |
| Custom header requirement | Good for SPAs | Forces preflight; pairs with CORS |
| Re-authentication / step-up | Strong for sensitive actions | Password change, email change, payments, key management |

Implementation rules:

- Protect every state-changing method (`POST`, `PUT`, `PATCH`, `DELETE`) and state-changing GETs
  (which should not exist).
- Bind the token to the authenticated session, not just to the browser; rotate on login.
- Keep tokens out of URLs, logs, and `Referer` leakage; put them in a header or form field.
- Login and logout endpoints need CSRF protection too (login CSRF).
- JSON APIs are not automatically safe: a cross-site HTML form can send `text/plain` bodies that
  some parsers accept; enforce `Content-Type` and prefer token or header requirements.
- Do not disable CSRF middleware for "internal" routes; if a route is truly token-authenticated,
  document why it is exempt and test the exemption.

## CORS Interactions

CORS controls who may read responses, not who may send requests; it is not CSRF protection.

| Misconfiguration | Risk | Fix |
|---|---|---|
| `Access-Control-Allow-Origin: *` with credentials | Browsers block it, but developers often work around it | Never; use explicit origin allowlist |
| Reflecting the `Origin` header | Any site reads authenticated data | Compare against a static allowlist |
| `null` origin allowed | Sandboxed iframes and `data:` URIs bypass | Reject `null` unless a documented need |
| Partial origin matching (`endsWith("example.com")`) | `evil-example.com` passes | Exact string match after parsing |
| `Access-Control-Allow-Credentials: true` on public APIs | Widens impact of XSS/CSRF | Only where credentials are truly needed |
| Long `Access-Control-Max-Age` with broad methods | Stale permissive policy | Keep short; re-evaluate on change |
| Missing `Vary: Origin` | Cache serves one origin's policy to another | Always set when reflecting origin |

Design rules: preflight is a server-side authorization checkpoint, but browsers only preflight
non-simple requests; treat preflight as defense in depth, not control. Keep the API origin separate
from the app origin, and be explicit about which origins may use credentials.

## Tests and Verification

- Unit/integration tests: inject `<script>`, `<img onerror>`, `javascript:` URLs, `</script>` and
  assert the output is inert in the rendered context.
- Use browser automation with a CSP report collector to catch policy violations in CI.
- Test cookie flags and `Set-Cookie` output in integration tests; assert `__Host-` usage.
- Test CSRF: state-changing request without token, with a foreign origin, and with `SameSite=None`
  cookies must fail; assert exemptions are explicitly listed.
- Test CORS with a hostile `Origin` and with `null`; assert the response omits the CORS headers.

## Anti-Patterns

- Writing a single `escapeHtml()` and reusing it in attributes, URLs, and JavaScript contexts.
- Sanitizing on input and assuming the stored value is safe forever.
- Allowing `javascript:` and `data:` schemes in user-controlled links.
- Building HTML strings in JavaScript and inserting them with `innerHTML`.
- Treating CSP as an alternative to encoding instead of a backstop.
- Using `SameSite=None` to fix an embed and silently reopening CSRF.
- Reflecting `Origin` into CORS headers "so the frontend works".
- `Access-Control-Allow-Credentials: true` with a wildcard or permissive origin list.

## Checklist

- [ ] Every output context uses the matching encoder; no unescaped interpolations anywhere.
- [ ] Dangerous sinks are absent or fed only sanitized, allowlisted HTML.
- [ ] Trusted Types (report-only, then enforced) and a nonce-based CSP are deployed.
- [ ] Security headers and cookie attributes are set at origin and edge; tests assert them.
- [ ] CSRF protection covers all state-changing routes, including login/logout; exemptions documented.
- [ ] CORS uses an exact origin allowlist with `Vary: Origin`; credentials only where required.
- [ ] Session identifiers rotate on authentication and privilege changes.
- [ ] Regression tests include XSS payloads, cookie flag assertions, and hostile-origin requests.
