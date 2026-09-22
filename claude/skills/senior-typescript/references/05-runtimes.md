# Runtimes

> Scope: Node.js LTS lines, Bun 1.x, Deno 2.x, and edge runtimes — TypeScript support, API compatibility, and deployment constraints.

Version floors (verify upstream; treat as minimums):

| Runtime | Current in 2026 | TypeScript story |
| --- | --- | --- |
| Node.js 22 | maintenance LTS | type stripping on recent minors |
| Node.js 24 | active LTS | type stripping on by default |
| Node.js 26 | current release line | verify upstream |
| Bun | 1.2+ | native `.ts`/`.tsx`, no config |
| Deno | 2.x | native TS, JSR-first |
| Cloudflare Workers | workerd (continuous) | types via `wrangler types`; bundled TS |
| Vercel Edge / Netlify Edge | Web-API runtimes | bundled TS, subset of Node |
| Deno Deploy | Deno runtime | native TS |

Rule of thumb: pick the oldest supported LTS that satisfies constraints. Runtime novelty is a liability unless it buys something specific (startup time, permissions, edge latency).

## 1. Node.js LTS

Node 24 is the active LTS line through 2026; Node 22 stays in maintenance. New work should target Node 24 with an `engines` floor that matches the oldest deployment target your CI tests (typically `>=22`).

Capabilities that changed what TypeScript services look like:

| Capability | Availability | Notes |
| --- | --- | --- |
| `fetch`, `Request`/`Response`, `FormData`, `Blob` | stable | undici-based; `AbortSignal` everywhere |
| `node:test` runner | stable | `node --test`, snapshots, coverage flags |
| `node --watch` | stable | supersedes nodemon for simple cases |
| Type stripping of `.ts` | Node 22.18+/24+ on by default | erasable syntax only |
| `--experimental-transform-types` | current lines | enables enums/namespaces at runtime |
| `require(esm)` | Node 22.12+/23+ unflagged | unblocks some CJS consumers |
| WebSocket client | stable | no `ws` needed for clients |
| `node:sqlite` | experimental in 22, stabilizing | built-in SQLite; verify per minor |
| Permission model (`--permission`) | available, verify stability | read/write/net allowlists |
| `node --run` | stable | runs package.json scripts |
| Single Executable Applications (SEA) | available | for CLIs; verify tooling |

Type stripping constraints: only erasable syntax runs directly. `enum`, `namespace` with runtime values, parameter properties, and `import x = require()` fail unless transform mode is enabled. Enable `erasableSyntaxOnly` in tsconfig for code meant to run this way.

```jsonc
// package.json — run TS directly on Node 24
{
  "type": "module",
  "engines": { "node": ">=24" },
  "scripts": {
    "dev": "node --watch src/server.ts",
    "start": "node src/server.ts",
    "typecheck": "tsc --noEmit"
  }
}
```

Deployment notes:

- Docker: multi-stage build, `node:24-slim` or distroless, non-root `USER`, `dumb-init`/`tini` or signal-forwarding entrypoint, `--max-old-space-size` tuned to the container limit, `HEALTHCHECK` on a `/healthz` route.
- Node as PID 1 does not forward signals to children unless configured; handle `SIGTERM` in-process (see [06-backend-node](./06-backend-node.md)).
- Do not rely on `NODE_ENV` semantics beyond what libraries document; set it at build and run time explicitly.

## 2. Bun

Bun 1.2+ is a drop-in-oriented runtime, package manager, bundler, and test runner in one binary with native TypeScript/JSX execution.

What it is good at:

- Fast installs (`bun install`), lockfile (`bun.lock`), and script running with far less startup latency than Node.
- Built-in `bun test` (Jest-compatible APIs), `bun build` bundling, and `bun --watch`.
- Built-in database clients (SQLite, Postgres) and Redis; S3 client.
- Native Node compatibility layer for most popular packages, including `node:` builtins.
- N-API support for native addons; verify per-addon.

Where to be careful:

