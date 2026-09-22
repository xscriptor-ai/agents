# Security and Observability

Python-specific vulnerabilities (deserialization, injection, secrets), password hashing, supply chain, structured logging, OpenTelemetry, metrics, health checks, and error tracking.

## Threat Map

| Vulnerability | Python surface | Primary mitigation |
|---|---|---|
| RCE via deserialization | `pickle`, `marshal`, `yaml.load`, `dill`, `joblib.load`, `torch.load` | Never deserialize untrusted data; signed/typed formats |
| SQL injection | f-string/format SQL, `text()` misuse, raw cursors | Bound parameters; ORM expressions; allowlist identifiers |
| Command injection | `os.system`, `subprocess(shell=True)` | Argument lists; `shlex.quote` when a shell is unavoidable |
| Path traversal | `os.path.join` with user input, archive extraction | `Path.resolve()` + `is_relative_to`; extraction filters |
| Secrets exposure | `.env` commits, logs, error reports, image layers | Secret managers, redaction, scanning |
| Weak password storage | MD5/SHA1, home-grown schemes, stale `passlib` | Argon2id or bcrypt with current libraries |
| SSRF | `requests`/`httpx` to user-controlled URLs | Allowlists, block private/metadata ranges, timeouts |
| XML attacks | `xml.etree` entity expansion | `defusedxml`; disable external entities |
| Timing attacks | `==` on tokens/HMACs | `hmac.compare_digest` |
| Supply chain | Typosquatting, dependency confusion, stolen tokens | Lockfiles, audits, trusted publishing, SBOM |

## Deserialization

- `pickle` executes arbitrary code by design (`__reduce__`). No sandbox makes untrusted
  pickle safe. The same applies to `dill`, `joblib.load`, and most `torch.load` payloads.
- `yaml.load` without a safe loader is code execution. Use `yaml.safe_load`; even then,
  alias expansion can be a DoS — cap document size and disable aliases where possible.
- `marshal` is for `.pyc` files, not data exchange; it is not a security boundary.
- `torch.load`: use `weights_only=True` where supported and prefer `safetensors` for model
  weights (verify upstream support in your framework version).
- Safe interchange: JSON, msgpack, protobuf, CBOR; add HMAC/Ed25519 signatures when
  integrity matters, and validate the schema with pydantic.
- Cache/session stores: store JSON, not pickled objects, so a compromised store cannot
  achieve RCE.

**Anti-patterns**

- `pickle.loads(redis.get(key))` "because it is faster".
- `yaml.load(stream)` without `Loader=` on config uploaded by users.
- Deserializing model checkpoints from public hubs without provenance and weights-only
  loading.

## Injection

### SQL

```python
from sqlalchemy import text

await session.execute(
    text("select id from users where email = :email"), {"email": email}
)
```

- ORM expression builders parameterize automatically; `text()` is safe only with bound
  parameters.
- Identifiers (table/column names) cannot be bound: choose them from an allowlist, never from
  request input.
- Stored procedures and raw `cursor.execute` calls need the same discipline; review every
  string that reaches a database.

### OS commands

```python
import shutil, subprocess

path = shutil.which("git")
if path is None:
    raise RuntimeError("git not found")
subprocess.run([path, "clone", "--depth", "1", url], check=True)
```

- Never `shell=True` with interpolated input; if a shell is truly required, `shlex.quote`
  every value and prefer fixed command templates.
- Validate and canonicalize file paths before passing them to subprocesses.

### Templates and HTML

- Jinja2: keep `autoescape=True` for HTML (framework defaults do this); never render
  user-controlled template source (`Template(user_input)` is RCE).
- `SandboxedEnvironment` reduces, but does not eliminate, risk from untrusted authors.
- Avoid `Markup`/`|safe` on user data; sanitize rich text with a dedicated library.

### Paths and archives

```python
from pathlib import Path

base = Path("/srv/data").resolve()
candidate = (base / user_path).resolve()
if not candidate.is_relative_to(base):
    raise ValueError("path traversal")
```

- `os.path.join` with an absolute component discards the base; resolve and verify containment
  instead.
