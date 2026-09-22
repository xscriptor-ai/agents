# Per-Language Cheatsheets

Scope: sharp-edge secure-coding rules and safe-API mappings for Python, TypeScript/Node, Go, Rust, Java/Kotlin, and C/C++, with links to the sibling language packs for depth.

## Generic Rules That Apply Everywhere

- Use a typed, schema-validating boundary (DTOs) instead of passing request data through maps,
  dictionaries, or dynamic objects.
- Parameterize every interpreter path; allowlist identifiers (see
  [./01-injection.md](./01-injection.md)).
- Import secrets from the environment or a secrets manager, never from source; scan commits in CI
  (see [./04-crypto-secrets.md](./04-crypto-secrets.md) and [./07-dependencies.md](./07-dependencies.md)).
- Wrap user data at the output sink with the context encoder; never trust a previous "clean" step.
- Turn on the language's security linters and fail the build on new high-severity findings
  (see [./08-review-checklist.md](./08-review-checklist.md)).

## Python

Depth pack: [../../python/SKILL.md](../../python/SKILL.md) (3.12-3.14 idioms, pydantic v2,
SQLAlchemy 2.0, FastAPI hardening).

| Risk | Unsafe | Safe |
|---|---|---|
| SQL | f-string into `execute` | driver placeholders; SQLAlchemy bound params |
| Command | `os.system`, `shell=True` | `subprocess.run([...], shell=False, check=True)` |
| Deserialization | `pickle.loads`, `yaml.load` | `json`, `yaml.safe_load`, pydantic models |
| XML | `xml.etree` default parser (XXE) | `defusedxml`; disable entities |
| Randomness | `random`, `uuid.uuid1` | `secrets.token_urlsafe`, `os.urandom` |
| Comparison | `==` on tokens/MACs | `hmac.compare_digest` |
| Paths | string concat with `..` | `pathlib.Path.resolve()` + `is_relative_to` |
| Templates | `render_template_string(user)` | render named templates with context data |
| Hashing | `hashlib.md5/sha1` | `argon2-cffi` for passwords; SHA-256 for integrity |
| TLS | `verify=False`, old protocols | default verification; `ssl` with TLS 1.2+ |

Django-specific: keep `DEBUG=False`, set `SECURE_*` settings, use `CSRF_*` middleware, never
`mark_safe` on user data, use `get_object_or_404` with user-scoped querysets, set
`ALLOWED_HOSTS`, and prefer `django.core.signing` for signed cookies. FastAPI/Starlette:
pydantic with `extra="forbid"`, explicit response models, and dependency-injected authz.

## TypeScript / Node

Depth pack: [../../typescript/SKILL.md](../../typescript/SKILL.md) (runtimes, frameworks, Node
backend patterns).

| Risk | Unsafe | Safe |
|---|---|---|
| Command | `exec`, `execSync` with interpolation | `execFile`/`spawn` with args, `shell: false` |
| SQL | template literals in queries | driver placeholders + values array |
| Prototype pollution | `Object.assign(target, userObj)`, deep-merge libs | validate keys; `Object.create(null)`; ban `__proto__`/`constructor` keys |
| Deserialization | `node-serialize`, `eval`, `new Function`, `vm` as sandbox | `JSON.parse` + Zod/Valibot; no dynamic code |
| XSS | `innerHTML`, `dangerouslySetInnerHTML` with raw data | `textContent`; sanitizer; CSP/Trusted Types |
| Randomness | `Math.random` for tokens | `crypto.randomBytes`, `crypto.randomUUID` |
| Comparison | `===` on MACs/tokens | `crypto.timingSafeEqual` |
| Paths | `path.join(base, userInput)` alone | resolve + `startsWith(base + path.sep)` |
| Headers/CORS | reflecting `Origin` | explicit allowlist; Helmet-style defaults |
| Regex | user-built `new RegExp` | escape input; safe-regex checks; timeouts |

Note: `node:vm` is not a security boundary and can be escaped; do not use it to run untrusted code.
For untrusted JavaScript execution, isolate in a separate process or WASM sandbox with resource
limits. In frameworks, prefer `helmet`-style header baselines and CSRF middleware, and bind
payloads to DTO schemas instead of `as` casts.

## Go

