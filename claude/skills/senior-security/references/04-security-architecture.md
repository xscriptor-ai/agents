# Security Architecture

> Scope: system-level security design — defense in depth, zero trust, segmentation, secure defaults, trust boundaries, key management architecture, and architecture review.

## Principles

| Principle | Meaning | Design consequence |
|---|---|---|
| Defense in depth | Independent layers so one failure is not a breach | Authn plus authz plus validation plus monitoring on the same path |
| Least privilege | Minimum rights, shortest duration | Scoped roles, short-lived credentials, no ambient authority |
| Complete mediation | Every access is checked, every time | Central policy decision point; no cached "already checked" assumptions |
| Fail secure | Failure denies access and preserves integrity | Closed-by-default gateways, deny on policy-engine errors |
| Economy of mechanism | Simple, reviewable designs | Fewer trust paths, no bespoke protocols, small policy surface |
| Separation of duties | No single principal controls a critical operation end to end | Dual control for key ceremonies, production changes, and payments |
| Least common mechanism | Shared components do not create shared risk | Tenant isolation, separate control and data planes |
| Open design | Security does not depend on secrecy of design | Public algorithms; secrets limited to keys |
| Minimize attack surface | Fewer ports, features, and dependencies | Disable unused services; remove debug and admin endpoints from public routes |
| Secure by default | The safe configuration is the zero-effort configuration | Deny policies on until explicitly opened; TLS on by default |

## Trust boundaries

A trust boundary is anywhere control, identity, or data classification changes: browser to edge, edge to cluster, service to service across namespaces, application to database, workload to cloud metadata, service to a third-party API, and application to an LLM or agent tool. Find them from the data-flow model in `./01-threat-modeling.md`.

For each boundary, define:

1. **Enforcement** — what authenticates and authorizes crossing it (gateway, mesh mTLS, policy engine, token exchange).
2. **Validation** — what schema and semantic checks run on entry.
3. **Data handling** — what may cross, in what form (classification, redaction, field-level rules).
4. **Observability** — what is logged and alerted at the crossing.
5. **Failure mode** — what happens when the enforcement point is unavailable (deny, queue, degraded read-only).

Rule of thumb: crossing a boundary requires an explicit decision; crossing inside a boundary may inherit context, but never inherits trust to a different classification.

## Zero trust

Zero trust replaces network location with explicit, continuously evaluated identity and context. NIST SP 800-207 is the canonical reference (cloud-native guidance in SP 800-207A); verify the current revision upstream.

Core tenets in practice:

- Every request is authenticated and authorized based on identity, device, and context, regardless of network.
- Access is per-session with least privilege and just-in-time elevation, not standing network access.
- Policy is centralized and dynamic; enforcement is distributed to gateways, proxies, and sidecars.
- Assume the network is hostile: encrypt and authenticate service traffic, verify endpoints.
- Log everything relevant to access decisions for detection and improvement.

Architecture building blocks:

| Component | Role | Examples |
|---|---|---|
| Policy decision point (PDP) | Evaluates policy on identity and context | OPA, Cedar, cloud policy engines |
| Policy enforcement point (PEP) | Applies the decision at the data path | API gateway, sidecar, service mesh, IdP-aware proxy |
| Identity provider | Strong authentication and token issuance | OIDC IdP with passkeys and MFA |
| Device posture | Device health and management signal | MDM signal, certificate-based device identity |
| Identity-aware proxy | Replaces VPN for workforce app access | Provider ZTNA solution or self-built gateway with OIDC |
| Continuous evaluation | Re-checks sessions on context change | Short sessions, re-auth on risk signals, revocation feeds |

Migration reality: you cannot buy zero trust in one product. Sequence: strong identity, then segmentation and mTLS, then centralized policy, then device signals and continuous evaluation.

## Segmentation

- Place workloads in tiers by data classification and exposure: public edge, application, data, management. Allow only declared flows between tiers; default deny within the cluster as well.
- Enforce L3/L4 network policy as a floor and L7 policy where identity matters (method, path, service identity). See `./05-container-cloud-security.md` for Kubernetes specifics.
- Isolate management planes (CI, bastion, admin APIs) from data planes; management never rides on the same path as user traffic.
- Egress is a boundary too: allowlist destinations for workloads, especially anything that processes untrusted input or hosts an agent.
- Deny lateral movement by default: no flat RFC1918 trust, no shared credentials between tiers, no "internal" header trust.
- Use separate accounts/projects/subscriptions per environment and blast-radius zone; production credentials do not exist in dev.

## Secure defaults

| Area | Safe default | Common unsafe default |
|---|---|---|
| Network | Deny all ingress and egress; open explicitly | Allow-all then restrict later |
| Authz | Deny when policy is missing or evaluation fails | Allow when no rule matches |
| TLS | On, valid certs required, no skip-verify option in prod | Optional TLS, insecure flags wired for convenience |
| Debug/admin | Disabled in production images and routes | Debug endpoints reachable from the internet |
| CORS | No wildcard with credentials; explicit origins | `*` plus credentials |
| Cookies | `Secure`, `HttpOnly`, `SameSite`, prefixed | No attributes, long-lived |
| Storage | Private buckets, encryption on, access logging | Public buckets, no logging |
| Errors | Generic external messages, detailed internal logs | Stack traces and queries returned to clients |
| Feature flags | Default off for risky features; kill switch ready | Default on, no off switch |
| Secrets | Required from a manager; no fallback literal | "Temporary" hardcoded key that survives |