- `tarfile`: pass `filter="data"` (3.12+) — the default in newer CPython — and still bound
  extraction size and member count.
- `zipfile`: validate resolved member paths and refuse absolute or `..` entries; cap
  decompressed size (zip bombs).
- XML: `defusedxml` for untrusted documents; disable DTD/entity resolution.
- SSRF: allowlist schemes/hosts, resolve DNS and block private ranges plus the cloud
  metadata address (169.254.169.254), disable redirects or re-validate each hop, set short
  timeouts.

**Anti-patterns**

- `eval`, `exec`, or `ast.literal_eval` misused as a parser (use JSON/pydantic).
- Fetching `webhook_url` supplied by a user without SSRF controls.
- Building shell strings by concatenation, however "internal" the endpoint.

## Secrets Management

- Source of truth: a secret manager (Vault, AWS/GCP/Azure secret manager) or the platform's
  environment injection. `.env` is a local convenience, never a production secret store.
- Never commit `.env`; add it to `.gitignore`, `.dockerignore`, and secret-scanning hooks
  (gitleaks/trufflehog) in CI.
- Wrap secrets in `SecretStr` or a similar type so accidental `repr`/logging does not leak
  them; call `get_secret_value()` explicitly.
- Do not log headers, cookies, tokens, or request bodies containing credentials. Configure
  redaction in the logger and in error tracking.
- Prefer short-lived credentials: OIDC workload identity, instance roles, dynamic database
  credentials. Rotate on exposure and on schedule.
- Generate tokens and IDs with `secrets`, never `random`.

## Password Hashing

```python
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

hasher = PasswordHasher()
stored = hasher.hash(password)
try:
    hasher.verify(stored, password)
except VerifyMismatchError:
    raise
```

- Argon2id (argon2-cffi) is the default recommendation; tune time/memory to roughly
  50-100 ms on production hardware and store the parameters with the hash.
- bcrypt is acceptable with cost >= 12; remember it truncates beyond 72 bytes and needs
  explicit handling (pre-hash with SHA-256 or reject long inputs).
- `hashlib.scrypt`/`pbkdf2_hmac` are acceptable stdlib fallbacks; PBKDF2 iteration counts
  must track current guidance.
- `passlib` is unmaintained and incompatible with modern bcrypt releases — do not start new
  projects on it. Use `argon2-cffi` directly or a maintained wrapper such as `pwdlib`
  (verify upstream).
- Never store passwords reversibly; never log or email them; enforce a strong minimum and
  rate-limit authentication attempts.
- Compare hashes and tokens with `hmac.compare_digest`, not `==`.

## Tokens and Sessions

- JWT: use PyJWT and an explicit `algorithms=["RS256"]` (or similar) allowlist; reject
  `alg: none`; validate `exp`, `nbf`, `aud`, `iss`; handle clock skew and JWKS rotation.
- `python-jose` is effectively unmaintained; prefer PyJWT unless you need its specific
  algorithms.
- Keep JWT payloads minimal; they are signed, not secret. Use opaque server-side sessions
  when revocation matters.
- Session IDs: `secrets.token_urlsafe(32)`; rotate on login and privilege change; set
  `HttpOnly`, `Secure`, `SameSite=Lax/Strict`; scope cookies tightly.
- Short access-token lifetimes plus refresh rotation; revoke refresh tokens on reuse
  detection.

## Crypto Hygiene

- `cryptography` (AES-GCM, Ed25519, X25519) for real cryptography; never implement primitives.
- `hashlib.sha256`/BLAKE2 for integrity, not passwords; `hmac` for MACs with
  `compare_digest`.
- Keep TLS verification enabled everywhere (`httpx`, `requests`, DB drivers); never
  `verify=False` outside a documented test.
- Pin and update crypto dependencies; CVEs in these libraries are high impact.

## Supply Chain

- Install from a lockfile; use hash checking where the workflow supports it.
- Run `pip-audit` (or `osv-scanner`) on the lockfile in CI and fail on known
  vulnerabilities, with a documented, time-boxed exception process.
- Static analysis: `bandit` and/or `ruff` security rules (`S`) in the lint gate; add
  `semgrep` rules for organization-specific policies.
