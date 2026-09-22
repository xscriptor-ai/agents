# API Authentication and Authorization

OAuth 2.1, OIDC, scopes and audiences, token lifetimes and revocation, DPoP, mTLS, API keys,
rate limiting as an access control, and multi-tenancy.

## Choosing a Mechanism

| Caller | Mechanism | Notes |
|---|---|---|
| Browser SPA, mobile app (user present) | OAuth 2.1 authorization code + PKCE; OIDC for identity | BFF pattern preferred for browsers; never keep refresh tokens in JS |
| Service-to-service (no user) | OAuth 2.1 client credentials, or mTLS/private_key_jwt | Prefer sender-constrained tokens |
| Third-party integration (public client) | OAuth 2.1 code + PKCE, consent, scopes | Redirect URI allow-list, exact match |
| Partner server | OAuth 2.1 + scopes, optional mTLS/DPoP | Resource indicators for audience binding |
| Simple internal tooling | API key, per-key scoped and rate limited | Hashed at rest, rotatable, never in URLs |
| Legacy client with no OAuth | Edge session or signed requests | Record as migration debt with a sunset date |

Never mix: one endpoint should not accept a bearer token *and* an API key *and* a session
cookie. Declare the accepted schemes in OpenAPI `securitySchemes` and enforce exactly those.

## OAuth 2.1

OAuth 2.1 consolidates the OAuth 2.0 security best current practice into the core spec. Design
against 2.1, not 2.0.

- **PKCE is mandatory** for all clients, including confidential ones (S256, never `plain`).
- **Implicit and password grants are removed.** Use authorization code + PKCE; use
  client credentials for machine identities.
- **Exact redirect URI matching**, no wildcard subdomains, no fragments in redirect URIs.
- **`state` is required** for browser-based flows (CSRF binding) even with PKCE.
- **Public clients** (SPAs, mobile) cannot hold secrets; do not issue them one. Use the BFF
  pattern (server-side session) for browser apps as the default recommendation.
- **Refresh token rotation** with reuse detection: a reused rotated refresh token invalidates
  the family and forces re-authentication.
- **Resource indicators (RFC 8707)**: clients pass the target resource so the authorization
  server can mint audience-bound tokens and prevent token replay across APIs.
- **Sender-constrained tokens**: prefer DPoP (RFC 9449) or mTLS-bound tokens (RFC 8705) over
  plain bearer tokens for high-value scopes.
- **Token storage**: server-side sessions or secure storage; never `localStorage` for refresh
  tokens. Mobile apps use the OS keychain/keystore.
- **Redirect handling in native apps**: custom URI schemes or claimed HTTPS links, with PKCE;
  no embedded webviews for the authorization endpoint.

**Anti-patterns**

- Long-lived access tokens "to reduce latency".
- Refresh tokens that never rotate or are not invalidated on reuse.
- Accepting tokens from any issuer the resource server happens to trust.
- Passing tokens in query strings (they leak in logs and referrers).

## OpenID Connect

Use OIDC for user identity; keep OAuth for authorization.

- **Discovery** (`/.well-known/openid-configuration`) and **JWKS** (`jwks_uri`) drive validation.
  Cache JWKS with a TTL and refresh on unknown `kid`; never fetch JWKS per request.
- **Validate every ID token**: signature (RS256/ES256 as advertised), `iss` exact match, `aud`
  contains the client id, `exp`/`iat`/`nbf` with a small clock skew (for example 60 s), and
  `nonce` for browser flows. `azp` must match when multiple audiences exist.
- **Do not use ID tokens as API access tokens.** The ID token is for the client; the access
  token is for the resource server, with its own audience.
- **Claims are hints until verified**: do not authorize on `email` alone; use the stable
  `sub` subject and map it to a local principal.
- **Logout**: implement RP-initiated logout for browser apps; access tokens may remain valid
  until expiry, so pair with short lifetimes and revocation where it matters.
- **Account linking**: key on issuer + subject (`iss`+`sub`), never email, for identity.

