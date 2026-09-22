# Web Services and Data Layer

Scope: axum versus actix-web, tower middleware, serde, database access (sqlx/diesel/sea-orm), migrations, configuration, auth patterns, and graceful shutdown.

## Framework Decision Table

| Criterion | axum | actix-web |
|---|---|---|
| Ecosystem | tokio + tower + hyper, broad middleware reuse | custom runtime (actix-rt), mature plugin set |
| Extractors | trait-based, composable, typed | custom extractors via `FromRequest` |
| Middleware | `tower::Layer` (tower-http, tower limits, tracing) | `Transform`/`Service`, actix-specific |
| Learning curve | moderate, explicit types | moderate, macros (`#[get("/")]`) |
| WebSocket/gRPC | axum + `tokio-tungstenite`, `tonic` in the same server | actix actors, `actix-ws`; tonic separate |
| Performance | high (hyper-based) | high; benchmarks are workload-dependent — measure, do not trust microbenchmarks |
| Best fit | services already on tokio/tower; library-friendly | teams already on actix; heavy actor-style state |

Default for new projects in 2026: **axum**, because middleware, HTTP clients, gRPC (`tonic`), and tracing all share the tower/hyper stack. Choose actix-web when the team knows it and the application fits its model; do not mix both in one service.

## axum Essentials

- `Router` composition: `Router::new().route("/x", get(h).post(h2)).nest("/api", api).layer(TraceLayer::new_for_http())`.
- State: `Router::with_state(state)`; extract with `State<T>` where `T: Clone + Send + Sync + 'static`. Wrap in `Arc` when non-trivial; `Arc` the whole state once rather than per-field.
- Extractors run in order: body-consuming extractors (`Json`, `Form`) must be last. Extractors that fail return non-2xx by default via `IntoResponse`.
- Handlers return `impl IntoResponse`; use `Result<Json<T>, AppError>` and one `IntoResponse for AppError` mapping.
- Path/query: `Path<(u64, String)>`, `Path<Struct>`, `Query<Pagination>` with serde `Deserialize`.
- Custom extractor: implement `FromRequestParts` (no body) or `FromRequest` (consumes body) for auth/api-key.
- Sharing HTTP clients: `reqwest::Client` is `Clone` and pools connections; build once in state with timeouts.
- `axum` 0.7/0.8 era changed path syntax (`/{id}` instead of `/:id`) and removed `async_trait` requirements; verify exact API upstream.

```rust
#[derive(Clone)]
struct AppState { db: PgPool, http: reqwest::Client }

async fn get_user(State(s): State<AppState>, Path(id): Path<i64>) -> Result<Json<User>, AppError> {
    let user = queries::user_by_id(&s.db, id).await?.ok_or(AppError::NotFound)?;
    Ok(Json(user))
}
```

## tower Middleware

- Layers wrap services; order matters: outermost runs first on request, last on response. `ServiceBuilder::new().layer(A).layer(B).service(svc)` results in `A(B(svc))`.
- Recommended stack order (outer to inner): request id -> tracing -> timeout -> concurrency limit -> compression -> catch panic.
- tower-http: `TraceLayer`, `TimeoutLayer`, `CompressionLayer`, `CorsLayer`, `RequestIdLayer`, `SetRequestIdLayer`, `RequestBodyLimitLayer`, `ServeDir`/`ServeFile`.
- `tower::limit::ConcurrencyLimitLayer` and `tower::load_shed::LoadShedLayer` protect the service; combine with `tower::buffer::Buffer` carefully (buffer adds a task and queue).
- Rate limiting: `tower-governor` or custom keyed limiter; token buckets need shared state (`governor`).
- `ServiceBuilder` vs `Router::layer`: `Router::layer` applies to routes added before it; `route_layer` only runs on matched routes (so 404s skip auth). Use `route_layer` for auth.
- Middleware errors must map to responses; a layer returning a body must set content type and length consistently.
- Test layers by calling `router.oneshot(request)` (tower `ServiceExt`).

## Serde