- Generate an SBOM (CycloneDX via `cyclonedx-py`, or `syft`) per release and store it with
  the artifact.
- Use PyPI trusted publishing with build provenance; do not keep long-lived tokens in CI.
- Dependency confusion: prefer a single curated index/proxy (devpi, Artifactory) and avoid
  mixing `--extra-index-url` with public indexes on private package names.
- Review new transitive dependencies; typosquatted names are a common entry point.

## Structured Logging

```python
import structlog

structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ],
)
log = structlog.get_logger()
log.info("user_created", user_id=7)
```

- structlog gives processors and `contextvars` binding; loguru is simpler with less
  structured control; stdlib `logging` with `dictConfig` remains valid.
- Production: JSON to stdout; development: human-readable console renderer.
- Log events with structured fields, not interpolated prose; keep a stable event name for
  search/alerting.
- Bind `request_id`/`trace_id` with contextvars at the boundary; `asyncio.to_thread`
  propagates context, raw executor calls do not.
- Redact secrets/PII centrally (processor/serializer), not per call site.
- Never log full request bodies, auth headers, tokens, or credentials.

## OpenTelemetry, Metrics, Health

```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("charge_card") as span:
    span.set_attribute("payment.provider", "stripe")
```

- Auto-instrumentation (`opentelemetry-instrument`, `opentelemetry-instrumentation-fastapi`,
  `-sqlalchemy`, `-httpx`) covers most stacks; add manual spans only around domain
  operations.
- Propagate trace context across queues and RPC: inject/extract with the W3C trace-context
  propagator; carry `trace_id` in log fields.
- Sampling: parent-based plus a rate limit in production; never sample errors away. Capture
  exception events on spans for error correlation.
- Metrics with `prometheus-client`: counters, histograms, gauges; follow RED
  (rate/errors/duration) for services and USE for resources.
- Label cardinality is the classic outage: never label with user IDs, raw URLs, or
  unbounded values. Aggregate into buckets.
- Health endpoints: `/healthz` (liveness, no dependencies) and `/readyz` (dependency checks
  with tiny timeouts and cached results). Probes must not hammer the database or perform
  migrations.

## Error Tracking

- Sentry (`sentry-sdk[fastapi]`) or equivalent: set `environment`, `release` (git SHA),
  `traces_sample_rate`, and PII scrubbing (`send_default_pii=False` plus explicit
  `before_send` redaction).
- Capture once at the boundary; avoid duplicate events from both middleware and handlers.
- Add context (request id, route, version) but never credentials or full payloads.
- Alert on new issue types, regressions, and error-rate SLO burn, not on every event.
- Test that scrubbing actually removes your secret fields before enabling in production.

## Anti-Patterns

- Unpickling anything that crossed a network or trust boundary.
- `subprocess` with `shell=True` and interpolated input.
- SQL built with f-strings; identifiers taken from requests.
- Logging tokens, cookies, passwords, or full request bodies.
- MD5/SHA1 password hashes, or `==` comparisons of secrets.
- Disabling TLS verification to "make it work".
- Secrets baked into images or committed `.env` files.
- Unbounded metric labels, log lines without request correlation.
- Extracting archives or fetching URLs supplied by users without validation.

## Checklist

- [ ] No unsafe deserialization on untrusted input; signed formats where integrity matters.
- [ ] All SQL parameterized; identifiers allowlisted; no shell interpolation.
- [ ] Path containment and archive extraction validated; SSRF controls on outbound fetches.
- [ ] Secrets from a manager, wrapped, redacted, scanned in CI.
- [ ] Password hashing with a maintained Argon2id/bcrypt implementation and sane parameters.
- [ ] JWT/session handling validates algorithms, lifetimes, audiences; tokens compared in
      constant time.
- [ ] Lockfile + `pip-audit` + static security lint + SBOM in the release process.
- [ ] Structured JSON logs with request/trace IDs and centralized redaction.
- [ ] Traces/metrics exported with bounded label cardinality; errors captured without PII.
- [ ] Liveness/readiness separated and cheap; alerting tied to SLOs.
