# Ecosystem 2026

> Scope: state of the TypeScript ecosystem in 2026, migration notes, recurring pitfalls, and the senior review checklist.

Everything here is a snapshot with a shelf life. Treat versions as floors, prefer stable APIs, and verify upstream before making a version claim in a deliverable.

## 1. TypeScript compiler line

| Track | Status | What it means |
| --- | --- | --- |
| TypeScript 5.x | stable line | all current language features; regular minors |
| TypeScript 6.x | bridge release | deprecations aligned for the native compiler; verify exact changes |
| TypeScript 7 (native, Go) | preview/early adoption | same type semantics, much faster; tooling API differences |
| `tsgo` binary | preview | drop-in type-check gate; watch editor/plugin support |

Practical stance for 2026: pin the newest stable 5.x/6.x for production, evaluate `tsgo` as a faster CI type gate, and do not adopt the native line in production until editors, lint tooling, and declaration emit are verified. Watch the deprecation list: legacy `moduleResolution: node`, older `target` values, and implicit-any-era defaults are being phased out. `erasableSyntaxOnly` and `isolatedDeclarations` are the flags that future-proof code for both the native compiler and runtime type stripping.

Ecosystem-wide TypeScript features that are now expected in senior code: `satisfies`, `const` type parameters, `NoInfer`, inferred type predicates, `using` for disposal, and `import type` under `verbatimModuleSyntax`. See [01-type-system](./01-type-system.md).

## 2. Runtimes

- Node.js 24 is the active LTS through 2026; Node 22 maintenance; Node 26 current. Type stripping is default on current LTS lines for erasable syntax; `node:test`, watch mode, fetch, and WebSocket are stable. Permission model and `node:sqlite` are the areas to verify per minor.
- Bun 1.2+ is production-viable for services you control: fast installs, native TS, built-in test/bundler, Postgres/SQLite/Redis clients. Verify Node-compat edges for heavyweight libraries.
- Deno 2 is npm-compatible and JSR-first, with granular permissions, built-in tooling, KV/Queues, and `deno compile`.
- Edge runtimes (Cloudflare Workers, Deno Deploy, Vercel Edge) are the default for latency-sensitive read paths; treat them as Web-API-only and keep state in KV/Durable Objects/queues.

Details and matrices: [05-runtimes](./05-runtimes.md).

## 3. Frameworks and UI

| Framework | Line in 2026 | Center of gravity |
| --- | --- | --- |
| React | 19.x | Server Components, actions, compiler |
| Next.js | 15/16+ | App Router, explicit caching, PPR |
| Vue | 3.5+/3.6 | script setup, vapor mode in preview |
| Svelte | 5+ | runes, snippets |
| Angular | 20+ | standalone, signals, zoneless |
| Solid | 1.9+ | fine-grained reactivity |
| Astro | 5+ | islands, content layer |

The convergent trend: fine-grained reactivity (signals) and server-first rendering with explicit client islands. The framework-specific idioms are in [04-frameworks](./04-frameworks.md), React depth in [03-react](./03-react.md).

## 4. Tooling landscape

| Category | Current | Notes |
| --- | --- | --- |
| Dev server / bundler | Vite 6/7, Rolldown-based Vite | Rust bundling for production builds |
| App bundlers | Rollup, esbuild, webpack (legacy), Parcel (niche) | pick by plugin needs |
| Library builds | tsdown, tsup, unbuild, tsc | see [02-modules-build](./02-modules-build.md) |
| Test runner | Vitest 3/4 | Jest compatibility layer for migration |
| E2E | Playwright | traces, sharding, component testing |
| Lint | ESLint 9 flat, Biome 2, oxlint | typed ESLint + fast Rust complement |
| Format | Prettier 3, Biome | one per repo |
| Package manager | pnpm 9/10, npm, Bun | strict installs recommended |
| Task graph | Turborepo 2, Nx | affected-only CI |
| Schemas | zod 4, valibot, TypeBox, arktype | Standard Schema interop |

Rules that survive tool churn: one formatter, one type-check gate, one package manager, one TS version, frozen lockfiles, and CI gates ordered cheapest-first. See [08-quality-tooling](./08-quality-tooling.md).

## 5. Data and services

- Validation is standardized around Standard Schema: zod/valibot/arktype implement it, frameworks accept it. Choose one per repo.
- ORMs split into schema-first (Prisma) and SQL-first (Drizzle, Kysely); the decision is about query complexity and deployment target, not popularity. See [06-backend-node](./06-backend-node.md).
- Serverless Postgres poolers (transaction mode) change ORM configuration; verify the provider's guidance before deploying.
- OpenTelemetry JS 2.x is the observability baseline; structured logging with pino is the default.
- Realtime: SSE for one-way, WebSockets/Socket.IO for two-way, Durable Objects for edge rooms.

## 6. Migrations

### CJS to ESM

1. Set `"type": "module"`; rename true CJS files to `.cjs`.
2. Convert `require`/`module.exports`; replace `__dirname`/`__filename`.
3. Add explicit extensions with `nodenext`; or use `bundler` and let the bundler resolve.
4. Convert JSON requires to import attributes or `fs` reads.
5. Fix CJS-only dependencies via adapters, dynamic `import()`, or replacement.
6. Run `attw`/`publint` on the built package; smoke-test both entry points.
7. Major-version the release if the layout changes.

