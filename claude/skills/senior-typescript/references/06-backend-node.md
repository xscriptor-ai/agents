# Backend on Node and Friends

> Scope: TypeScript service architecture — framework choice, validation, database layers, auth, queues, realtime, configuration, graceful shutdown, and observability.

Version floors (verify upstream; treat as minimums):

| Layer | Current line | Notes |
| --- | --- | --- |
| Fastify | 5+ | schema-first, plugin encapsulation |
| Hono | 4+ | multi-runtime, typed RPC |
| NestJS | 10/11+ | DI, decorators, enterprise structure |
| zod | 4+ | Standard Schema, faster parsing |
| valibot | 1+ | small bundle, tree-shakable schemas |
| Prisma | 6/7 | typed client, migrations; verify driver/engine changes |
| Drizzle | 0.4x/1.x line | SQL-first, typed, verify release channel |
| Kysely | 0.28+ | query builder only, no runtime magic |
| pino | 9/10+ | structured JSON logging |
| OpenTelemetry JS | 2.x | traces/metrics/logs |

## 1. Framework choice

| Situation | Choose | Why |
| --- | --- | --- |
| HTTP API, single runtime, performance matters | Fastify | schema validation built in, mature plugins |
| API on multiple runtimes (Node/Bun/Deno/edge) | Hono | Web-API core, tiny, typed client |
| Large team, heavy DI, multiple transports | NestJS | modules/providers/guards, opinionated structure |
| Legacy Express codebase | migrate incrementally | Express 5 improved but ecosystem momentum is elsewhere |
| Internal RPC between TS services | tRPC or Hono RPC | end-to-end types without codegen |
| GraphQL | GraphQL Yoga / Apollo | pick based on federation needs |

Do not choose a framework for benchmarks alone. Operational maturity (logging, validation, testing, plugin ecosystem) dominates.

## 2. Fastify patterns

```ts
import Fastify from "fastify";
import { z } from "zod";

const app = Fastify({ logger: true, requestIdHeader: "x-request-id" });

const CreateUser = z.object({ email: z.string().email(), name: z.string().min(1) });

app.post("/users", async (req, reply) => {
  const input = CreateUser.parse(req.body);       // validate at the edge
  const user = await userService.create(input);   // domain logic elsewhere
  return reply.code(201).send(user);
});

app.get("/healthz", async () => ({ status: "ok" }));
app.get("/readyz", async () => ({ status: (await db.ping()) ? "ok" : "degraded" }));

await app.listen({ port: Number(process.env.PORT ?? 3000), host: "0.0.0.0" });
```

Rules:

- One plugin per concern; use `fastify-plugin` only when you intend to break encapsulation.
- Register JSON schemas or zod serializers/parsers so responses are validated too, not just requests.
- Use lifecycle hooks (`onRequest` for auth/rate limit, `preHandler` for authorization) instead of decorating handlers.
- Return errors as RFC 7807-ish shapes consistently; set `setErrorHandler` once.
- Fastify's schema compilation is a real performance feature; for hot routes prefer TypeBox/JSON Schema over ad-hoc validation.

## 3. Hono patterns

```ts
import { Hono } from "hono";
import { zValidator } from "@hono/zod-validator";
import { z } from "zod";

const CreateTodo = z.object({ title: z.string().min(1) });
const app = new Hono<{ Bindings: { DB: D1Database } }>();

app.post("/todos", zValidator("json", CreateTodo), async (c) => {
  const { title } = c.req.valid("json");
  return c.json({ id: crypto.randomUUID(), title }, 201);
});

export default app;
```

- The app object is portable: run on Node via `@hono/node-server`, on Bun, Deno, Workers.
- `hono/client` gives an end-to-end typed client when the API is consumed from TypeScript.
- Middleware is composable (`app.use(cors(), secureHeaders(), logger())`); keep platform bindings behind typed `Bindings`/`Variables` generics.

## 4. NestJS notes

