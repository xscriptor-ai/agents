---
name: secure-coding
version: 1.0.0
description: "Cross-language secure coding patterns — injection prevention, XSS, CSRF, crypto, secrets management, input validation, output encoding"
---

# Secure Coding

## Injection Prevention

### SQL Injection

| Anti-Pattern | Secure Alternative |
|--------------|--------------------|
| String concatenation | Parameterized queries / prepared statements |
| Dynamic table names | Whitelist allowed values |
| Stored procedures with exec() | Typed parameters with strict validation |

```python
# insecure
query = f"SELECT * FROM users WHERE email = '{email}'"

# secure
cursor.execute("SELECT * FROM users WHERE email = %s", (email,))
```

### NoSQL Injection

- Use query builders with typed parameters (Mongoose, Spring Data).
- Sanitize `$where`, `$regex`, `$gt` operators.
- Validate schema before query execution.

### Command Injection

- Avoid `os.system()`, `subprocess(shell=True)`, `exec()`.
- Use library-specific safe APIs.
- If shell required, validate input against strict regex whitelist.

### LDAP Injection

- Escape special characters (`*`, `(`, `)`, `\`, `NULL`) per RFC 4514.
- Use parameterized LDAP queries when available.

## XSS Prevention

| Context | Encoding | Example |
|---------|----------|---------|
| HTML body | HTML entity encode `& < > " '` | `&lt;script&gt;` |
| HTML attribute | Attribute encode + quote wrapping | Use template engine auto-escaping |
| JavaScript string | Unicode escape `\uXXXX` | Never insert untrusted data in script tags |
| CSS | Strict validation | `url()` only with whitelisted protocols |
| URL | URL encoding | `encodeURIComponent()` |

- Use Content Security Policy (CSP) headers as defense-in-depth.
- Framework auto-escaping (React JSX, Vue templates, Go html/template).
- Never use `dangerouslySetInnerHTML`, `v-html`, or `innerHTML`.

## CSRF Protection

- Synchronizer token pattern: include CSRF token in forms, verify on server.
- Set `SameSite=Strict` or `SameSite=Lax` on session cookies.
- Require re-authentication for sensitive actions (password change, money transfer).
- Use `Origin` / `Referer` header validation as secondary check.

## Cryptography Best Practices

| Operation | Algorithm | Parameters |
|-----------|-----------|------------|
| Hashing (passwords) | bcrypt, argon2, scrypt | cost=12, memory=64MB |
| Hashing (integrity) | SHA-256, SHA-3 | — |
| Symmetric encryption | AES-256-GCM | Nonce=12 bytes |
| Asymmetric encryption | RSA-4096, ECDH P-384 | OAEP padding |
| Signing | ECDSA P-384, Ed25519 | Deterministic K |
| Key derivation | HKDF, PBKDF2 | Per-purpose salt |

- Never roll your own crypto.
- Use high-level libraries (Tink, libsodium, Go crypto).
- Rotate keys on a schedule.

## Secrets Management

| Environment | Method | Example |
|-------------|--------|---------|
| Development | .env files (gitignored) | `dotenv`, direnv |
| CI/CD | CI provider secrets | GitHub Actions secrets |
| Staging/Prod | Vault/Cloud KMS + IAM | HashiCorp Vault, AWS Secrets Manager |

- Never hardcode secrets. Never commit .env files.
- Use short-lived credentials (STS, IAM roles).
- Audit secret access.

## Input Validation

- Validate on the server (client-side is UX only).
- Whitelist over blacklist.
- Validate: type, length, range, format (regex), enum values.
- Use schema validation libraries (Zod, Pydantic, go-playground/validator).

## Output Encoding

- Encode at the presentation boundary, not at the data layer.
- Context-aware encoding (HTML vs JSON vs XML vs CSV).
- Use framework-provided encoding functions.

## Per-Language Cheat Sheets

| Language | SAST | Dependency Scan | Secrets Scan |
|----------|------|-----------------|--------------|
| Python | Bandit, Semgrep | pip-audit, Safety | truffleHog |
| TypeScript/JS | ESLint security, Semgrep | npm audit, Snyk | truffleHog |
| Go | gosec, Semgrep | govulncheck | truffleHog |
| Rust | cargo-audit, clippy | cargo-audit | truffleHog |
| Java | SpotBugs, FindSecBugs | OWASP Dependency Check | truffleHog |
