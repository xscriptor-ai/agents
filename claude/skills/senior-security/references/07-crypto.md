# Cryptography

> Scope: applied crypto engineering — AEAD, password hashing, TLS configuration, KMS/HSM key management, and post-quantum migration.

## Rules of engagement

1. Use vetted, high-level libraries (libsodium, Tink, Go `crypto`, platform crypto). Do not implement primitives or modes.
2. Prefer misuse-resistant APIs: the library should handle nonces, padding, and key separation for you.
3. Never invent a scheme, protocol, or custom "encryption" from a hash.
4. Separate keys by purpose (encryption, signing, key wrapping, tokens); never reuse one key for two operations.
5. Authenticate ciphertext (AEAD or encrypt-then-MAC); never use raw CBC/CTR without integrity.
6. Generate randomness only from the platform CSPRNG; never seed your own.
7. Plan for rotation and crypto agility from the first version; store algorithm/key identifiers with ciphertext.
8. Compliance floors: use algorithm suites allowed by current standards (NIST, BSI, ANSSI); FIPS 140-3 validation when mandated, and verify current validation status upstream.

## AEAD

| Algorithm | Nonce size | Use when | Notes |
|---|---|---|---|
| AES-256-GCM | 96 bits recommended | Hardware AES available; general default | Random nonces safe up to ~2^32 messages per key; nonce reuse is catastrophic |
| ChaCha20-Poly1305 | 96 bits | No AES acceleration, mobile, software paths | RFC 8439; same nonce-reuse discipline |
| AES-GCM-SIV | 96 bits | Nonce-misuse tolerance desired | RFC 8452; costs throughput |
| XChaCha20-Poly1305 | 192 bits | Large random nonce needed | libsodium ecosystem |

Nonce management (the dominant failure mode):

- Prefer a counter or deterministic scheme with persistent state per key; never reuse a nonce with a key.
- With random nonces, rotate the key long before the birthday bound: cap messages per key (for example 2^32 for 96-bit random, lower for high assurance) and document the cap.
- Bind context as associated data: version, key id, tenant, purpose, record id. AAD prevents cross-context ciphertext substitution.
- Store `key_id`, algorithm, and nonce with the ciphertext; decryption fetches the right key and verifies integrity before use.
- Consider key commitment when ciphertexts from different keys must be distinguishable; standard GCM does not provide it.

AEAD does not solve: replay (add timestamps/sequence numbers), key management (see below), or access control.

## Hashing and key derivation

| Purpose | Primitive | Notes |
|---|---|---|
| Integrity / content id | SHA-256, SHA-512, SHA-3 | Collision resistance; not for passwords |
| Message authentication | HMAC-SHA-256 | Constant-time verify; separate keys per context |
| Key derivation from high-entropy secret | HKDF (SHA-256+) | Salt plus context info; never skip the expand step |
| Key derivation from password | Argon2id, scrypt, bcrypt | Memory-hard, tuned parameters (below) |
| Password verification | Argon2id | Preferred; upgrade path for legacy hashes |

### Password hashing

Argon2id is the default. Parameters trade memory, time, and parallelism; OWASP-style floors (verify current guidance upstream):

| Profile | Memory | Iterations | Parallelism |
|---|---|---|---|
| Minimum interactive | 19 MiB | 2 | 1 |
| Recommended interactive | 46-64 MiB | 1-2 | 1 |
| Higher assurance | 64-128 MiB | 3+ | 1-4 |

Tuning rule: target roughly 50-100 ms per verification on production hardware, use as much memory as the deployment can afford, and store parameters in the hash string so they can be raised over time. Rehash on successful login when parameters increase.

Legacy migration: bcrypt (work factor 10-12 minimum, 72-byte input limit), scrypt (N=2^17, r=8, p=1 as a starting point), PBKDF2 only where required by legacy/compliance (high iteration count). Verify a legacy hash, then rehash with Argon2id on next login.

Never: unsalted hashes, single-round SHA-256 passwords, "pepper" stored next to the hash, client-side-only hashing that becomes the verifier.

## TLS configuration

| Setting | Current practice |
|---|---|
| Versions | TLS 1.3 preferred; TLS 1.2 acceptable with restricted suites; TLS 1.0/1.1 disabled |
| Cipher suites | AEAD only: TLS 1.3 defaults; TLS 1.2 with ECDHE + AES-GCM/ChaCha20 |
| Key exchange | ECDHE with strong groups; hybrid post-quantum where supported (below) |
| Certificates | ECDSA P-256 or RSA-2048+; automate issuance and renewal (ACME) |
| Certificate lifetime | Shrinking: CA/Browser Forum ballots step toward short lifetimes (200 days from 2026, then 100, then ~47 by 2029 — verify dates upstream). Automate. |
| HSTS | Enabled with a long max-age after verifying subdomains; preload only when committed |
| OCSP/CRL | Prefer OCSP stapling; do not rely on client-side soft-fail revocation |
| 0-RTT | Disable for non-idempotent requests; replay risk |
| Renegotiation/compression | Disabled |
| mTLS | Use for service identity; validate client certs against a private CA and check identity, not just possession |
| Pinning | Avoid in browsers; use for controlled service-to-service only with a rotation plan |

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
ssl_session_tickets off;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