Depth pack: [../../go/SKILL.md](../../go/SKILL.md) (database/sql, pgx, routing, supply chain).

| Risk | Unsafe | Safe |
|---|---|---|
| SQL | `fmt.Sprintf` into `db.Query` | `QueryContext` with `$1`/`?` placeholders |
| Command | `exec.Command("sh", "-c", ...)` | `exec.Command(binary, args...)`; `-`/`--` guard |
| Templates | `text/template` for HTML | `html/template` (contextual auto-escaping) |
| Deserialization | `gob` across trust boundaries, YAML into `interface{}` | `encoding/json` into typed structs |
| Randomness | `math/rand` | `crypto/rand`; `rand/v2` still not for secrets |
| Comparison | `==` on tokens | `crypto/subtle.ConstantTimeCompare` |
| Paths | `filepath.Join` then open | `filepath.Clean` + `filepath.Rel` prefix check |
| TLS | zero-value `tls.Config` in some paths; `InsecureSkipVerify: true` | explicit `MinVersion: tls.VersionTLS12`, verified chains |
| Secrets | struct tags/logging configs | env/secrets manager; redact `slog` attributes |

Run `go vet`, `gosec`, `govulncheck`, and the race detector in CI. Prefer `crypto/rand` even for
non-secret IDs if they appear in access control, and be careful with `unsafe` and `reflect` around
untrusted input.

## Rust

Depth pack: [../../rust/SKILL.md](../../rust/SKILL.md) (ownership, async, unsafe/FFI review,
sqlx/axum, cargo workflows).

| Risk | Unsafe | Safe |
|---|---|---|
| SQL | `format!` into `sqlx::query` | `sqlx::query!`/`query_as!` or `.bind(value)` |
| Command | `sh -c` with interpolated string | `Command::new(binary).args([...])` with validation |
| Secrets | `String` secrets copied everywhere | `secrecy::SecretString`, `zeroize` on drop |
| Randomness | `fastrand`, `thread_rng` for secrets | `rand::rngs::OsRng` / `getrandom` |
| Comparison | `==` on MACs | `subtle::ConstantTimeEq` |
| Deserialization | `serde_json::Value` then unchecked casts | typed structs, `deny_unknown_fields`, validation |
| Crypto | hand-rolled `unsafe` crypto | `ring`, `rustls`, `aws-lc-rs`, `argon2`, `chacha20poly1305` |
| FFI | unchecked pointer/length from C | `try_into`, checks before `unsafe`, document invariants |

Cargo hygiene: commit `Cargo.lock`, run `cargo audit` and `cargo deny` (licenses, bans, advisories),
avoid unnecessary `unsafe`, and add `#![forbid(unsafe_code)]` in crates that do not need it. Audit
proc-macro and build-script dependencies as executable code in the build.

## Java / Kotlin

Depth pack: [../../java-kotlin/SKILL.md](../../java-kotlin/SKILL.md) (JDBC/JPA, Spring Security,
serialization, Gradle/Maven).

| Risk | Unsafe | Safe |
|---|---|---|
| SQL | `Statement` + concat, HQL concat | `PreparedStatement`, JPA `setParameter`, Criteria API |
| Command | `Runtime.exec(String)` | `ProcessBuilder(List.of(...))` with validation |
| Deserialization | `ObjectInputStream`, Jackson default typing, Fastjson autotype, XStream | fixed DTOs; `PolymorphicTypeValidator` allowlist; no native serialization |
| XML | `DocumentBuilderFactory` defaults (XXE) | disable DTDs and external entities; `XMLConstants` features |
| YAML | `new Yaml()` unsafe load | `SafeConstructor` with explicit types |
| Randomness | `java.util.Random`, `Math.random` | `SecureRandom` |
| Comparison | `Arrays.equals` on MACs | `MessageDigest.isEqual` |
| Expression languages | SpEL/OGNL/MVEL with user input | never evaluate user input; use data binding |
| Logging | user data into log messages unescaped | parameterized logging; CRLF encoding |
| Paths | `new File(base, userInput)` | `Path.normalize` + `startsWith(base)` after `toRealPath` |
| Crypto | `Cipher.getInstance("AES")` (ECB) | `AES/GCM/NoPadding` with random IV; BouncyCastle where needed |

