---
name: senior-secure-coding
description: 'Cross-language secure coding reference pack for 2026: injection prevention
  across SQL, NoSQL, ORM, OS command, template, LDAP, and XPath sinks; XSS/CSRF; output
  encoding; Trusted Types and CSP; SSRF and unsafe deserialization; passwords, AEAD,
  randomness, keys, and secrets; validation, file uploads, and path traversal; per-language
  cheatsheets (Python, TS/Node, Go, Rust, JVM, C/C++); dependency, provenance, and
  patch-SLA hygiene; and a secure code review checklist with SAST/DAST/SCA/fuzzing
  tests. Use when writing, reviewing, or hardening application code in any language;
  when fixing injection, XSS, CSRF, SSRF, deserialization, crypto, secret-handling,
  validation, upload, or dependency vulnerabilities; when choosing parameterization,
  encoding, or validation strategies; or when auditing a codebase against OWASP-style
  defect classes. Optional: consumers degrade gracefully when absent.'
---

# Secure Coding

Secure coding is the practice of writing and reviewing application code so that attacker-controlled
data never gains control of an interpreter, a privilege boundary, or a cryptographic decision. Most
real exploits are not exotic: they are concatenated strings, unvalidated object shapes, missing
authorization checks, reused nonces, and stale dependencies. This pack is the working reference for
preventing and reviewing those defect classes in any stack.

The depth lives in `references/`; this file is the map. Named libraries and tools are examples of a
category, not endorsements. Version numbers are floors or ranges, never exact pins; verify upstream
before depending on a specific release.

## Non-Negotiable Core Rules

1. **All input is hostile until validated.** HTTP bodies, headers, cookies, query strings, file
   contents, message-queue payloads, database rows written by other users, and third-party API
   responses are all untrusted. Trust is granted per boundary, never per network location.
2. **Parameterize, never concatenate, across every interpreter.** Queries, OS commands, templates,
   LDAP filters, and XPath expressions receive data through bindings. Where binding is impossible
   (identifiers, sort keys, operator choice), use a fixed allowlist, not escaping.
3. **Validate at the boundary, encode at the sink.** Validation decides what enters the system;
   output encoding decides what reaches HTML, SQL, shell, or logs. Do both, and never use one as a
   substitute for the other.
4. **Authorization is server-side, per request, per object, per action.** Authentication answers
   who; authorization answers whether this principal may do this to this object now. Enforce it in
   the data layer or a policy layer that every route passes through.
5. **Encoding is context-specific.** HTML text, attributes, JavaScript, CSS, URLs, JSON, XML, CSV,
   and headers each need a different encoder. One global "escape" function guarantees bugs in at
   least one context.
6. **Use vetted cryptography only.** AEAD or nothing; unique nonces per key; CSPRNG for every
   security decision; constant-time comparison for secrets. Never invent primitives, modes, or
   protocols; never use `Math.random`, `rand()` unseeded, or timestamps as entropy.
7. **Secrets never live in source, images, logs, or clients.** Use workload identity and short-lived
   credentials; store long-lived material in a KMS/HSM or secrets manager; scan CI and git history;
   rotate on exposure and schedule.
8. **Deserialize only trusted, schema-validated data.** Native object serialization (Java, Python
   pickle, PHP, Ruby Marshal, .NET BinaryFormatter, YAML unsafe load) crosses trust boundaries only
   in attacks. Prefer JSON/CBOR/protobuf with explicit schemas; sign state you must round-trip.
9. **Deny by default: egress, filesystem, CORS, CSP, cookies.** Explicit allowlists for outbound
   network destinations, upload paths, browser origins, and cookie scope. Every exception is a
   documented decision with an owner.
10. **Treat dependencies and build inputs as trust decisions.** Lockfiles are mandatory, provenance
    is verified where available, install scripts are constrained, and every advisory has a patched
    SLA. A vulnerable transitive package is your vulnerability.
11. **Fail closed, log safely, bound resources.** On errors, deny rather than permit; never log
    secrets, tokens, or full payloads; cap sizes, counts, depth, and time so one request cannot
    exhaust the process (see [references/05-validation-encoding.md](./references/05-validation-encoding.md)).
12. **Fix the class, not the instance, and pin it with a test.** For every vulnerability, add a
    regression test, a lint/SAST rule where possible, and a note in the review record so the same
    pattern cannot silently return.