### Jest to Vitest

Mechanical for 90% of suites: replace the runner, map `jest.*` to `vi.*`, convert config to `vitest.config.ts`, move setup files, and handle ESM-only deps (which Vitest supports natively). Keep the same assertions; migrate snapshot files with the codemod path. Watch fake timers and module mocking semantics.

### Angular to signals

Standalone components first; then replace `BehaviorSubject` state with `signal`/`computed`, template reads with signal calls, RxJS kept at async boundaries (`resource`, `toSignal`). Remove zone.js once all async sources are signal-compatible; verify per-version support.

### React 18 to 19

Remove `forwardRef` wrappers; PropTypes are gone; adopt actions and `useActionState` for forms; review `use` and Suspense boundaries; check third-party libs for React 19 peer ranges. Enable the compiler only after the rules-of-hooks lint is clean.

### Next.js pages to App Router

Convert route by route; pages become server components; move data fetching into the component/loader; port `getServerSideProps` to async components; port API routes to route handlers or server actions; re-audit caching behavior since defaults changed across majors. See [03-react](./03-react.md).

### ESLint to flat config

Use the official migration tooling, replace `extends`/`overrides` with array composition, move ignores into config objects, and delete `.eslintignore`/`.eslintrc*`. Keep typed linting enabled for correctness rules.

## 7. Common pitfalls in 2026

| Pitfall | Why it bites | Guard |
| --- | --- | --- |
| Trusting bundler output as type-checked | esbuild/swc don't check | `tsc --noEmit` gate |
| Implicit framework caching | stale or missing data in prod | explicit cache directives/tags |
| Mixing module systems in one package | resolution errors for half the users | exports map + attw |
| Client bundles importing server modules | secret leakage, huge bundles | `server-only`, boundary lint |
| Runtime execution of non-erasable TS | enums fail under type stripping | `erasableSyntaxOnly` |
| Lockfiles ignored | supply chain drift | frozen installs |
| "Just add `any`" during migration | type debt compounds | `unknown` + parse |
| Adopting preview compilers in prod | tooling gaps | pin stable, test preview in CI |
| Time/randomness in tests | flakes | fake timers, seeded RNG |
| Missing graceful shutdown | dropped requests on deploy | SIGTERM handler + deadline |

## 8. Senior review checklist

Architecture and types:

- [ ] Domain logic framework-agnostic; boundaries (HTTP/DB/queue) thinnest possible.
- [ ] External data parsed at boundaries; no `any`, no unchecked assertions on I/O.
- [ ] Public APIs typed with documented generics; type tests present.
- [ ] Error model explicit: typed errors or Result at boundaries; no swallowed catches.

Modules and build:

- [ ] `module`/`moduleResolution` match consumers; `exports` map correct; `verbatimModuleSyntax` on.
- [ ] One package manager and lockfile; frozen installs in CI.
- [ ] Libraries pass `publint`/`attw`; dual-package smoke tests where applicable.

Runtime and operations:

- [ ] Target runtime's constraints respected (edge/Node/Bun/Deno); `engines` matches CI floor.
- [ ] Config parsed once at boot; secrets from a manager; no client-visible secrets.
- [ ] SIGTERM drains HTTP, DB, queues within a deadline shorter than the orchestrator kill.
- [ ] Logs structured with request ids; traces/metrics exported; health/readiness endpoints live.

Quality:

- [ ] `strict` + hardening flags; typed lint; zero warnings; formatting enforced.
- [ ] CI gates ordered: format, lint, types, tests, build, e2e, package checks.
- [ ] Bundle budgets enforced; no dependency added without size/maintenance review.

Security:

- [ ] Supply-chain controls (lockfile, cooldown, provenance, script allowlist).
- [ ] XSS surfaces sanitized; CSP enforced; Trusted Types where supported.
- [ ] SSRF allowlists, authz per resource, rate limits, cookie flags correct.

Testing:

- [ ] Test pyramid mapped; e2e limited to journeys; type tests in CI.
- [ ] Deterministic tests; flake quarantine with owner and expiry.
- [ ] Integration tests use real engines (Testcontainers) where semantics matter.

Versions and release:

- [ ] Version claims verified upstream; migration notes documented; changelog maintained.
- [ ] One TypeScript version per repo; preview tooling isolated from release paths.

## 9. Where to verify

- TypeScript release notes: `typescriptlang.org/docs/handbook/release-notes`.
- Node.js releases and LTS schedule: `nodejs.org/en/about/previous-releases`.
- Framework docs for the exact major you run: Next.js, Vue, Svelte, Angular, Solid, Astro.
- Package registries and provenance: `npmjs.com`, `jsr.io`.
- Web platform baselines: MDN and the W3C/WHATWG specs for browser APIs.
- Security advisories: GitHub Advisory Database, OSV.

Related: [01-type-system](./01-type-system.md), [02-modules-build](./02-modules-build.md), [03-react](./03-react.md), [05-runtimes](./05-runtimes.md), [06-backend-node](./06-backend-node.md), [07-testing](./07-testing.md), [08-quality-tooling](./08-quality-tooling.md), [09-security](./09-security.md).
