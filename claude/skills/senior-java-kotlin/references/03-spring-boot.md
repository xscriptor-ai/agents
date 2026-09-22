# Spring Boot

Scope: building and reviewing Spring Boot services: dependency injection, configuration, web stack choice, validation, error handling, security, actuators, and AOT/native.

## Version baseline

| Component | Range | Notes |
| --- | --- | --- |
| Spring Boot 3.x | 3.5+ (maintenance) | Java 17 baseline, Jakarta EE 10, Framework 6, Security 6 |
| Spring Boot 4.x | current line | Framework 7, Jakarta EE 11, JSpecify null-safety, API versioning; verify exact versions and renamed modules upstream |
| Java | 17+ for Boot 3.x, 21 recommended | Boot 4 targets the modern JDK; run on 21 or 25 LTS |
| Kotlin | 2.x | K2 compiler, coroutine support; `kotlin("plugin.spring")` for open classes |
| Build | Gradle Kotlin DSL or Maven | Gradle preferred in this pack (`./06-build-tooling.md`) |
| Native | GraalVM for JDK 21/25 | Spring AOT plus runtime hints; test thoroughly (`./10-migration-modernization.md`) |

Rules:

- Always use a dependency management BOM or the Boot plugin's managed versions; never hand-pin framework artifacts.
- Do not run a Boot 4 major upgrade and a Java major upgrade in the same PR; upgrade one axis at a time.
- Keep `spring-boot-starter-*` dependencies minimal; each starter adds auto-configuration you must understand and secure.

## Dependency injection

Constructor injection with final fields; the container is a wiring detail, not a pattern.

```java
@RestController
@RequestMapping("/api/v1/users")
class UserController {
    private final UserService service;
    UserController(UserService service) { this.service = service; }

    @GetMapping("/{id}")
    UserResponse get(@PathVariable long id) {
        return UserResponse.from(service.find(id));
    }
}
```

Guidelines:

- One public constructor per bean; no `@Autowired` needed with a single constructor (Java and Kotlin).
- `@Component` for classes you own; `@Bean` methods for third-party types and explicit wiring. Keep `@Configuration` classes grouped by concern.
- Prefer `ApplicationContext`-free domain code: no `@Autowired` fields in domain objects, no `BeanFactory` lookups in logic.
- `@Qualifier` beats `@Primary` when two beans of a type are legitimate; `ObjectProvider<T>` for optional/lazy dependencies.
- Circular dependencies indicate a design problem. Do not paper over them with `@Lazy` without a plan to break the cycle.
- `@ConfigurationProperties` beans should be records or immutable classes; validate at startup.
- In Kotlin, class bodies are final by default. The Spring plugin opens `@Component`/`@Configuration` classes; use `@ConfigurationProperties` data classes with `@ConstructorBinding` semantics (constructor binding is the default in Boot 3+).
- Request scope and prototype scope need proxies and careful lifecycle handling; prefer passing data as parameters.

Anti-patterns:

- Field injection with `@Autowired`; it hides dependencies and blocks immutability.
- `@ComponentScan` on the application class spanning unrelated packages; keep scans narrow.
- Static/global access to beans via a holder; breaks tests and ordering.
- Injecting a `Map<String, Foo>` and doing runtime dispatch when strategy selection is a domain decision.

## Configuration

```java
@ConfigurationProperties(prefix = "app.payments")
@Validated
public record PaymentsProperties(
    @NotBlank String baseUrl,
    @Positive Duration timeout,
    @Min(1) @Max(64) int maxConnections,
    List<String> allowedCurrencies) {}
```

Rules:

- Externalize all environment-specific values. No defaults that silently point at production, no secrets in `application.yml`.
- Use profile-specific files (`application-prod.yml`) and environment variables in deploy environments; use `spring.config.import` for vaults/config servers.
- Validate configuration at startup: `@Validated` + Bean Validation on properties records; fail fast beats undefined behavior at runtime.
- Prefer typed properties over scattered `@Value`; `@Value` is for one-off, non-domain values only.
- Relaxed binding maps `APP_PAYMENTS_BASE_URL` to `app.payments.base-url`; document the environment mapping.
- Immutable maps/lists in properties; defensive-copy if the source can be mutated.
- Feature flags live in config, not code; but avoid config that changes code paths so much that testing them all is impossible.
- Keep `application.yml` short; if it grows past a page, split by concern with `spring.config.import`.