## Decision Tables

### Control selection by data path

| Data path | Primary control | Secondary control | Never do |
|---|---|---|---|
| User value into SQL/ORM | Bound parameter | Schema validation, least-privilege DB account | String formatting or f-string |
| Table/column/sort identifier | Allowlist constant map | Reject unknown keys | Quote/escape identifiers |
| User value into OS command | argv array, no shell | Absolute binary path, `--` terminator | `sh -c`, `exec`, `shell=True` |
| User value into HTML | Context-aware output encoding | CSP, Trusted Types, sanitizer for rich text | `innerHTML` with raw data |
| User value into a template | Pass as template variable | Logic-less engine, sandboxed rendering | Compiling user input as a template |
| User URL fetched by server | Scheme allowlist + DNS/IP pinning | Egress proxy, redirect re-validation | Fetching arbitrary user URLs directly |
| Serialized state from client | Signed + schema validated | HMAC, short TTL | Native deserialization |
| User file upload | Content sniff + re-encode + random name | Store outside web root, serve inert | Trusting extension or MIME header |
| Secret at runtime | Secrets manager / KMS | Short TTL, rotation, audit | Config file, env default, hardcode |

### Where the control belongs

| Layer | Responsible for | Examples |
|---|---|---|
| Edge / gateway | Transport, coarse rate limits, request size caps | TLS, WAF, quotas |
| Application boundary | Authentication, schema validation, canonicalization | Middleware, DTOs, Zod/Pydantic |
| Domain logic | Authorization, invariants, business rules | Policy checks, ownership filters |
| Data layer | Query parameterization, row scoping, constraints | Prepared statements, RLS, FK/CHECK |
| Presentation | Output encoding, CSP, cookie attributes | Template engine, security headers |
| Platform / CI | Dependency policy, secret scanning, least privilege | Lockfiles, OIDC, scanners |

### Cryptographic primitive selection

| Need | Use | Avoid |
|---|---|---|
| Password storage | Argon2id (or scrypt/bcrypt with tuned work factor) | MD5/SHA-1/SHA-256 alone, fast hashes, unsalted |
| Symmetric encryption | AES-256-GCM or ChaCha20-Poly1305, unique nonce | ECB, CBC without MAC, static IV |
| Key derivation | HKDF for key material, Argon2id/PBKDF2 for passwords | Ad-hoc KDF, password as key |
| Signatures | Ed25519 (EdDSA), ECDSA P-256/P-384, RSA-PSS >= 3072 | RSA PKCS#1 v1.5 for new designs, MD5/SHA-1 |
| Key exchange | X25519/ECDH P-256+ with TLS 1.3 or Noise | Custom Diffie-Hellman, anonymous DH |
| Integrity comparison | Constant-time equality | `==` on MACs/tokens |
| Random tokens | CSPRNG, >= 128 bits | UUIDv1, counters, timestamps, `rand()` |
| Post-quantum migration | Hybrid classical + ML-KEM (FIPS 203) where supported | Waiting until migration is forced |

### Secret storage by environment

| Environment | Storage | Notes |
|---|---|---|
| Local dev | `.env` gitignored, direnv, mock secrets | Never a real production credential |
| CI/CD | OIDC workload identity, masked variables | Prefer federation over long-lived tokens |
| Staging/prod | KMS/HSM or secrets manager, injected at runtime | Envelope encryption, audit, rotation |
| Customer-managed | External Secrets Operator, sealed secrets | Cluster compromise must not reveal plaintext |

## Reference Index