Kotlin: string templates (`` "SELECT ... $id" ``) are a common reintroduction of SQL injection; the
same parameterization rules apply. Spring Boot: secure defaults, CSRF enabled for cookie sessions,
method security annotations enforced, actuator endpoints protected, and no entity binding directly
from request bodies. Note that the SecurityManager is disabled/removed in recent JDKs, so do not
design sandboxing around it; isolate untrusted code in processes or containers instead.

## C / C++

Depth pack: [../../systems/SKILL.md](../../systems/SKILL.md) (systems, memory, tooling context).

| Risk | Practice |
|---|---|
| Buffer overflows | Use `snprintf`, `std::string`/`std::span`, bounds-checked containers; never `strcpy`, `strcat`, `gets`, `sprintf` |
| Integer overflow | Check before arithmetic; use `__builtin_*_overflow`, `std::ckd*` (C++26, verify upstream) or explicit checks; size before allocation |
| Use-after-free / double free | RAII, smart pointers, ownership annotations; sanitizers in CI |
| Format strings | Never pass user data as the format: `printf("%s", user)` |
| Secrets in memory | Zero with `explicit_bzero`/`memset_s`; disable core dumps; avoid swapping secrets |
| Parsing untrusted input | Fuzz with libFuzzer/AFL++ and run ASan/UBSan/MSan; avoid recursive descent without depth limits |
| Command execution | `execve` with argv arrays; never `system()`/`popen()` with user data |
| Randomness | `getrandom(2)`/`BCryptGenRandom`/`SecRandomCopyBytes`; never `rand()` |
| Crypto | OpenSSL/libsodium/BoringSSL; check return values; no custom memory comparison |
| Compiler hardening | `-D_FORTIFY_SOURCE=3`, `-fstack-protector-strong`, `-fPIE -pie`, `-Wl,-z,relro,-z,now`, `_GLIBCXX_ASSERTIONS`, CFI where available |

C23 and modern C++ reduce some classes (bounds-checked APIs, `std::span`, `constexpr` validation)
but do not eliminate the need for fuzzing and sanitizers. Treat every `memcpy`, pointer arithmetic,
and integer conversion as a review checkpoint.

## Tooling Matrix

| Language | SAST / Lint | Dependency audit | Fuzzing / Runtime |
|---|---|---|---|
| Python | Bandit, Semgrep, ruff (`S` rules) | pip-audit, uv audit, OSV-Scanner | Atheris, Hypothesis |
| TS/Node | ESLint security plugins, Semgrep, CodeQL | npm/pnpm audit, OSV-Scanner | Jazzer.js, fast-check |
| Go | gosec, staticcheck, govulncheck | govulncheck, OSV-Scanner | native `go test -fuzz` |
| Rust | clippy (`-D warnings`), cargo-geiger | cargo-audit, cargo-deny, OSV-Scanner | cargo-fuzz, proptest |
| Java/Kotlin | SpotBugs + FindSecBugs, CodeQL, Semgrep | OWASP Dependency-Check, Gradle/Maven audit, OSV-Scanner | Jazzer |
| C/C++ | clang-tidy, CodeQL, Coverity | OSV-Scanner, Trivy | libFuzzer, AFL++, ASan/UBSan/MSan/TSan |

Pick tools that run in CI and fail on new high-severity findings; a scanner that nobody reads is
not a control (see [./08-review-checklist.md](./08-review-checklist.md)).

## Cross-Language Anti-Patterns

- "Framework X escapes for me" applied to raw/untrusted/unsafe escape hatches the framework offers.
- Copy-pasting a safe snippet from one language into another without the matching library.
- Relying on types at compile time for runtime data (casts, `as`, `interface{}`, `Any`).
- Custom crypto or custom token formats in the language's "simple" APIs.
- Security tooling installed but not enforced on pull requests.

## Checklist

- [ ] Each service has the language's SAST, audit, and secret-scanning tools wired into CI.
- [ ] No dynamic code execution (`eval`, `exec`, `new Function`, reflection-driven calls) on
      untrusted input.
- [ ] Native object deserialization is absent; formats are JSON/CBOR/protobuf with schemas.
- [ ] Command execution uses argv arrays with validated arguments.
- [ ] Secrets come from the environment or a manager; nothing is committed.
- [ ] Language-specific sharp edges from the table above are covered by tests.