Anti-patterns:

- Secrets committed in YAML or default passwords in test configs that bleed into production.
- `@Value("${...}")` with `:` defaults masking missing configuration.
- Profile proliferation (`dev1`, `dev2`, `local-john`) instead of documented base plus overrides.

## Web stack: MVC vs WebFlux

| Criterion | Spring MVC | WebFlux |
| --- | --- | --- |
| Concurrency model | Thread-per-request (platform or virtual) | Event loop, non-blocking |
| Blocking libraries | Fine (JDBC, JPA, blocking HTTP) | Forbidden on event loops |
| Backpressure | Not applicable per request | `Flux`/`Mono` backpressure |
| Virtual threads | Excellent fit: `spring.threads.virtual.enabled=true` | Largely unnecessary |
| Streaming/SSE/websockets with many connections | Limited threads help, but memory per connection is the cost | Strong fit |
| Complexity | Low | High; reactive all the way down |
| Debugging | Familiar stacks | Async stack traces, harder context propagation |

Decision rules:

- Default to MVC. Use virtual threads for I/O concurrency rather than adopting reactive code.
- Choose WebFlux only when you need non-blocking end-to-end (R2DBC, reactive clients), streaming with backpressure, or extreme connection counts with low memory.
- Never mix blocking JDBC into a WebFlux handler; offload to `boundedElastic` only as a stopgap and measure.
- Do not migrate a working MVC service to WebFlux for performance without a measured problem and a plan for the full chain.
- For synchronous outbound calls prefer `RestClient` (blocking) or `WebClient` (reactive) and declare clients as HTTP interfaces with `@HttpExchange`.

```java
@HttpExchange(url = "/v1/orders", accept = "application/json")
interface OrdersClient {
    @GetExchange("/{id}")
    Order get(@PathVariable String id);
}
```

- Register clients with `HttpServiceProxyFactory` or the Boot auto-configuration; configure timeouts and retries explicitly.
- Timeouts are mandatory on every client: connect, read, and total request timeout. Retries only for idempotent operations with jittered backoff and a budget.

Anti-patterns:

- Returning entities directly from controllers; use DTOs/records.
- Blocking calls in reactive chains (`block()`, JDBC, `Thread.sleep`).
- Unbounded `WebClient` fan-out; apply concurrency limits and timeouts.
- Building a "generic" controller abstraction; the framework already provides routing.

## Validation and error handling

```java
record CreateUser(@NotBlank @Email String email, @Min(18) int age) {}

@RestControllerAdvice
class ApiErrors extends ResponseEntityExceptionHandler {
    @ExceptionHandler(NotFound.class)
    ProblemDetail notFound(NotFound e) {
        ProblemDetail p = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
        p.setType(URI.create("https://api.example.com/problems/not-found"));
        return p;
    }
}
```

Rules:

- Validate at the boundary: `@Valid` on request bodies and query parameters, `@Validated` on configuration properties and beans with method validation.
- Use RFC 9457 `ProblemDetail` for error responses; consistent problem types and machine-readable `type` URIs.
- Map exceptions to HTTP statuses in one place (`@RestControllerAdvice`); controllers should not catch what they cannot handle.
- Never leak stack traces, SQL, class names, or internal identifiers in error payloads; log them with a correlation ID instead.
- Distinguish client errors (400/409/422) from server errors (500); do not return 200 with an error body.
- Validation messages are user-facing strings: keep them in a message source for i18n and avoid English-only inline text in libraries.
- For Kotlin, use `@field:` targeted annotations on constructor properties when validation annotations must land on fields.

Anti-patterns:

- `@Valid` on the controller class instead of parameters.
- Catching `Exception` in controllers and returning `500` for everything.
- Custom error format that changes shape per endpoint.
- Throwing exceptions from `equals`/`hashCode` or domain invariants during serialization.

## Security

```java
@Configuration
@EnableMethodSecurity
class SecurityConfig {
    @Bean
    SecurityFilterChain api(HttpSecurity http) throws Exception {
        return http
            .securityMatcher("/api/**")
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/public/**").permitAll()
                .anyRequest().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .csrf(AbstractHttpConfigurer::disable)
            .build();
    }
}
```

Guidelines:

- Lambda DSL only. `WebSecurityConfigurerAdapter` is gone; do not copy old tutorials.
- Deny by default: `anyRequest().authenticated()`. Explicitly permit the small public surface.
- Stateless APIs: JWT resource server validation (issuer, audience, JWKS rotation, clock skew). Sessions and cookies only for browser apps with CSRF enabled.
- Method security (`@PreAuthorize`, `@PostAuthorize`) for domain-level authorization; do not scatter role checks in controllers.
- Password storage: Argon2id or bcrypt with per-user salt; never SHA/MD5, never custom crypto.
- CSRF applies to cookie/session-based clients. Disabling it is safe only for token-authenticated, non-browser clients.
- CORS: explicit origins, methods, headers; never `*` with credentials.
- Headers/transport: HSTS, secure cookies (`HttpOnly`, `Secure`, `SameSite`), TLS everywhere in production; trust proxies only when configured deliberately.
- Security events are logged; sensitive data in auth failures is not (see `./09-observability-security.md`).
- Dependencies: pin and scan; Security advisories map to Boot patch releases — stay current on the maintenance line.

Anti-patterns:

- Rolling your own JWT parsing/validation instead of the resource server support.
- Role checks encoded as URL string matching with path patterns that can be bypassed by encoding tricks.
- Shared long-lived API keys in config files.
- Disabling CSRF on cookie-authenticated endpoints "because tests fail".

## Actuators

- Expose only what is needed: `management.endpoints.web.exposure.include=health,info,prometheus` by default; everything else through the management port, bound to the internal network.
- Health groups: `liveness` must be independent of dependencies (DB down must not kill the pod); `readiness` may include critical dependencies.
- `management.endpoint.health.show-details=when-authorized` at most; details leak topology.
- Metrics should flow to a registry (Prometheus/OTLP) with consistent tags; avoid high-cardinality tags like user IDs (`./09-observability-security.md`).
- Startup probes for slow-starting apps; `management.endpoint.startup.enabled=true` with `ApplicationStartup` tracking where needed.
- Thread dumps, heap dumps, env/configprops endpoints are powerful attack surface; secure or disable them.

Anti-patterns:

- Exposing `/actuator/env`, `/actuator/heapdump`, or `/actuator/loggers` to the public internet.
- Liveness checks hitting the database; restarts will cascade during DB incidents.
- Custom health indicators that perform expensive upstream calls on every probe.

## AOT, native, and startup

- Spring AOT processes the context at build time: reflection hints, proxy hints, resource hints. Most auto-configuration ships hints; third-party libraries may not.
- GraalVM native image gives fast startup and low memory for CLI/serverless, at the cost of build time, closed-world constraints, and slower peak optimization in some workloads.
- Native constraints: no dynamic class loading, limited reflection, runtime proxies and serialization need registration, `ClassPathScanningCandidateComponentProvider` behavior differs.
- Build with the Boot Gradle/Maven plugin plus the GraalVM native plugin; run the full integration test suite against the native binary, not just unit tests.
- JVM AOT caches (class-loading and method-profiling AOT in recent JDKs) reduce startup without a native image; consider them before taking the native complexity (`./10-migration-modernization.md`, `./05-jvm-performance.md`).
- Keep profiles and conditional beans simple; AOT makes complex `@Conditional` graphs hard to reason about.
- Measure: startup time, RSS, first-request latency, throughput under sustained load. Do not choose native on startup alone.

Anti-patterns:

- Assuming native works because the app starts; exercising only health endpoints.
- Reflection-heavy serialization/config libraries without hints.
- Two build pipelines (JVM and native) that diverge in configuration.

## Testing slices (pointer)

- `@WebMvcTest`, `@DataJpaTest`, `@JdbcTest`, `@SpringBootTest` and `@ServiceConnection` are covered in `./07-testing.md`.

## Review checklist

- [ ] Constructor injection; no field injection or context lookups in domain code.
- [ ] Config validated at startup, secrets externalized, no production defaults.
- [ ] MVC chosen by default; virtual threads enabled; blocking calls have timeouts.
- [ ] ProblemDetail error model; no internal details leaked.
- [ ] Security: deny by default, stateless JWT or CSRF-correct sessions, method security, no wildcard CORS.
- [ ] Actuator surface minimal and secured; liveness independent of dependencies.
- [ ] Native/AOT evaluated against measured startup and memory goals.
- [ ] Boot maintenance line kept current; upgrade path to the next major planned (`./10-migration-modernization.md`).