## Scopes and Audiences

- **Scopes express capabilities, not roles.** Prefer `orders:read`, `orders:write`,
  `refunds:create` over `admin`, `user`.
- **Declare scopes per operation in the contract** (OpenAPI `security` per operation, proto
  service config or annotations, GraphQL field policy). Reviewers can then see required
  permissions in the diff.
- **Least privilege**: default-deny; a token with no matching scope gets 403 with
  `code: SCOPE_REQUIRED` (see [errors](./06-errors.md)).
- **Audience every token**: `aud` must identify this API (single resource). Resource servers
  reject tokens issued for another service, even in the same trust domain. Use resource
  indicators to request narrow audiences.
- **Do not put authorization data in scopes that changes often** (tenant ids, resource ids);
  scopes are coarse and rarely revoked mid-token. Check dynamic permissions at request time.
- **Group/role scopes** (`roles:admin`) are a bottleneck; map IdP groups to local roles at
  token exchange or session creation instead.
- **Scope explosion**: keep the catalog under a few dozen; if you need more, your resources
  need a policy layer (OpenFGA/SpiceDB/Cedar-style) with relationship-based checks.

## Token Lifetimes and Revocation

| Token | Recommended lifetime | Notes |
|---|---|---|
| Access token | 5-60 minutes | Shorter for sensitive scopes; supports fast revocation via expiry |
| Refresh token | Days to months, rotated each use | Rotate + reuse detection; bind to client and device |
| ID token | Minutes | Usually unused after login; do not call APIs with it |
| API key | 90-365 days with rotation | Per-key revocation; scan for leaked keys |
| mTLS certificate | 1-90 days (automate renewal) | Short-lived certs beat CRL/OCSP complexity |
| DPoP proof | 1-5 minutes `iat` window | Replay-protected by `jti` cache |

- **JWT vs introspection**: self-contained JWTs scale statelessly but cannot be revoked before
  expiry. `introspection` (RFC 7662) allows instant revocation at the cost of per-request I/O.
  Hybrid: short JWTs plus a revocation list for high-value scopes.
- **Revocation events**: publish token revocation to resource servers (pub/sub or a shared
  cache) so "logout everywhere" and "compromised key" take effect in seconds.
- **Clock skew**: allow a small leeway; reject tokens far in the future.
- **Key rotation**: publish overlapping `kid`s, rotate signing keys regularly, and keep the
  previous key verifiable during the max token lifetime.

## Sender-Constrained Tokens: DPoP and mTLS

Bearer tokens are replayable; bind them to a key when the threat model requires it.

**DPoP (RFC 9449)**:

- Client generates a key pair per device/session; the access token carries
  `cnf.jkt` (JWK thumbprint).
- Every request includes a `DPoP` header: a JWS over `htm`, `htu`, `iat`, `jti`, and optionally
  `ath` (access token hash), signed with the client key.
- Server verifies: proof signature, `htm`/`htu` match the actual request, `iat` within window,
  `jti` unseen (short replay cache), and thumbprint equals the token's `cnf.jkt`.
- **DPoP-Nonce** challenges (`use_dpop_nonce` + `DPoP-Nonce` header) raise security at the cost
  of an extra round trip; use for high-value APIs.
- DPoP is a strong fit for public clients (SPAs via BFF, mobile) and service-to-service where
  mTLS is impractical.

**mTLS (RFC 8705)**:

- Client certificates on every connection; the token may carry `cnf.x5t#S256` to bind it.
- The edge (mesh sidecar, ingress) terminates TLS and forwards verified identity in a header
  your app trusts **only from the edge** (strip client-supplied versions of that header).
- Short-lived certificates with automated issuance (SPIFFE/SPIRE, cert-manager) remove the need
  for CRL/OCSP in practice.
- Good for internal service meshes and high-security partner links; operationally heavier for
  arbitrary public clients.

## API Keys

API keys are simple, not automatically insecure — but they are bearer credentials.

