---
name: senior-security
description: 'Security reference pack for 2026 application, cloud, and AI security
  work: threat modeling with STRIDE, attack trees, and LINDDUN; the current OWASP
  Top 10, ASVS, API Security Top 10, and LLM Top 10; authentication and authorization
  with OAuth 2.1, OIDC, passkeys, and RBAC/ABAC/ReBAC; security architecture and zero
  trust; Kubernetes and cloud hardening; software supply chain security with SLSA,
  sigstore, and SBOMs; applied cryptography including post-quantum migration; LLM
  and agent security; and incident response. Use when threat modeling a system, designing
  or reviewing authentication and authorization, triaging findings against OWASP or
  ASVS, hardening containers, cloud IAM, or CI/CD, choosing cryptography or planning
  post-quantum migration, securing LLM and agent features, or preparing for and running
  incident response.'
---

# Security

Read-only reference pack for security engineering in 2026: design-time threat modeling, requirements and controls, architecture, identity, cloud and supply chain hardening, cryptography, LLM and agent security, and incident response. Use it for decisions, review criteria, and operating procedures. Depth lives in `references/`; this file is the map.

The field moves on standards cycles, so the pack states floors and ranges instead of exact releases and marks uncertain items with "verify upstream". Nothing here is installation-specific: tool names and parameters are examples, not mandates.

## How to use this pack

1. Match the task to a reference scope in the index below. Most tasks need one or two references; design reviews and incident work often need three or more.
2. Load references on demand. Never paste the whole pack into context.
3. Work in the mode that fits the task: design-time (models and requirements), review-time (findings mapped to controls), or incident-time (response procedures).
4. When a decision is cross-cutting, load every relevant reference and reconcile their checklists instead of merging them mentally.
5. Treat all versions and parameters as floors. Verify current releases and standards upstream before pinning.

## Non-negotiable core rules

These hold regardless of stack, cloud, or team size. Violating one requires a written, owned, time-boxed exception.

1. **Model threats before building.** Every design starts with a data-flow model, trust boundaries, and abuse cases; update it when boundaries change.
2. **Deny by default.** Every request, job, and tool call is authenticated, authorized at the object level, and logged. Fail closed, not open.
3. **Treat all input as untrusted, including LLM and agent output.** Validate at boundaries, encode at sinks, and never let model output reach a privileged sink unchecked.
4. **Use phishing-resistant authentication for high-value access.** Passkeys/WebAuthn and MFA for privileged accounts; no shared accounts, no MFA-fatigue-prone flows for admins.
5. **Least privilege and short-lived credentials for every principal.** Humans, services, workloads, and agents use scoped, expiring identity — never long-lived static keys.
6. **Central authorization, enforced server-side.** No client-side-only checks, no per-endpoint ad hoc logic; one policy decision point with object-level checks.
7. **No secrets in code, images, or long-lived environment variables.** Secrets live in a managed store, are delivered by identity, and rotate automatically.
8. **Standard, managed cryptography only.** No custom algorithms, no static keys on disk, keys in a KMS/HSM with a documented lifecycle.
9. **Verify artifacts before deployment.** Signed, digest-addressed builds with provenance; dependencies pinned and scanned.
10. **Assume breach.** Segment, minimize blast radius, log security-relevant events centrally, detect, and rehearse response.
11. **Patch on a risk-based SLA.** Track findings from scanners and reports to closure or a documented exception; "accepted" has an owner and expiry.
12. **Write decisions down.** Security decisions and exceptions live in version control next to the architecture they protect.

## Decision tables

### Where to start by task

| Task | First reference | Then |
|---|---|---|
| New system or significant design change | `references/01-threat-modeling.md` | `references/04-security-architecture.md`, `references/03-authn-authz.md` |
| Review or fix authentication and authorization | `references/03-authn-authz.md` | `references/02-owasp.md`, `references/04-security-architecture.md` |
| Triage scanner, pen-test, or bug-bounty findings | `references/02-owasp.md` | `references/06-supply-chain.md`, `references/07-crypto.md` |
| Harden Kubernetes, containers, or cloud accounts | `references/05-container-cloud-security.md` | `references/04-security-architecture.md`, `references/06-supply-chain.md` |
| Choose or migrate cryptography | `references/07-crypto.md` | `references/04-security-architecture.md`, `references/03-authn-authz.md` |
| Build LLM, RAG, or agent features | `references/08-llm-security.md` | `references/02-owasp.md`, `references/06-supply-chain.md` |
| Active incident or breach | `references/09-incident-response.md` | `references/05-container-cloud-security.md`, `references/06-supply-chain.md` |

### Authentication mechanism

| Context | Default | Notes |
|---|---|---|
| Workforce / admin access | SSO (OIDC or SAML) plus passkeys, MFA enforced | Phishing-resistant factors for admin roles |
| Consumer sign-in | Passkeys first, email OTP or magic link fallback | Rate-limit and monitor recovery paths |
| Service to service | Workload identity with mTLS, or OAuth client credentials | No shared static API keys; short token lifetimes |
| Third-party / delegated access | OAuth 2.1 authorization code with PKCE | Exact redirect matching, no implicit flow |
| CLI and devices | Device authorization grant | Never embed a client secret in a public client |
| Agent to tool | Scoped, on-behalf-of credentials per tool call | Human approval for irreversible actions |