Use when the org benefits from enforced structure: modules, DI with `@Injectable`, providers, guards, interceptors, pipes.

- Pipes do validation (`ValidationPipe` + class-validator or a zod pipe); keep DTOs at the transport layer and map to domain objects.
- Prefer constructor injection with explicit types; avoid request-scoped providers unless needed (they cascade cost).
- Use interceptors for cross-cutting concerns (logging, tracing), guards for auth, exception filters for error mapping.
- Test with `Test.createTestingModule` and `supertest`; override providers rather than hitting real infrastructure.

## 5. Validation

Validation belongs at every boundary: HTTP bodies/params, env, queue messages, DB rows read raw, webhooks.

| Library | Strength | Tradeoff |
| --- | --- | --- |
| zod 4 | ecosystem, Standard Schema, great DX | bundle size in tight client budgets |
| valibot | small, tree-shakable | smaller ecosystem |
| TypeBox | JSON Schema-native, fastest for Fastify | verbose, JSON Schema ergonomics |
| arktype | type-first syntax | smaller ecosystem |
| Standard Schema | shared interface (`~standard`) | interoperability layer, not a validator |

```ts
import { z } from "zod";

export const Env = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().url(),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace"]).default("info"),
});
export type Env = z.infer<typeof Env>;
```

Parse env once at startup and crash on failure. Never read `process.env.X` ad hoc deep in the codebase; pass a typed config object.

## 6. Database layer

| Need | Prisma | Drizzle | Kysely |
| --- | --- | --- | --- |
| Schema-as-code + migrations | strong | strong (drizzle-kit) | manual SQL migrations |
| Typed SQL-first queries | limited | good | excellent |
| Runtime weight | client engine | thin | thin |
| Complex SQL escape hatch | `$queryRaw` | `.sql` escape | native |
| Edge/serverless | driver adapters | yes | yes |

Rules that apply to all three:

