# Cryptography and Secrets

Scope: choosing and using cryptographic primitives correctly, generating random values, storing keys, and managing secrets across their life cycle.

## Non-Negotiable Rules

1. Never design your own primitives, modes, or protocols. Use vetted libraries (libsodium, Tink,
   OpenSSL/BoringSSL, Go `crypto`, WebCrypto, the platform's crypto framework).
2. Encrypt with AEAD only (AES-GCM, ChaCha20-Poly1305, XChaCha20-Poly1305, AES-GCM-SIV) or use an
   encrypt-then-MAC composition from a library that provides it.
3. A nonce must never repeat under the same key. Prefer a counter or libsodium's random nonces; with
   AES-GCM and random 96-bit nonces, rotate keys well before the birthday bound (millions of
   messages) or use a misuse-resistant construction.
4. Never use a password, passphrase, or user identifier as a key. Derive keys (HKDF) or hash
   passwords (Argon2id).
5. All randomness that affects security comes from a CSPRNG. Never `Math.random`, `rand()` unseeded,
   `mt_rand`, timestamps, UUIDv1, or counters.
6. Compare secrets, MACs, and tokens in constant time. Early-exit `==` leaks information.
7. Keys and secrets live in a KMS/HSM or secrets manager, never in source, images, logs, or client
   bundles. Design for rotation from day one.

## Primitive Selection

| Need | Primitive | Parameters / notes |
|---|---|---|
| Password storage | Argon2id | Tune to ~50-100 ms+; OWASP-era baseline: m=19 MiB, t=2, p=1, increase as hardware allows |
| Password storage (fallback) | scrypt, bcrypt | scrypt N=2^17, r=8, p=1; bcrypt cost >= 10-12 |
| Fast integrity / hashing | SHA-256, SHA-3, BLAKE3 | Not for passwords; not a MAC |
| Legacy compatibility only | SHA-1, MD5 | Never in new designs; MD5 is collision-broken, SHA-1 too |
| Symmetric encryption | AES-256-GCM, ChaCha20-Poly1305 | 96-bit nonce for GCM, 192-bit for ChaCha20-Poly1305 |
| Large data / streams | XChaCha20-Poly1305, AES-GCM with counter nonces | Segment with unique nonces per chunk |
| HMAC | HMAC-SHA-256 (or keyed BLAKE3) | For tokens and webhook signatures |
| Key derivation | HKDF (RFC 5869) | Separate keys per purpose via `info` |
| Password-based KDF | Argon2id | Never PBKDF2 below current guidance; if required, >= 600k iterations SHA-256 |
| Signatures | Ed25519, ECDSA P-256/P-384, RSA-PSS >= 3072 | RSA PKCS#1 v1.5 only for existing protocols |
| Key agreement | X25519, ECDH P-256+ | Inside TLS 1.3 or Noise; not hand-rolled |
| TLS | 1.3 preferred, 1.2 minimum with modern suites | Disable renegotiation and legacy ciphers |
| Post-quantum readiness | Hybrid X25519+ML-KEM (FIPS 203) where supported, ML-DSA/SLH-DSA for signatures | Crypto agility now; verify library and protocol support upstream |

Deprecated advice to refuse: SHA-256 for passwords, AES-CBC without MAC, ECB anywhere, `openssl enc`
with a password, static IVs, "encrypt and then base64 means safe", custom token formats, JWT `none`
or HMAC algorithms with public keys.

## Password Hashing

```python
from argon2 import PasswordHasher

ph = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=1)
digest = ph.hash(password)                    # store this string (embeds params+salt)
ph.verify(digest, candidate)                  # raises on mismatch
if ph.check_needs_rehash(digest):
    store(ph.hash(candidate))                 # upgrade transparently on login
```

- Hash on the server, in the login path, with a unique salt per password (libraries handle this).
- Rate-limit and add a per-account delay or lockout; hashing does not stop online guessing.
- On password change, rehash; on parameter upgrades, rehash on next successful login.
- If you must support multiple algorithms during migration, store the algorithm and parameters
  with the digest and upgrade lazily.
- Do not impose composition rules (uppercase/symbol quotas); enforce a length floor (for example
  12+), check against breached-password lists, and allow long passphrases and paste.
- Password reset tokens: >= 128 bits of CSPRNG, single use, short TTL, hashed at rest, invalidated
  on use or on password change.

## AEAD Usage

```python
import os
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

key = AESGCM.generate_key(bit_length=256)     # in practice: from a KMS, not ad hoc
aead = AESGCM(key)
nonce = os.urandom(12)                        # unique per encryption under this key
ct = aead.encrypt(nonce, plaintext, associated_data=b"tenant:42:v1")
pt = aead.decrypt(nonce, ct, associated_data=b"tenant:42:v1")
```

- Bind context with associated data (tenant, user, purpose, version) so ciphertexts cannot be
  replayed into another context.
- Store `version || nonce || ciphertext || tag` with an explicit format; never rely on implicit
  framing.
- Rotate the key before nonce exhaustion; never reset a counter when restarting a process.
- Do not use the same key for encryption and signing; derive separate keys with HKDF.
- On decryption failure, fail closed and do not reveal whether the tag or padding failed.

## Secure Randomness

| Language | Use | Never |
|---|---|---|
| Python | `secrets.token_urlsafe`, `secrets.token_bytes`, `os.urandom` | `random`, `uuid.uuid1()` |
| Node | `crypto.randomBytes`, `crypto.randomUUID` (v4), `crypto.getRandomValues` | `Math.random` |
| Go | `crypto/rand` | `math/rand` without `rand/v2` crypto | 
| Rust | `rand::rngs::OsRng`, `getrandom` | `fastrand`, `thread_rng` for secrets |
| Java | `SecureRandom` (default provider) | `java.util.Random`, `Math.random` |
| .NET | `RandomNumberGenerator.GetBytes`, `RandomNumberGenerator.GetInt32` | `Random`, `Guid.NewGuid()` for secrets |
| C/C++ | `getrandom(2)` / `BCryptGenRandom` / `SecRandomCopyBytes` | `rand`, `srand(time(NULL))` |

For tokens: at least 128 bits of entropy (256 for long-lived or high-value); encode URL-safe; store
hashed if the token is a bearer credential; bind to a purpose and expiry. `randomUUID` from
`crypto` is fine for identifiers, but UUIDv1 (time/MAC-based) and predictable IDs are not secrets.

## Constant-Time Comparison

```go
// Go: wrong vs right
if subtle.ConstantTimeCompare([]byte(got), []byte(want)) != 1 { reject() }   // right
```

- Python: `hmac.compare_digest`; Node: `crypto.timingSafeEqual`; Rust: `subtle::ConstantTimeEq`;
  Java: `MessageDigest.isEqual` (constant-time for equal lengths); .NET:
  `CryptographicOperations.FixedTimeEquals`.
- Beware length leaks: constant-time compare of unequal lengths still reveals length. Hash both
  sides to a fixed size first when length itself is sensitive.
- Do not branch on secret bytes: no `if (mac[0] == ...)` checks, no early return on first mismatch,
  no lookup tables indexed by secrets.

## Key Management

| Layer | Practice |
|---|---|
| Root key | HSM/KMS, never exported, dual control for destructive actions |
| Data keys | Envelope encryption: KMS encrypts a DEK, DEK encrypts data; cache short TTL |
| Per-tenant keys | Separate key material per tenant where data-residency or isolation demands |
| Key versions | `kid` in ciphertext metadata; old versions decrypt-only during rotation |
| Rotation | Scheduled (for example <= 12 months for root, sooner for high-volume keys) and event-driven on exposure |
| Access | IAM/KMS policies per workload; audit every decrypt/encrypt; deny by default |
| Dev/test | Separate keys and accounts; no production key material in lower environments |

Rotation procedure that works:

1. Generate the new key version; publish it alongside the old.
2. Write new data with the new version; tag all ciphertexts with their version.
3. Re-encrypt old data lazily or in a batch job; track progress.
4. After a defined window with zero old-key reads, disable and then destroy the old version.
5. Document the rollback window; destroying a key is irreversible.

## Secret Management

| Environment | Storage | Notes |
|---|---|---|
| Developer laptop | `.env` gitignored, direnv, mock values | Never real production secrets |
| CI/CD | OIDC federation to the cloud, masked variables | Prefer short-lived tokens over static keys |
| Runtime | Secrets manager / KMS, mounted or injected at start | No secrets in env when avoidable; env leaks via crash dumps and child processes |
| Kubernetes | External Secrets Operator, CSI secrets store, sealed secrets | Encryption at rest alone is insufficient; RBAC is the boundary |
| Build artifacts | None | Images must be reproducible without embedded secrets |

Life cycle rules:

- Inventory every secret: owner, purpose, storage, expiry, rotation method, consumers.
- Prefer identity over keys: workload identity, mTLS, SPIFFE, short-lived cloud credentials.
- Scan repositories and CI logs for secrets (gitleaks, TruffleHog, provider-native scanning) and
  treat any historical commit as compromised.
- Never log credentials, tokens, cookies, or full request bodies; redact at the logging layer and
  test the redaction.
- On exposure: revoke first, then rotate, then audit usage, then fix the root cause. Assume
  exfiltration for any secret committed to a public repository.
- Limit blast radius: per-service credentials, per-purpose keys, least-privilege scopes, and
  egress restrictions so stolen secrets are less useful.

## Common Misuse Catalog

| Mistake | Consequence | Fix |
|---|---|---|
| AES-CBC without authentication | Padding-oracle decryption, tampering | AEAD or encrypt-then-MAC |
| Reused nonce/IV | Keystream reuse in CTR/GCM, forgery | Counter or random with rotation policy |
| Static IV stored with data | Deterministic ciphertext, equality leaks | Fresh random nonce per message |
| Password as encryption key | Offline brute force of all data | Argon2id-derived key via a KMS |
| `==` on MACs/tokens | Timing oracle | Constant-time compare |
| Custom JWT parsing without signature verification | Full auth bypass | Verify signature, `alg`, `iss`, `aud`, `exp` with a maintained library |
| Accepting `alg: none` or HMAC with a public key | Token forgery | Pin allowed algorithms server-side |
| Self-signed/disabled TLS verification | MITM | Verify chains; pin where the threat model requires |
| Random tokens from `Math.random` | Predictable sessions/resets | CSPRNG, >= 128 bits |
| Secrets in client bundles or mobile apps | Public disclosure | Never ship secrets; proxy server-side |

## Checklist

- [ ] Passwords use Argon2id (or scrypt/bcrypt) with tuned params and transparent rehash.
- [ ] All encryption is AEAD; nonces are unique; ciphertexts carry version/key id context.
- [ ] Keys come from KMS/HSM; envelope encryption; rotation is scheduled and rehearsed.
- [ ] CSPRNG is used for every token, session, nonce, and secret; no `Math.random`/`rand()`.
- [ ] Secret comparisons are constant-time; no branching on secret bytes.
- [ ] Secrets are absent from git history, images, logs, and client code; scanning runs in CI.
- [ ] Token formats use maintained libraries with algorithm allowlists and full claim validation.
- [ ] Tests cover tampered ciphertext, wrong key/nonce reuse detection, and token tampering.
