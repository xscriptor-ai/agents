# Observability and Security (JVM)

Scope: production visibility and defense for JVM services: Micrometer and OpenTelemetry, structured logging, authentication/authorization patterns, secrets, supply chain, and hardening.

## Telemetry stack

| Concern | Default choice | Notes |
| --- | --- | --- |
| Metrics API | Micrometer (`Observation`, meters) | Boot-native; bridges to Prometheus/OTLP |
| Tracing API | Micrometer Tracing or OpenTelemetry SDK | Pick one; OTel is the cross-language standard |
| Auto-instrumentation | OTel Java agent | Fastest path to traces for existing apps |
| Manual instrumentation | `Observation` API / OTel spans | For business-meaningful spans and attributes |
| Logs | JSON to stdout via Logback or Log4j2 | Ship with the platform's log pipeline |
| Profiling | JFR + async-profiler | Continuous JFR in production (`./05-jvm-performance.md`) |

Rules:

- One correlation story: generate or accept a trace/request ID at the edge, put it in MDC and spans, return it in error responses.
- Instrument business outcomes, not just infrastructure: checkout conversions, payment failures, queue lag per topic.
- Cardinality discipline: never tag metrics with user IDs, order IDs, raw URLs, or unbounded values. Traces can carry these as attributes; metrics cannot.
- Sampling: parent-based head sampling for high-traffic services; tail sampling at the collector when error/latency-biased retention is needed.
- Telemetry data is sensitive: redact PII and secrets from spans, logs, and metric tags. Assume telemetry leaves the trust boundary.

## Micrometer

```java
@Service
class CheckoutService {
    private final ObservationRegistry registry;

    CheckoutService(ObservationRegistry registry) { this.registry = registry; }

    CheckoutResult checkout(Cart cart) {
        return Observation.createNotStarted("checkout", registry)
            .lowCardinalityKeyValue("channel", cart.channel())
            .observe(() -> doCheckout(cart));
    }
}
```

Guidance:

- Use `Observation` (not separate timer/counter APIs) so metrics and traces are created consistently. `@Observed`/`@Timed` annotations for coarse coverage; manual observations for business context.
- Meter types: counter (monotonic counts), gauge (sampled values), timer (latency), distribution summary (sizes). Choose based on the question you need to answer.
- Histograms/percentiles: server-side histograms (Prometheus native histograms or client-side SLO buckets) beat per-instance quantiles; never average percentiles across instances.
- Long tasks (`LongTaskTimer`) for work that is currently running, useful for concurrency visibility.
- Naming: lowercase dot/dash conventions, stable names; treat metric names as API. Renames break dashboards and alerts.
- Tags: bounded dimensions only (status, route template, tenant tier). Use route patterns (`/users/{id}`), not raw paths.
- JVM binders (memory, GC, threads) are automatic in Boot; add pool and cache binders deliberately.

Anti-patterns:

- Metric explosion from per-user or per-request tags.
- Mixing timer and counter for the same signal with different semantics.
- SLOs defined on averages.
- Alerting on raw resource metrics instead of user-facing symptoms.

## OpenTelemetry and tracing

- Agent vs SDK: the Java agent gives zero-code spans for HTTP servers/clients, JDBC, Kafka; the SDK/API gives control. Many teams run the agent plus manual spans; document the mix.
- Semantic conventions: use stable `http.*`, `db.*`, `messaging.*` attributes; verify the current stability level before depending on newer names.
- Context propagation: W3C `traceparent` across services, `tracestate` for vendor data. Propagate through HTTP, messaging, and thread-pool boundaries; coroutines need the OTel context integration, not thread locals.
- Baggage: keep small and non-sensitive; it propagates everywhere and multiplies cardinality.
- Span kinds and naming: server spans named by route, client spans by target; avoid high-cardinality span names (raw URLs, IDs).
- Sampling: head sampling is cheap and predictable; tail sampling requires a collector and central policy. Document what "not sampled" means for incident response.
- Exporter: OTLP to a collector; batch export with retries; never block business threads on export (use the batch processor).
- Async: for message consumers, create a span per message linked to the producer context, and record receive/process latency separately.
- Coroutines: use the OTel context-aware dispatcher or `Context` propagation; spans opened in `launch` must close; consider `Observation` with `Context` propagation for Java.

Anti-patterns:

