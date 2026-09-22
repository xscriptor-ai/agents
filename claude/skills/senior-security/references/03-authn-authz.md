# Authentication and Authorization

> Scope: identity for humans, services, and agents — OAuth 2.1, OIDC, WebAuthn/passkeys, session management, MFA, authorization models, and service-to-service auth.

## Model the problem first

Separate three questions. Conflating them is the root of most identity bugs.

1. **Authentication** — who is this principal, and how strongly was that proven?
2. **Session/token** — how does that proof persist across requests, and how is it revoked?
3. **Authorization** — may this principal perform this action on this object, in this context?

Also separate principal types: human interactive, human via third-party app, service/workload, and autonomous agent. Each has different credential lifetimes and revocation paths.

## Protocol selection

| Situation | Use | Never |
|---|---|---|
| First-party web app, server-rendered or BFF | OIDC authorization code with PKCE and server-side session cookie | Tokens in `localStorage` |
| SPA or mobile app calling your API | Authorization code with PKCE; BFF pattern when possible | Implicit flow, password grant |
| Third-party access to your API | OAuth 2.1 authorization code with PKCE, scoped tokens, consent | Shared API keys handed to partners |
| Service to service in one trust domain | Workload identity with mTLS (SPIFFE-style), short-lived tokens | Static API keys in config |
| Service to service across domains | OAuth client credentials with mTLS/private key JWT, or token exchange | Long-lived shared secrets |
| CLI, TV, IoT with limited input | Device authorization grant | Embedding a client secret in the binary |
| Enterprise workforce SSO | OIDC (preferred) or SAML 2.0 | Home-grown directory federation |
| High-value consumer access | Passkeys (WebAuthn) with recovery design | SMS as the only second factor |

OAuth 2.1 consolidates the security best current practice: PKCE required for all authorization code flows, implicit and password grants removed, exact redirect URI matching, and rotation for public clients. Verify the RFC number and status upstream; the safe engineering posture (PKCE everywhere, no implicit) is already mandatory.

## OAuth 2.1 and OIDC essentials

Authorization code with PKCE:

1. Client generates `code_verifier`, sends `code_challenge` (S256) with the authorization request, plus `state` and a `nonce` for OIDC.
2. User authenticates at the IdP; the IdP redirects back with a code to an exactly matched redirect URI.
3. Client exchanges the code plus `code_verifier` at the token endpoint (authenticated for confidential clients).
4. Client validates tokens and creates its own session.

Rules:

- Verify `state` (CSRF), `nonce` (replay), and exact redirect URI match.
- Request the narrowest scopes; scopes are coarse gates, claims are data. Never encode authorization decisions only in scopes.
- Access tokens are for resource servers, not for the browser. Keep them in the backend when a BFF is available.
- Prefer sender-constrained tokens where the threat model includes token theft: DPoP or mTLS-bound tokens.
- Use audience-restricted tokens; a token for service A must not work at service B. Reject tokens with the wrong `aud` or issuer.
- Rotate refresh tokens and detect reuse; a reused refresh token invalidates the family.

OIDC ID token validation, in order:

1. Signature against the issuer's JWKS, with key rotation handled by `kid` lookup and caching.
2. `iss` equals the expected issuer (exact string match).
3. `aud` contains this client, and `azp` matches when multiple audiences exist.
4. `exp`/`iat`/`nbf` within acceptable clock skew; reject expired or far-future tokens.
5. `nonce` matches the one you sent.
6. Only then read claims (`sub`, `email_verified`, groups) and map to local identity.

SAML notes: validate signatures over the assertion and the response with an allowlisted key, defend against XML signature wrapping, enforce `Audience`, `Recipient`, `InResponseTo`, and NotOnOrAfter, and prefer OIDC for new integrations.

## WebAuthn and passkeys

WebAuthn gives phishing-resistant authentication; passkeys are discoverable credentials synced or device-bound by the platform.

Registration (navigator.credentials.create):