- Node compatibility has sharp edges in exotic APIs (worker internals, some crypto, some streams); run your test suite under Bun before committing to it in production.
- Edge/serverless platforms do not run Bun as a managed runtime; use Bun mainly for servers you control, dev speed, and CLIs.
- Tooling ecosystem assumptions (some frameworks' adapters) may still target Node; verify.

```ts
// Bun server, native TS
const server = Bun.serve({
  port: 3000,
  fetch(req) {
    const url = new URL(req.url);
    if (url.pathname === "/healthz") return new Response("ok");
    return Response.json({ runtime: `bun ${Bun.version}` });
  },
});
console.log(`listening on ${server.port}`);
```

## 3. Deno 2

Deno 2 keeps secure-by-default permissions and first-class TypeScript while adopting npm compatibility.

- Package management: `deno add npm:fastify` / `jsr:@std/http`; `deno.json` holds imports, compiler options, tasks, lint/format config; lockfile `deno.lock`.
- Node compatibility: `node:` specifiers and `npm:` packages; most Node libraries work; frameworks like Hono and Fastify run with caveats.
- JSR: native registry for TypeScript packages (see [02-modules-build](./02-modules-build.md)).
- Tooling built in: `deno test` (with sanitizers), `deno lint`, `deno fmt`, `deno check`, `deno compile` for single binaries, `deno bench`.
- Platform primitives: Deno KV, Queues, Cron, OpenTelemetry hooks, FFI.
- Permissions are granular: `--allow-net=api.example.com`, `--allow-read=./data`, `--allow-env=NODE_ENV`.

```jsonc
// deno.json
{
  "imports": { "@/": "./src/", "@std/": "jsr:@std/" },
  "compilerOptions": { "strict": true, "noUncheckedIndexedAccess": true },
  "tasks": { "dev": "deno run --watch --allow-net src/server.ts" },
  "exclude": ["dist"]
}
```

Deployment notes: Deno Deploy runs the same runtime at edge locations; locally you can compile to a binary or ship a Docker image based on the Deno runtime. Permissions should be enumerated in the start command, not dropped with `-A`.

## 4. Edge runtimes

Edge runtimes are V8 isolates with Web APIs and constrained I/O. They are not Node.

| Constraint | Cloudflare Workers | Deno Deploy | Vercel Edge |
| --- | --- | --- | --- |
| Filesystem | no | no | no |
| `child_process` | no | no | no |
| Node compat | `nodejs_compat` flag | strong (Deno) | partial |
| TCP sockets | via `connect()` | yes (per APIs) | restricted |
| Persistent DB | D1, KV, R2, Durable Objects, Hyperdrive | Deno KV, Postgres | vendor stores |
| CPU limits | plan-dependent, seconds | plan-dependent | plan-dependent |
| Memory | ~128 MB per isolate | plan-dependent | plan-dependent |
| Streaming | Web Streams | Web Streams | Web Streams |

Practices:

- Write handlers against Web APIs (`Request`, `Response`, `fetch`, `crypto.subtle`) and keep vendor bindings at the edge of the code (adapter modules).
- Bundle with the platform's toolchain (Wrangler, Vercel) so the `workerd`/edge export conditions resolve; Node-targeted bundles will import fs or net and fail at deploy.
- No long-lived in-memory state: isolates are evicted; use KV/Durable Objects for state and queues for background work.
- Cold starts reward small bundles: avoid mega-dependencies and top-level side effects.
- Local development: emulate with `wrangler dev` (workerd) rather than trusting browser mocks; the emulator is the same engine.

Cloudflare specifics worth knowing: Durable Objects for coordination and per-key consistency, Hyperdrive for pooled Postgres, service bindings for worker-to-worker RPC, and Smart Placement for latency-sensitive fan-out. Verify current limits upstream; they change per plan.

## 5. Compatibility matrix

| API | Node 24 | Bun 1.2+ | Deno 2 | Edge |
| --- | --- | --- | --- | --- |
| `fetch`, Web Streams | yes | yes | yes | yes |
| `node:fs` | yes | yes | yes | no |
| `node:http` | yes | yes | most | partial via compat |
| `node:crypto` | yes | yes | most | WebCrypto only |
| Workers/threads | yes | yes | Web Workers | limited |
| `AsyncLocalStorage` | yes | yes | yes | via compat |
| `process.env` | yes | yes | via `Deno.env` / compat | bindings |
| Top-level await | ESM | yes | yes | yes |
| Native addons | yes | N-API | N-API, FFI | no |
| `require(esm)` | yes | yes | compat | n/a |

Portability rule: if a module must run in more than one runtime, isolate differences behind an interface, test on every target, and prefer Web APIs over `node:*` everywhere except unavoidable server internals.

## 6. TypeScript support per runtime

| Runtime | How TS executes | Caveats |
| --- | --- | --- |
| Node 24 | strip types, no transform | erasable syntax only; no path aliases |
| Bun | transpile-on-load | uses its own transpiler; tsconfig mostly respected |
| Deno | native | honors `deno.json` compilerOptions; JSR types |
| Workers/Vercel Edge | pre-bundled by platform | types come from `wrangler types`/generated env types |
| tsx / ts-node | loader-based | dev only; never production default |

Regardless of runtime, the type-check gate is `tsc --noEmit` (or native compiler) in CI. Runtime execution never substitutes for checking.

## 7. Anti-patterns

| Anti-pattern | Consequence | Fix |
| --- | --- | --- |
| Targeting latest current Node, deploying to older LTS | runtime syntax errors | `engines` + CI floor matrix |
| Relying on `node:` built-ins in edge code | deploy-time failures | Web APIs + adapters |
| `bun install` producing a lockfile other runtimes use | drift | one package manager per repo, lockfile committed |
| `-A` / `--allow-all` in Deno prod | no security boundary | enumerate permissions |
| Long tasks in edge isolates | CPU limit kills request | offload to queues/durable storage |
| `ts-node` in production | slow, fragile | precompile or native stripping |
| In-memory sessions on ephemeral runtimes | random logouts | external session store |

## Checklist

- [ ] Runtime chosen per workload: Node for compatibility, Bun for throughput/dev, Deno for permissions/JSR, edge for latency.
- [ ] `engines` matches the floor tested in CI.
- [ ] TS runs natively only for erasable syntax; `erasableSyntaxOnly` set where relevant.
- [ ] Edge code uses Web APIs only; vendor bindings isolated.
- [ ] Container: non-root, signal-aware, memory limit aligned with heap flags.
- [ ] Permissions explicit (Deno) or binding allowlists explicit (Workers).
- [ ] Lockfile committed for the chosen package manager.

Related: [02-modules-build](./02-modules-build.md) for resolution and bundles, [06-backend-node](./06-backend-node.md) for service patterns, [10-ecosystem-2026](./10-ecosystem-2026.md) for the current runtime landscape.