- Creating spans for every method call; tracing is for boundaries and meaningful work.
- Forgetting to end spans (leaks) or ending on a different thread without explicit context.
- Injecting trace IDs into logs but not into responses, making support triage blind.
- Treating trace data as compliant-by-default; it is personal data when it carries identifiers.

## Structured logging

```xml
<!-- logback.xml: JSON console, no file appenders in containers -->
<appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
  <encoder class="net.logstash.logback.encoder.LogstashEncoder">
    <includeMdcKeyName>traceId</includeMdcKeyName>
    <includeMdcKeyName>requestId</includeMdcKeyName>
  </encoder>
</appender>
```

Rules:

- JSON to stdout in containers; the platform ships and indexes. No file appenders, no size-based rotation inside the app.
- One event per log line with consistent fields: timestamp, level, logger, message, trace/span IDs, service, environment, tenant (hashed where needed).
- Parameterized logging (`log.info("user {} not found", id)`) not string concatenation; guard expensive debug logging with `isDebugEnabled` when building payloads.
- Levels: ERROR = actionable failure requiring attention; WARN = degraded but handled; INFO = state changes and business events; DEBUG/TRACE off in production (enable per logger temporarily).
- Never log secrets, tokens, passwords, full PANs, or raw request/response bodies. Redaction belongs in a shared utility, not per-caller memory.
- Exceptions: log once at the boundary with stack trace; inner layers either wrap or log, not both.
- Correlate with traces: MDC `traceId`/`spanId` populated by the tracing integration; if absent, generate a request ID at ingress (`./03-spring-boot.md`).
- Audit logs are a separate stream: append-only, immutable retention, access-controlled, and distinct from application logs.
- Beware log amplification: partial failures in fan-out loops can generate thousands of lines per request; rate-limit or aggregate.

Anti-patterns:

- `System.out.println` and frameworks that bypass the logging facade.
- Logging inside tight loops or per-row batch processing.
- PII in URLs/query strings (logged by access logs by default); redact query parameters.
- Different log formats per service, making cross-service search impossible.

## Authentication (authn)

| Pattern | Use when | Notes |
| --- | --- | --- |
| OIDC authorization code + PKCE | Browser/mobile user login | Never implicit flow; PKCE mandatory for public clients |
| Client credentials | Service-to-service with an IdP | Short-lived tokens, audience-restricted |
| mTLS | High-trust service mesh/internal | Strong identity, operational cost; pair with SPIFFE-style identities where available |
| JWT access tokens | Stateless API auth | Validate signature, issuer, audience, expiry, clock skew; cache JWKS with rotation |
| Opaque tokens + introspection | Central revocation required | Adds a network call per validation; cache carefully |
| Session cookies | Server-rendered browser apps | `HttpOnly`, `Secure`, `SameSite`; CSRF protection required |

Rules:

- Validate tokens at every service that consumes them; do not trust an upstream gateway's word unless it is in the same trust boundary (document that assumption).
- Enforce `aud` and `iss`; a token for another service is not a token for you.
- Clock skew tolerance is small and explicit; do not disable expiry checks.
- Token lifetime: access tokens minutes to an hour; refresh tokens rotated and revocable.
- Store tokens server-side only where necessary; on mobile use the platform keystore (see `./08-android.md`).
- Log authentication failures with reason codes but never log the token itself.
- Session fixation: rotate session IDs on login; invalidate on logout and privilege change.

Anti-patterns:

- Parsing JWTs without signature verification, or trusting `alg: none`.
- Long-lived tokens (days) used as API keys.
- Shared credentials between services.
- Custom crypto or token formats.

## Authorization (authz)

Patterns:

- RBAC: roles/scopes mapped to permissions; simple, but role explosion is common. Keep roles coarse and permissions fine-grained in code.
- ABAC/policy engines: central policies (OPA/Cedar-style), useful for complex, auditable rules; adds a decision service to the critical path.
- Resource-level checks: every read/write of a user-owned object must verify ownership or explicit sharing. IDOR (insecure direct object reference) is the most common API vulnerability.
- Multi-tenant isolation: tenant ID from the token, never from the request body; enforce at the data layer with tenant-scoped queries or row-level security.

Rules:

- Deny by default; allow lists only.
- Put authorization decisions at the service layer, not only the controller; defense in depth for internal callers.
- Do not rely on UI hiding; the API is the security boundary.
- Centralize policy in one module and test it; ad-hoc checks in controllers drift.
- Return 404 vs 403 deliberately for resource existence leakage.
- Test authorization with property/matrix tests (role × resource × action), not spot checks.