- `#[derive(Serialize, Deserialize)]`; `#[serde(rename_all = "camelCase")]`, `#[serde(deny_unknown_fields)]` for strict external input, `#[serde(default)]` for optional fields.
- `skip_serializing_if = "Option::is_none"` for sparse payloads; `flatten` sparingly (breaks `deny_unknown_fields` and can hide errors).
- Use `serde_with` for base64, hex, timestamps, and duration formats; `chrono`/`time` serializers must be explicit.
- Custom types: implement `Serialize`/`Deserialize` for newtypes to validate at parse time (`TryFrom` inside `Deserialize`).
- JSON: `serde_json` is the baseline. `simd-json`/`sonic-rs` accelerate hot paths with compatibility caveats (verify upstream); profile before switching.
- Enum representations: `#[serde(tag = "type", rename_all = "snake_case")]` internally tagged is common; untagged is last resort (poor errors, quadratic in variants).
- Do not use `serde_json::Value` for domain data; parse into typed structs at the boundary.
- Version payloads explicitly (`#[serde(rename = "...")]` legacy aliases) instead of relying on field-order.

## Database Access

| Criterion | sqlx | diesel (+ diesel-async) | sea-orm |
|---|---|---|---|
| Style | async, SQL-first, compile-time checked macros | typed query builder + async in `diesel-async` | async ORM over `sea-query` |
| Compile-time SQL check | yes (`query!` against live DB or offline `.sqlx` cache) | yes via schema types | no (runtime), but strong typing |
| Migrations | `sqlx migrate` | `diesel migration` | `sea-orm-cli migrate` |
| Best fit | existing SQL, precise queries, Postgres/MySQL/SQLite | teams wanting ORM-like safety with Rust types | entity modeling, CRUD-heavy apps |
| Async | native | requires `diesel-async` | native |

- Pooling: `sqlx::postgres::PgPoolOptions` — set `max_connections` from DB limits and concurrency budget, `acquire_timeout`, `max_lifetime`, `idle_timeout`. Never `max_connections` = number of tasks.
- Transactions: `let mut tx = pool.begin().await?; ...; tx.commit().await?;` — dropping rolls back. Hold transactions short; never across external HTTP calls.
- sqlx compile-time macros need `DATABASE_URL` at build time or `cargo sqlx prepare` (`SQLX_OFFLINE=true` in CI). Commit `.sqlx/` for reproducible builds.
- Use `query_as!`/`FromRow` for row mapping; add `#[sqlx(rename = "...")]` for column mismatches; prefer explicit SELECT columns over `SELECT *`.
- Migrations: forward-only, immutable once applied; additive changes (new nullable column, backfill, then constraint) to allow rolling deploys. Never edit an applied migration.
- N+1 detection: log query counts in dev; batch with `WHERE id = ANY($1)` or `INSERT ... ON CONFLICT`.
- SQLite for embedded/small services with WAL mode and a single writer or a connection-pool bound of 1 for writes; libsql/turso for remote SQLite if needed.
- SeaORM entities generated from schema drift; re-run generation in CI to catch drift.
- Connection health: set `test_before_acquire`/`before_acquire` hooks; handle transient failures with retries at the repository layer.

```rust
let rows = sqlx::query_as!(User,
    "SELECT id, email, created_at FROM users WHERE id = $1", id)
    .fetch_optional(&pool).await?;
```

## Configuration

- Precedence: defaults < config file < environment < CLI flags. Document it once and test each layer.
- `figment` (layered providers: TOML + env) or the simpler `config` crate; `envy` for env-to-struct only. `dotenvy` in dev only — never load `.env` in production.
- Parse config into a typed struct at startup with `serde`; fail fast with context (`anyhow` with file/key names). No `std::env::var` scattered through the codebase.
- Secrets: inject via environment or a secret manager (Vault, AWS Secrets Manager, SOPS); never commit them, never log them. Use `secrecy::SecretString`/`zeroize` for sensitive fields.
- Validate config ranges at startup (port, pool size > 0, URL schemes); reject unknown keys in config files.
- Feature flags/tenancy config that changes at runtime belongs in a `watch` channel or the DB, not `OnceLock` reads.