| File | Scope | Load when |
|---|---|---|
| [references/01-injection.md](./references/01-injection.md) | SQL/NoSQL/ORM injection, OS command, template (SSTI), LDAP/XPath; parameterization, identifier allowlists, per-context escaping, DB hardening | Any query, command, template, or directory call built from user data; reviewing data access code |
| [references/02-xss-csrf.md](./references/02-xss-csrf.md) | Output encoding contexts, dangerous sinks, sanitizers, Trusted Types, CSP, cookie attributes, CSRF tokens, SameSite, Fetch Metadata, CORS interactions | Building or reviewing browser-facing UI, session handling, headers, or cross-origin APIs |
| [references/03-ssrf-deserialization.md](./references/03-ssrf-deserialization.md) | SSRF patterns, cloud metadata endpoints, redirect and DNS-rebinding handling, egress allowlists; unsafe deserialization per language, safe formats, signed state | Server-side fetches, webhooks, URL previews, import/export, cache or session deserialization |
| [references/04-crypto-secrets.md](./references/04-crypto-secrets.md) | Password hashing, AEAD and nonce rules, secure randomness, constant-time comparison, key storage and rotation, secret life cycle, common misuse | Choosing or reviewing crypto, storing secrets, generating tokens, handling keys |
| [references/05-validation-encoding.md](./references/05-validation-encoding.md) | Validation strategy and trust boundaries, schema libraries, canonicalization, Unicode pitfalls, file uploads, path traversal, output encoding contexts, CSV/header/log injection | Designing DTOs or middleware, handling files or paths, normalizing input, fixing encoding bugs |
| [references/06-per-language-cheatsheets.md](./references/06-per-language-cheatsheets.md) | Sharp-edge rules and safe APIs for Python, TypeScript/Node, Go, Rust, Java/Kotlin, C/C++; links to sibling language packs | Writing or reviewing code in a specific language and you need the local unsafe/safe mapping |
| [references/07-dependencies.md](./references/07-dependencies.md) | Dependency hygiene, lockfiles, integrity and provenance, SBOM, audit automation, patch SLAs, typosquatting and dependency confusion, CI hardening | Adding a dependency, triaging advisories, hardening install and release pipelines |
| [references/08-review-checklist.md](./references/08-review-checklist.md) | Secure code review process and per-class checklist, security-focused tests (SAST/DAST/SCA/IaC/secrets), fuzzing and sanitizers, threat-driven test cases, CI gates and triage | Reviewing a diff or service, building a security test plan, setting CI security gates |

## Sibling Packs

| Pack | Use for | Link |
|---|---|---|
| security | Threat modeling (STRIDE), authn/authz architecture, API and container security, zero trust | [../security/SKILL.md](../security/SKILL.md) |
| web | Browser security depth: CSP, Trusted Types, cookies, third-party scripts, headers | [../web/SKILL.md](../web/SKILL.md) |
| api-design | OAuth 2.1, OIDC, scopes, idempotency, webhook verification, contract review | [../api-design/SKILL.md](../api-design/SKILL.md) |
| testing | Test strategy, fixtures, fuzzing ergonomics, CI structure for security tests | [../testing/SKILL.md](../testing/SKILL.md) |
| cloud | Supply-chain security, admission control, platform hardening, secret operators | [../cloud/SKILL.md](../cloud/SKILL.md) |
| python | Python idioms, async, SQLAlchemy/pydantic depth, packaging and deployment | [../python/SKILL.md](../python/SKILL.md) |
| typescript | TS/Node depth: types, runtimes, framework security, tooling | [../typescript/SKILL.md](../typescript/SKILL.md) |
| go | Go depth: concurrency, database/sql, pgx, module and supply-chain practice | [../go/SKILL.md](../go/SKILL.md) |
| rust | Rust depth: ownership, unsafe/FFI review, axum, sqlx, cargo audit workflows | [../rust/SKILL.md](../rust/SKILL.md) |
| java-kotlin | JVM depth: JDBC/JPA, Spring Security, serialization, Gradle/Maven supply chain | [../java-kotlin/SKILL.md](../java-kotlin/SKILL.md) |

## How to Use This Pack

- Start with the control-selection table, then load exactly the references the task needs. One
  reference is usually enough for a fix; reviews load two or three.
- For a new service or feature, read 01, 02, and 05 before writing handlers, 04 before adding any
  crypto or session logic, and 07 before adding dependencies.
- For an incident or audit, read 08 first to structure the review, then the defect-class reference
  it points to.
- References cross-link with relative paths (`./NN-*.md`) and point to sibling packs for depth;
  follow those links instead of re-deriving guidance here.

## Port

- **Port id** — `skill://senior/secure-coding` (version in `metadata.port-version`).
- **Kind** — read-only reference pack; no side effects, no tools, no scripts required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "secure-coding" })` in OpenCode; Claude Code reads
     `<skills-dir>/secure-coding/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the
     degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it (`senior-appsec`,
  `senior-pentest`, all coding agents, `orchestrator`); consumers reference it as
  `load skill senior-secure-coding (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major.