- Server sends a random challenge, RP id, user handle, and a list of acceptable algorithms.
- Verify the attestation as far as policy requires (most consumer services use `none`; high assurance may require specific attesting keys).
- Store credential id, public key, sign counter, transports, and AAGUID; never a biometric or PIN.

Authentication (navigator.credentials.get):

- Server sends a random challenge and allowed credentials; verify the signature over authenticator data plus client data, check `rpIdHash`, user presence/verification flags, and UV for sensitive operations.
- Treat counters as a signal, not a hard lock; synced passkeys may not increase them.
- Require user verification for step-up actions such as adding a key or changing recovery methods.

Operational rules:

- Offer passkeys first; keep TOTP or another fallback for compatibility, but not SMS-only.
- Design recovery deliberately — recovery is the weakest link in every passkey deployment. Use multiple registered keys, recovery codes stored offline, or an assisted identity-proofing flow; never an email reset that downgrades to a single factor.
- Support account recovery without exposing credential enumeration: identical responses for known and unknown users.
- Bind passkey registration and deletion to a re-authenticated session to prevent credential injection from a hijacked session.

## Session management

| Concern | Practice |
|---|---|
| Cookie flags | `Secure`, `HttpOnly`, `SameSite=Lax` or `Strict`; `__Host-` prefix for session cookies |
| Session id | At least 128 bits of CSPRNG entropy; opaque, not derived from user data |
| Rotation | New id on login, privilege change, and periodic intervals; invalidate the old id |
| Lifetimes | Short idle timeout for sensitive apps, absolute maximum regardless of activity |
| Revocation | Server-side session store; revoke on logout, password change, and credential compromise |
| Concurrent sessions | Show and allow revoking active sessions; cap where policy requires |
| Binding | Consider binding to a device or token where risk warrants; handle false positives |
| CSRF | Synchronizer token or double-submit for cookie-based flows, `Origin` checks as defense in depth |
| Logout | Clear server state, expire cookies, and call IdP logout where single logout is required |

For bearer-token APIs with no browser session, treat refresh tokens as the crown jewel: store them hashed, rotate on use, bind to the client where possible, and support revocation per device.

## MFA

| Factor | Strength | Notes |
|---|---|---|
| Passkey/WebAuthn | Phishing-resistant | Preferred for admins and high-value accounts |
| Hardware security key | Phishing-resistant | Same WebAuthn mechanics, portable assurance |
| TOTP app | Moderate | Shared secret; phishable in real time; still valuable |
| Push with number matching | Moderate | Add number matching or origin binding; avoid simple approve/deny |
| SMS/voice OTP | Weak | SIM swap and interception; fallback only, with monitoring |
| Email OTP | Weak | Acceptable only for low-risk recovery with rate limits |
| Security questions | Very weak | Avoid; often publicly discoverable |

Program rules: enforce MFA for all privileged roles and all remote access; register at least two factors; use step-up authentication for sensitive actions (changing credentials, exporting data, approving payments); throttle and alert on failed factor attempts; never allow MFA setup to bypass re-authentication.

## JWT pitfalls

| Pitfall | Fix |
|---|---|
| `alg` confusion or `none` accepted | Pin the expected algorithm; reject unknown `alg` |
| Signature verified but issuer/audience ignored | Validate `iss`, `aud`, `exp`, `nbf` every time |
| Symmetric secret shared across services | Use asymmetric keys or mTLS-bound tokens; never HS256 with a public client |
| Long-lived tokens | Minutes for access tokens, rotation for refresh |
| Sensitive data in claims | JWT payloads are readable; keep PII and secrets out |
| No revocation story | Short expiry plus denylist or introspection for high-value operations |
| `kid` header trusted blindly | Resolve keys from a trusted JWKS by `kid`, not from the token itself |
| Clock skew ignored or excessive | Small skew (tens of seconds), monitor expiry errors |

## Authorization models