- **Format**: recognizable prefix (`sk_live_`, `pk_test_`), high entropy (256 bits), base62 or
  base64url. The prefix enables scanners and log redaction.
- **Storage**: store only a hash (SHA-256 with a server-side pepper, or Argon2 if you must
  support low-entropy keys). Show the plaintext once at creation.
- **Scope and rate limit per key**: keys belong to a principal, carry explicit scopes, and have
  their own quota. Do not create one universal key.
- **Rotation**: support two active keys per principal with overlapping validity, plus last-used
  timestamps so you can revoke unused keys.
- **Transport**: header only (`Authorization: Bearer ...` or a dedicated header), never query
  strings. Reject over cleartext; HSTS on the edge.
- **Leak detection**: integrate secret scanning (push protection in the forge, runtime scanning
  of logs), and support instant revocation from the console/API.
- **Do not expose API keys in browser code** or mobile apps; those are public clients.

## Authorization Model

- **Deny by default**; every route declares its required scopes/permissions in the contract.
- **Object-level authorization**: check that the subject may act on *this* resource, not just
  that it holds a scope. Scope says "can create orders"; policy says "can refund this order".
- **Do not trust client-supplied identity or tenant fields.** Derive `sub`, tenant, and roles
  from the token; ignore body/query overrides.
- **Centralize policy** for complex rules (RBAC/ABAC/ReBAC engine or a policy-as-code module)
  and test it like code; scattered `if user.role ==` checks drift.
- **Admin surfaces** need stronger mechanisms: step-up authentication, hardware-backed MFA,
  short sessions, and audit logging on every mutation.
- **Return 403, not 404**, when hiding existence is not a requirement; when it is, return 404
  consistently for both missing and unauthorized resources and document it.

## Rate Limiting and Abuse Controls as Auth

- Limit per token/client/user/tenant, not just per IP (see [errors](./06-errors.md) for
  signaling).
- **Credential stuffing defense**: rate limit auth endpoints aggressively, lock or delay after
  failures, and consider proof-of-work or bot detection at the edge.
- **Tiered limits by plan** are authorization-adjacent: enforce quota from the same principal
  model so billing and access agree.
- **Denial-of-wallet**: cap expensive operations per principal and per tenant; concurrency
  limits protect shared dependencies.

## Multi-Tenancy

- **Tenant identity is a first-class claim** (`tenant_id`/`org_id`) minted by the
  authorization server, never chosen by the client at call time.
- **Every data access is tenant-scoped**: row-level security in the database or a mandatory
  repository predicate; a missing `WHERE tenant_id = ?` is the classic cross-tenant breach.
- **Key management**: per-tenant encryption keys (KMS) for data isolation where required;
  document the tenancy model (shared schema, schema-per-tenant, database-per-tenant) and its
  isolation guarantees.
- **Cross-tenant operations** (support tools, migrations) go through explicit, audited
  privileged paths, not a bypass flag.
- **Token audience per tenant** where regulations require isolation; otherwise enforce at the
  data layer.
- **Testing**: automated cross-tenant access tests that assert 403/404 for every resource type;
  include them in CI.
- **Noisy neighbor**: per-tenant concurrency and quota limits at the gateway.

## Checklist

- [ ] Each caller class has an approved mechanism; no endpoint mixes schemes.
- [ ] OAuth 2.1: PKCE everywhere, exact redirect URIs, rotation with reuse detection.
- [ ] OIDC tokens fully validated (issuer, audience, signature via JWKS cache, nonce).
- [ ] Scopes are capability-oriented, declared per operation, and default-deny.
- [ ] Tokens are audience-bound; resource indicators used where applicable.
- [ ] Access tokens are short-lived; refresh rotation and revocation paths are implemented.
- [ ] DPoP or mTLS binding for high-value scopes and public clients.
- [ ] API keys are hashed, prefixed, scoped, rotated, and revocable.
- [ ] Object-level authorization and tenant scoping are enforced and tested.
- [ ] Auth endpoints are rate limited and abuse controls are in place.
- [ ] Edge-trusted identity headers are stripped from client requests.