Anti-patterns:

- Role checks using string matching on URLs that can be bypassed with path encoding.
- Tenant ID taken from a header or query parameter without verification.
- Admin endpoints protected only by network location.
- Policy scattered across controllers, filters, and services with no single source of truth.

## Secrets management

- Source of truth: a managed store (HashiCorp Vault, cloud secret managers, Kubernetes Secrets backed by CSI/External Secrets). Never in Git, images, or environment defaults committed to the repo.
- Injection at runtime: mounted files, projected volumes, or short-lived credentials fetched by the app at startup with retry.
- Rotation: automated where possible; apps must tolerate credential changes (refresh, reconnect, re-read files) rather than caching forever.
- Least privilege per service and per environment; separate credentials for read replicas, queues, and caches.
- Encryption: TLS in transit everywhere including inside the cluster or mesh; KMS/HSM for at-rest keys; envelope encryption for sensitive columns if required.
- No secrets in logs, crash dumps, JFR recordings, or error reports; scrub heap dumps before sharing (`jhat`-style analysis on real dumps is a data exposure risk).
- Developers get scoped dev credentials, not production ones; break-glass access is logged and reviewed.

Anti-patterns:

- Secrets in `application.yml`, CI variables visible to all jobs, or Docker layers.
- One shared credential for all environments and services.
- Long-lived static keys where workload identity is available.
- Secrets in chat/tickets during incidents.

## Supply chain

- Lock dependency versions and verify checksums/signatures (`./06-build-tooling.md`); builds must fail on unexpected artifacts.
- Generate an SBOM (CycloneDX/SPDX) per release and store it with the artifact.
- Scan continuously: dependencies, container images, and IaC. Prioritize reachable, exploitable CVEs over raw counts.
- Sign artifacts (Sigstore/cosign) and attach provenance (SLSA-style build metadata) where the platform supports it.
- Pin CI actions/plugins by digest; treat CI as production infrastructure with least-privilege tokens.
- Base images: minimal, distroless or slim, pinned by digest, rebuilt on a schedule for OS patches.
- Keep an incident process for zero-days: identify affected artifacts via SBOM, patch, rebuild, redeploy, verify.
- Avoid unnecessary dependencies; every library is an attack surface and an upgrade obligation.

Anti-patterns:

- `curl | bash` installers in CI for critical tools.
- Scanners with no triage process; alert fatigue means real CVEs get ignored.
- Building releases from unverified local builds.
- Forked/abandoned dependencies with no upstream.

## JVM and service hardening checklist

- [ ] TLS verified with real trust stores; no `TrustAll`/`InsecureSkipVerify` equivalents.
- [ ] JVM serialization filters set (`jdk.serialFilter`) if Java serialization is used at all; prefer not to expose it.
- [ ] XML parsers configured against XXE (disable DTDs/external entities).
- [ ] Deserialization of untrusted data avoided or whitelisted (Jackson polymorphic typing disabled/instrumented carefully).
- [ ] Actuator/management endpoints secured or bound to an internal port (`./03-spring-boot.md`).
- [ ] Security headers (HSTS, `X-Content-Type-Options`, CSP where applicable) in place at the edge.
- [ ] Rate limiting and request size limits at ingress; timeouts everywhere.
- [ ] Dependency and image scanning in the pipeline; SBOM published.
- [ ] Error responses free of stack traces, SQL, or class names.
- [ ] Logs and traces redacted; audit log stream separate and immutable.
- [ ] `-XX:+HeapDumpOnOutOfMemoryError` paths are access-controlled; dumps treated as sensitive.
- [ ] Break-glass procedures documented, logged, and reviewed.

## Review checklist

- [ ] Metrics, traces, and logs correlated by a single request/trace ID.
- [ ] Cardinality bounded on every metric and tag.
- [ ] Structured JSON logs to stdout; no PII/secrets; audit stream separated.
- [ ] Token validation complete (signature, iss, aud, exp) with JWKS rotation.
- [ ] Authorization denies by default and enforces resource ownership and tenant isolation.
- [ ] Secrets from a managed store, rotated, never logged or committed.
- [ ] SBOM, signature, and provenance produced for releases; scanning triaged.
- [ ] Hardening checklist applied and verified by tests or config review, not memory.