Make the safe path the easy path: scaffolding, templates, and CI checks should generate the secure configuration so developers do not choose it manually.

## Key management architecture

A key hierarchy limits exposure: root keys never encrypt data directly.

| Layer | Function | Storage | Rotation |
|---|---|---|---|
| Root of trust / CMK | Wraps key-encryption keys; root of the hierarchy | HSM or KMS, never exported | Rare, under dual control and ceremony |
| Key encryption key (KEK) | Wraps data keys; may be per-tenant | KMS or HSM-backed | On schedule and on compromise |
| Data encryption key (DEK) | Encrypts data with AEAD | Stored encrypted (envelope) or ephemeral in memory | Per object, per message, or per short period |
| Application secrets | Passwords, API credentials, tokens | Secret manager with workload identity | Automated, short-lived where possible |

Design rules:

- Never ship root or KEK material into application memory; use KMS/HSM wrap/unwrap or envelope encryption with DEKs.
- Bind ciphertext to context: store key id/version and encryption metadata with the data; support decrypt-with-old-key while writing new keys.
- Plan rotation before you need it: every ciphertext carries enough metadata to rewrap; run a rotation drill in staging.
- Enforce separation of duties: key administrators cannot read data encrypted under the keys they manage; use quorum or dual control for destructive key operations.
- Document the crypto boundary: which components can see plaintext, which only ciphertext, and which hold key material. Data must be plaintext only inside the boundary.
- BYOK/HYOK changes trust in the provider, not your key hygiene; verify provider semantics (import, rewrap, revocation, regional residency) before relying on them.
- Prefer per-tenant keys for isolation, but track KMS quotas and cost; quota exhaustion is an availability risk.
- Capture an inventory: key id, purpose, algorithm, owner, creation, rotation schedule, and dependent systems. Unknown keys cannot be rotated or revoked.

## Pattern catalog

| Problem | Pattern | Notes |
|---|---|---|
| Browser app calling APIs | Backend for frontend (BFF) with server-side session | Keeps tokens off the browser; see `./03-authn-authz.md` |
| Cross-cutting authz | Policy sidecar or library with central PDP | One decision semantics; policy tested as code |
| Third-party integration | Gateway with schema validation and egress allowlist | Boundary control in one place |
| High-risk actions | Step-up authentication plus dual approval | Risk-based challenge on the action, not only on login |
| Untrusted code execution | Sandboxed worker with no credentials and bounded egress | Also applies to agent code tools |
| Multi-tenant SaaS | Tenant id in the resource identity; per-tenant keys and policy scope | Isolation enforced in data access, not UI |
| Secrets delivery | CSI/secret operator with workload identity | No plaintext secrets in manifests or images |
| LLM feature | Tool gateway with allowlisted actions and human approval for writes | See `./08-llm-security.md` |

## Security architecture review

Inputs: data-flow model and threat list, data classification, compliance obligations, deployment topology, identity model, and the ADRs for prior decisions.

Review outputs:

1. Boundary table (enforcement, validation, data handling, observability, failure mode) as above.
2. Control placement map: which layer owns each control and what happens when it fails.
3. Open risks with owner, severity, and expiry.
4. Security decisions recorded as ADRs, linked from the system's docs.
5. Follow-up items with tests or verification steps.

Review questions that catch most design flaws:

- What is the worst thing an authenticated user can do with one request?
- What happens when each external dependency fails or is compromised?
- Where is plaintext data, and who can reach it?
- Which credentials exist, how long do they live, and how are they revoked?
- What happens to existing sessions and tokens when an account is disabled?
- Can a single compromised CI job or admin account reach production data?
- Which paths cross an autonomy boundary (an agent acting without approval)?

## Anti-patterns

- Security as a perimeter: hard shell, soft center.
- Copying a reference architecture without its operating assumptions (scale, tenancy, compliance).
- One giant shared VPC/subscription with allow-all security groups.
- Encryption without key management: keys in config, one key for everything, no rotation.
- Adding a control in the UI and calling it enforced.
- Policy evaluation that fails open when the PDP is down.
- Rebuilding zero trust as a VPN replacement only, with no per-request authorization.
- Threat model updated only when an auditor asks.
- Admin plane colocated with the user data plane on the same credentials.

## Checklist

- [ ] Data-flow model identifies boundaries; each boundary has enforcement, validation, data rules, observability, and a failure mode.
- [ ] Zero-trust rollout sequenced: identity first, then segmentation, policy, device, continuous evaluation.
- [ ] Network denies by default for ingress and egress; management planes isolated.
- [ ] Secure defaults documented and generated by templates; unsafe options require explicit override.
- [ ] Key hierarchy documented with roles, storage, rotation, and separation of duties.
- [ ] Every ciphertext carries key id and metadata; rotation drill executed.
- [ ] Crypto boundary and plaintext visibility documented.
- [ ] Patterns chosen deliberately: BFF, PDP/PEP, gateway, sandbox, per-tenant isolation.
- [ ] Security review performed for boundary-changing work; decisions recorded as ADRs.
- [ ] Exceptions have owners and expiry; controls have owners and tests.