- Transactions wrap invariants, not whole request handlers. Keep them short.
- Solve N+1 by construction: batch with `include`/relational queries or explicit `IN` queries; log query counts in tests.
- Migrations are forward-only in production; destructive changes go in expand/migrate/contract steps.
- Pool per process; serverless needs an external pooler (session vs transaction mode matters — verify the provider's guidance).
- Set statement and lock timeouts in the connection config; a stuck query should fail, not hold the request forever.
- Return domain objects from a mapping layer; do not leak ORM types across module boundaries.

## 7. Auth

| Need | Approach |
| --- | --- |
| Browser app, first-party | httpOnly, Secure, SameSite=Lax session cookie + server-side session store |
| API for third parties | short-lived access token + rotating refresh token, or API keys with scopes |
| Federated login | Auth.js / better-auth / OIDC provider; do not hand-roll |
| Service-to-service | mTLS or signed tokens; never shared static secrets in env |

Non-negotiables:

- Password hashing: argon2id (preferred) or bcrypt with cost tuned to hardware; never SHA-family for passwords.
- Compare secrets with timing-safe comparison.
- Sessions: store server-side (DB/Redis), rotate on privilege change, expire idle and absolute.
- CSRF: SameSite cookies plus origin checks; token-based API clients exempt.
- Authorization happens server-side per resource — checks in the client are UX only.
- Never put secrets, tokens, or PII in JWT payloads (they are readable).

## 8. Queues and background work

| Tool | Fit |
| --- | --- |
| BullMQ | Redis-based jobs, retries, rate limits, schedulers |
| pg-boss | Postgres-only stacks, transactional enqueue |
| Cloud queues (SQS, Cloudflare Queues) | managed, at-least-once semantics |
| In-process `setTimeout`/worker threads | never for durable work |

Patterns: idempotency keys for every consumer; the transactional outbox when the job must reflect a DB commit; dead-letter queues with alerting; visibility timeout larger than worst-case handler time; and a separate worker process from the HTTP server.

## 9. Realtime

| Need | Use |
| --- | --- |
| Server push, one-way | SSE (simplest, HTTP-native, auto-reconnect) |
| Bidirectional, moderate scale | `ws` or framework WebSocket plugins |
| Rooms, fallbacks, presence | Socket.IO |
| Edge, per-room state | Durable Objects / KV-backed pub-sub |

Scale-out requires a shared bus (Redis pub/sub, NATS) or sticky routing; an in-memory room map breaks the moment you run two instances. Authenticate the upgrade request and apply per-connection rate limits.

## 10. Config

- One typed config module, parsed at startup, immutable in the process.
- Layers: defaults in code, overrides from env, secrets from a manager (Vault, AWS Secrets Manager, Doppler). Never commit `.env` files; commit `.env.example` that stays in sync.
- Feature flags are config, not code paths scattered through modules; load once, evaluate consistently.
- Distinguish build-time and runtime config: client-exposed prefixes are public (see [09-security](./09-security.md)).

## 11. Graceful shutdown

```ts
const shutdown = async (signal: string) => {
  app.log.info({ signal }, "shutting down");
  const timer = setTimeout(() => process.exit(1), 15_000); // hard deadline
  try {
    await app.close();        // stop accepting, finish in-flight
    await db.destroy();       // close pools
    await queue.close();      // stop workers
    clearTimeout(timer);
    process.exit(0);
  } catch (err) {
    app.log.error({ err }, "shutdown failed");
    process.exit(1);
  }
};
process.on("SIGTERM", () => void shutdown("SIGTERM"));
process.on("SIGINT", () => void shutdown("SIGINT"));
```

Rules: readiness must flip to failing before draining starts (Kubernetes `preStop` or a ready flag); the deadline must be shorter than the orchestrator's kill timeout; never call `process.exit()` mid-request; workers stop pulling new jobs before closing.

## 12. Observability

- Structured logs with pino: one JSON line per event, request id propagated via `AsyncLocalStorage`, no `console.log` in production code.
- OpenTelemetry for traces/metrics; instrument HTTP, DB, and queue clients; export via OTLP to the platform collector.
- Correlation: accept/generate `traceparent` and `x-request-id`; return the request id to clients for support.
- RED metrics per route (rate, errors, duration) and saturation for pools; alert on symptoms (error budget burn), not causes.
- Health endpoints: `/healthz` liveness (process alive), `/readyz` readiness (dependencies checked), both cheap and unauthenticated.
- Error reporting to Sentry or equivalent with release and user context, scrubbed of PII and secrets.

## Anti-patterns

| Anti-pattern | Consequence | Fix |
| --- | --- | --- |
| Validation only on the client | malformed data reaches the DB | parse at every boundary |
| ORM entities across boundaries | coupling, accidental lazy loads | map to domain types |
| Per-request DB connection | pool exhaustion | shared pool per process |
| Long transactions | lock contention | short transactions around invariants |
| `console.log` | unstructured, unbounded | pino with levels |
| In-memory job state | lost on redeploy | durable queue |
| Auth middleware checking only authentication | horizontal privilege escalation | per-resource authorization |
| No `SIGTERM` handling | dropped requests on deploy | graceful shutdown |

## Checklist

- [ ] Framework chosen per decision table; plugin/middleware organization explicit.
- [ ] All inputs parsed (HTTP, env, queue, webhook) with one validator family.
- [ ] DB access wrapped; transactions short; N+1 guarded by tests.
- [ ] Sessions/tokens stored and rotated per policy; argon2id hashing; per-resource authorization.
- [ ] Background work durable, idempotent, and dead-lettered.
- [ ] Typed config parsed at boot; secrets from a manager; `.env` ignored.
- [ ] SIGTERM drains HTTP, DB, and workers within a deadline.
- [ ] Logs, traces, metrics, request ids, health endpoints in place.
- [ ] Realtime scale-out uses a shared bus.

Related: [05-runtimes](./05-runtimes.md) for runtime constraints, [07-testing](./07-testing.md) for service tests, [09-security](./09-security.md) for the security layer around all of this.