## Authentication and Authorization Patterns

- Password hashing: Argon2id (`argon2` crate) with sane parameters (memory >= 19 MiB, iterations >= 2, parallelism 1 as OWASP baseline; verify current recommendations upstream). Never SHA/MD5, never unsalted.
- Sessions: opaque random tokens stored server-side (hashed) with expiry and rotation; or signed cookies. Cookies: `HttpOnly`, `Secure`, `SameSite=Lax/Strict`, `__Host-` prefix.
- JWT (`jsonwebtoken`): short-lived access tokens (5-15 min), refresh tokens server-side revocable, validate `alg` explicitly (never `none`/unknown), `aud`, `iss`, `exp`, `nbf`. Public key set rotation via JWKS; cache keys.
- API keys: store a hash, show once, prefix for identification, per-key scopes and rate limits.
- Authorization: enforce in the service layer (`fn can(user, action, resource) -> bool`), not only in middleware; middleware handles authentication, handlers enforce per-resource access. Never trust client-supplied tenant/user ids.
- OAuth/OIDC: use `openidconnect` crate or a gateway; implement PKCE; validate `state` and nonce.
- Rate-limit auth endpoints and return uniform errors/timings to avoid user enumeration.
- mTLS/service auth inside the mesh or with signed service tokens; do not rely on network location.

## Graceful Shutdown

- Sequence: receive signal (SIGTERM/SIGINT) -> stop accepting -> drain in-flight requests with deadline -> close DB pools -> flush telemetry -> exit non-zero on timeout.
- axum: `axum::serve(listener, app).with_graceful_shutdown(shutdown_signal())`. `shutdown_signal` awaits `tokio::signal::ctrl_c()` and unix `SIGTERM`.
- Background tasks: `CancellationToken` + `TaskTracker`; cancel after HTTP drain or in parallel depending on semantics (e.g., stop consumers after in-flight writes complete).
- Readiness: flip to not-ready before drain so load balancers stop routing; keep liveness green until exit.
- Pools: `pool.close().await` after handlers stop.
- Timeouts: hard deadline (e.g., 30s) then abort; log remaining tasks. Kubernetes `terminationGracePeriodSeconds` must exceed the deadline.
- Deserialization/queue workers: finish the current message, then cancel; make handlers idempotent for redelivery.

```rust
let token = CancellationToken::new();
let mut app = app.with_state(state);
axum::serve(listener, app)
    .with_graceful_shutdown(shutdown_signal(token.clone()))
    .await?;
token.cancel();
tracker.close().await;
```

## Anti-Patterns

- Business logic in handlers; handlers should parse, call a service, map the result.
- Connection pool per request or unbounded pool size.
- Letting `serde_json::Value` leak into domain code.
- `SELECT *` plus struct field order assumptions.
- Middleware ordering that runs auth after body parsing or skips 404s unintentionally.
- JWT `alg` accepted from the token header; missing audience/issuer validation.
- Editing applied migrations; mixing schema DDL into request handlers.
- Blocking shutdown: dropping the future before drain; no deadline.
- Storing secrets in `config.toml` committed to the repo.

## Checklist

- [ ] Framework chosen deliberately; one HTTP stack in the service.
- [ ] State is `Clone + Send + Sync`; no per-request clients.
- [ ] tower layers ordered (trace -> timeout -> limits -> body) and tested.
- [ ] All external input parsed into typed structs with `deny_unknown_fields` where strictness helps.
- [ ] Pool sizes and acquire timeouts configured from DB limits; queries prepared/offline-checked.
- [ ] Migrations forward-only, applied in CI before deploy; rollback plan documented as a new migration.
- [ ] Authn at middleware, authz in services; tokens short-lived and revocable.
- [ ] Graceful shutdown drains with a deadline and closes pools; readiness flips first.
- [ ] Config validated at startup; secrets from environment/secret manager only.