### Authorization model

| Need | Model | Typical tooling |
|---|---|---|
| Simple roles, few resources | RBAC | Platform-native roles, small policy set |
| Context and attribute rules | ABAC | Cedar, OPA/Rego, cloud policy engines |
| Per-object sharing and relationships | ReBAC | OpenFGA, SpiceDB, Zanzibar-style stores |
| Multi-tenant SaaS with sharing | ReBAC plus ABAC constraints | Tenant isolation plus relationship checks |

### Secrets and keys

| Secret type | Store | Notes |
|---|---|---|
| Application config secrets | Managed secret manager | Delivered by workload identity, not copied by hand |
| Database credentials | Dynamic/short-lived credentials | Prefer IAM auth or a broker that issues per-lease creds |
| Signing and encryption keys | KMS/HSM | Keys never leave the boundary in plaintext |
| CI/CD cloud credentials | OIDC federation to the cloud role | No repository-stored cloud keys |
| Customer-owned keys | KMS with BYOK/HYOK | Verify provider semantics and revocation path |

### Cryptography defaults

| Use | Default | Avoid |
|---|---|---|
| Symmetric encryption | AES-256-GCM or ChaCha20-Poly1305 | ECB, CBC without a MAC, custom modes |
| Password storage | Argon2id (see `references/07-crypto.md`) | MD5/SHA-1, unsalted or fast hashes |
| Signatures | Ed25519 or ECDSA P-256+ | RSA PKCS#1 v1.5, custom schemes |
| Transport | TLS 1.3 (TLS 1.2 with restricted suites) | TLS 1.0/1.1, static RSA key exchange |
| Post-quantum transition | Hybrid ML-KEM plus classical KEX | Waiting, or DIY PQC |

## Reference index

| File | Scope | Load when |
|---|---|---|
| `references/01-threat-modeling.md` | STRIDE, attack trees, LINDDUN and privacy, data-flow modeling, risk scoring, design-time integration | You model a system, write abuse cases, or prioritize threats |
| `references/02-owasp.md` | OWASP Top 10, ASVS levels, API Security Top 10, LLM Top 10, finding-to-control mapping, verification tooling | You triage findings, set secure-coding requirements, or run verification |
| `references/03-authn-authz.md` | OAuth 2.1, OIDC, WebAuthn/passkeys, sessions, MFA, JWT pitfalls, RBAC/ABAC/ReBAC, service-to-service auth | You design or review login, tokens, sessions, or authorization |
| `references/04-security-architecture.md` | Defense in depth, zero trust, segmentation, secure defaults, trust boundaries, key management architecture, review process | You set architecture direction or review a design at the boundary level |
| `references/05-container-cloud-security.md` | Kubernetes hardening, image security, admission control, cloud IAM pitfalls, network policy, cloud secrets, posture management | You harden or review clusters, registries, cloud accounts, or runtime |
| `references/06-supply-chain.md` | SBOM, SLSA, sigstore/cosign, dependency provenance, build hardening, vendor risk | You harden builds, evaluate dependencies, or respond to a supply-chain event |
| `references/07-crypto.md` | AEAD, password hashing, TLS configuration, KMS/HSM key management, post-quantum transition | You choose parameters, configure TLS, or plan key and PQC migration |
| `references/08-llm-security.md` | Prompt injection, tool and agent abuse, data exfiltration, guardrails, red teaming, evaluation | You ship or review LLM, RAG, or agent functionality |
| `references/09-incident-response.md` | Detection and triage, containment, forensics, communication, postmortems, tabletop exercises, metrics | You prepare for, run, or learn from a security incident |

## Cross-cutting review checklist

Before approving any design or significant change, confirm:

- [ ] Data-flow model exists and trust boundaries are marked.
- [ ] Authentication is phishing-resistant where privilege is high.
- [ ] Authorization is centralized and checks object ownership, not just route access.
- [ ] Secrets come from a manager by identity; rotation is tested.
- [ ] Cryptography uses standard primitives with managed keys.
- [ ] Artifacts are signed, digest-pinned, and scanned; SBOM is generated.
- [ ] Logging covers auth, authz, admin, and data-export events to a tamper-resistant store.
- [ ] Failure modes fail closed and are observable.
- [ ] Blast radius is bounded and segmentation is enforced, not assumed.
- [ ] LLM or agent output cannot reach a privileged sink without validation.
- [ ] An incident runbook exists for the new failure modes.
- [ ] Exceptions are written, owned, and time-boxed.

## Port

- **Port id** — `skill://senior/security` (version in `metadata.port-version`).
- **Kind** — read-only reference pack; no side effects, no tools required, no executables.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "security" })` in OpenCode; Claude Code reads `<skills-dir>/security/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers reference it as `load skill senior-security (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major. Content updates that do not change the interface bump minor or patch.
- **Degraded mode** — without the pack, agents fall back to their embedded security guidance, state that the pack was unavailable, and must not invent version numbers, parameter defaults, or standards content that only the pack would provide.