| Model | Semantics | Strengths | Costs |
|---|---|---|---|
| RBAC | Roles grant permissions | Simple, auditable, easy to reason about | Role explosion; poor fit for per-object sharing |
| ABAC | Policies over attributes and context | Precise, contextual (time, device, data class) | Policy complexity, attribute quality risk |
| ReBAC | Relationships define access (Zanzibar-style) | Natural for sharing and hierarchies; scalable checks | Requires relationship store and model discipline |
| Hybrid | ReBAC for objects plus ABAC constraints | Handles multi-tenant SaaS with sharing | Two systems to operate; keep one policy decision point |

Enforcement rules that hold for every model:

- **One decision point.** Centralize policy evaluation in a service or sidecar; applications ask, policy decides. Avoid per-endpoint ad hoc logic.
- **Object-level checks always.** Route-level checks are not authorization. Fetch the object, then ask the policy engine whether this subject may act on this object.
- **Deny by default.** Unknown action, missing attribute, or policy service error means deny (fail closed), with a monitored error path.
- **Use list-and-filter for collections.** Do not fetch all rows then filter in memory; push authorization into the query or use relationship lookups.
- **Model tenancy explicitly.** Tenant id is part of the resource identity and a mandatory input to policy, never an optional header.
- **Separate admin planes.** Privileged actions have separate roles, separate authn strength, and full audit.
- **Keep policy in version control, tested.** Policy changes are code changes with tests and review; changes are the highest-risk deploys.

## Service-to-service authentication

- Give every workload a cryptographic identity: SPIFFE IDs or cloud workload identity. mTLS provides authentication and encryption in transit; authorization still needs an explicit policy on top.
- Prefer platform-issued, short-lived credentials (certificates or tokens) over static API keys. If an API key is unavoidable, hash it at rest, prefix it for identification, scope it narrowly, and rotate it.
- Use the token exchange pattern when a service must call downstream on behalf of a user; preserve `sub` and `act` so downstream authorization can see both the user and the actor.
- Authenticate callers at the mesh or gateway and pass identity in a signed, verifiable form (mTLS identity, signed headers). Never trust unsigned internal headers such as `X-User-Id`.
- Network location is not authentication: "inside the VPC" is not a principal.

## Agent and machine identities

- Give each agent its own identity and scopes; never lend it a human's broad credentials.
- Scope tools per task and per tenant; default to read-only, require approval for writes to high-impact systems.
- Make agent actions attributable in logs: agent id, on-behalf-of user, tool, input summary, result.
- Support kill-switch revocation per agent and per tool grant.

## Anti-patterns

- Home-grown session tokens or password crypto.
- Checking `auth != null` instead of `can(subject, action, object)`.
- Passing user id in a header or query parameter and trusting it.
- Storing tokens in `localStorage` and calling it a session strategy.
- Using one long-lived API key for many services or customers.
- Roles named after people, or roles that silently accumulate permissions.
- MFA that can be disabled by email-only reset.
- Trusting internal network traffic; no mTLS, no identity, no authz.
- Policy logic duplicated in three languages and diverging.
- No revocation path: the only way to remove access is waiting for expiry.

## Checklist

- [ ] Authn mechanism chosen from the protocol table, with PKCE and exact redirect matching where OAuth applies.
- [ ] ID/access tokens fully validated (`alg`, signature, `iss`, `aud`, `exp`, `nonce`).
- [ ] Sessions use secure cookie attributes, rotation, idle and absolute timeouts, and server-side revocation.
- [ ] MFA enforced for privileged access; at least two strong factors registered.
- [ ] Passkey recovery designed and tested; no single-factor downgrade.
- [ ] Authorization centralized, object-level, deny-by-default, and tested for negative cases.
- [ ] Tenancy enforced in policy inputs and data access, not in presentation code.
- [ ] Service identities use mTLS or workload identity with scoped, short-lived credentials.
- [ ] Agents have separate identities, scoped tools, approval gates, and revocation.
- [ ] Auth events and policy decisions logged to a central, tamper-resistant store.