Internal traffic is not exempt: encrypt service-to-service (mesh mTLS or workload-level TLS) and databases in transit. Certificate management is an availability dependency — monitor expiry and automate renewal with tested rollback.

## Key management

Lifecycle for every key: generate in a managed boundary, distribute controlled, use, rotate, revoke, destroy. If any step is missing, the key is a liability.

| Layer | Function | Storage | Rotation |
|---|---|---|---|
| Root/CMK | Wraps KEKs; trust anchor | HSM/KMS, never exported | Rare, dual control, ceremony |
| KEK | Wraps DEKs; may be per-tenant | KMS/HSM | Scheduled and on compromise |
| DEK | Encrypts data/messages | Envelope-encrypted, or memory only | Per object/message or short period |
| Signing keys | Signatures and tokens | KMS/HSM, non-exportable | Scheduled; support key rollover and old-key verification |
| Secrets | Passwords, API keys | Secret manager | Automated, short-lived |

Practices:

- Envelope encryption with per-tenant KEKs for isolation; track KMS request quotas because throttling is an outage.
- Never log key material, never put keys in code, config, images, or CI variables.
- Rotation must be online: write with the new key while reading old keys; rewrap in the background; verify with a drill.
- Revocation path: know how to invalidate a key and its derived artifacts (tokens, signatures) within the incident-response time budget.
- Separation of duties: key administrators manage keys, not data; use quorum for destructive operations; log every key use.
- HSM/FIPS: choose FIPS 140-3 validated modules when required; verify the module and the exact operation is in scope for the validation.
- Backups: encrypted key backups with split custody; test restore. A lost root key is an unrecoverable data loss, and an unguarded backup is a breach.

## Post-quantum transition

Standards: NIST FIPS 203 (ML-KEM, key encapsulation), FIPS 204 (ML-DSA, signatures), FIPS 205 (SLH-DSA, hash-based signatures), finalized in 2024; additional signature schemes are in progress. Verify current status upstream. Guidance and timelines: NIST IR 8547 (deprecate classical public-key crypto in the 2030s) and CNSA 2.0 for national-security systems; sector regulators publish their own deadlines.

Why act now: harvest-now-decrypt-later makes long-lived confidential data at risk today even before quantum computers exist. Signatures are less urgent but need crypto agility to migrate.

Migration roadmap:

1. **Inventory.** Find every use of RSA/ECDH/ECDSA: TLS endpoints, SSH, code signing, document signing, VPN, KMS key types, embedded devices, and long-lived data at rest.
2. **Prioritize confidentiality first.** Encrypt data that must stay secret for 10+ years with hybrid key establishment now where supported.
3. **Hybrid, not pure.** In TLS, negotiate hybrid key exchange (for example X25519+ML-KEM-768, deployed across major browsers and libraries; verify current support upstream). Hybrid preserves classical security if the new scheme is broken.
4. **Build agility.** Version algorithms and keys in protocols and stored data; avoid hard-coding key sizes in serialization formats; make "swap the algorithm" a config change, not a rewrite.
5. **Signatures second.** Plan ML-DSA/SLH-DSA rollouts for code signing, firmware, and long-lived signed artifacts; hybrid certificates and dual signatures ease the transition.
6. **Test.** Run interop and performance tests; PQC keys and signatures are larger and slower in some paths; measure before committing.
7. **Govern.** Track standards, regulator deadlines, and vendor support; record decisions in ADRs.

Do not use unvetted algorithms, do not deploy pure PQC in a single leap for critical paths without interoperability testing, and do not let long-lived data stay on classical-only key exchange once hybrid is available.

## Anti-patterns

- Home-grown crypto, custom modes, or "encrypt with SHA-256".
- AES-CBC without integrity, ECB mode, fixed IVs, nonce reuse.
- Keys in source, environment dumps, Terraform state, or CI variables.
- One key for all tenants and all purposes with no rotation plan.
- Password hashing tuned for speed; unsalted hashes; MD5/SHA-1 anywhere.
- TLS terminated with `verify=false`, expired certs ignored, or mixed HTTP fallbacks.
- Storing ciphertext without key id or algorithm, making rotation impossible.
- Signature verification that ignores the signer identity or uses `alg` from the token.
- Treating PQC as a 2035 problem; skipping hybrid key exchange on long-lived data.
- Backup keys without custody or restore drills.

## Checklist

- [ ] AEAD used everywhere; nonce discipline documented with per-key message caps.
- [ ] Context bound as associated data; ciphertext stores key id, algorithm, and nonce.
- [ ] Passwords hashed with Argon2id using tuned parameters and a legacy upgrade path.
- [ ] CSPRNG used for all keys, nonces, tokens, and identifiers.
- [ ] TLS 1.2+ restricted to AEAD and PFS; 1.0/1.1 disabled; 0-RTT controlled.
- [ ] Certificate issuance and renewal automated; expiry monitored; HSTS configured.
- [ ] Key hierarchy documented with purpose, storage, rotation, revocation, and owner.
- [ ] Envelope encryption per tenant where isolation matters; KMS quotas monitored.
- [ ] Rotation and revocation drills executed; old keys usable for reads during rollover.
- [ ] Crypto inventory includes PQC exposure; hybrid key exchange planned or deployed.
- [ ] Algorithm and key identifiers versioned for agility.
