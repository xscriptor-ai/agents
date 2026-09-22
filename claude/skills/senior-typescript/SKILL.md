---
name: senior-typescript
description: 'TypeScript reference pack (TS 5.9 through 7.x era) covering the type
  system, modules and build strategy, React, major frameworks, runtimes, Node backends,
  testing, quality tooling, security, and the 2026 ecosystem state. Use when writing,
  reviewing, refactoring, debugging, or migrating non-trivial TypeScript: advanced
  types and declaration files, ESM/CJS interop and dual publishing, React server components
  and hooks, Next/Vue/Svelte/Angular choices, runtime selection across Node/Bun/Deno/edge,
  Fastify/Hono/NestJS services, Vitest/Playwright strategy, strict tsconfig and lint
  hardening, or supply-chain and web security. Depth lives in references/, one topic
  per file.'
---

# TypeScript

TypeScript is the default typed layer of the JavaScript ecosystem: browsers, Node.js, Bun, Deno, edge workers, build tooling, and now the compilers themselves (the native TS 7 line). A senior engineer moves fluently between type-level design, module topology, runtime behavior, and the toolchain that binds them.

This pack is an entrypoint plus ten deep references. Read the core rules first; they encode defaults that rarely deserve debate. Then load only the references the task needs. Each reference starts with a one-line scope and carries version floors, decision tables, runnable snippets, anti-patterns, and checklists.

Content targets the stable ecosystem of 2026: TypeScript 5.x with the native 7.x line arriving, Node.js 22/24 LTS, Bun 1.2+, Deno 2.x, React 19+, Vue 3.5+, Svelte 5, Angular 20-era signals, and the current toolchain (Vite/Rolldown, Vitest, Playwright, ESLint 9 flat config, Biome 2, pnpm). Versions move monthly: treat stated numbers as floors and verify upstream before quoting them in deliverables.

## Non-negotiable core rules

1. `"strict": true` is the floor, not the goal. Add `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, and the rest of the hardening set from [08-quality-tooling](./references/08-quality-tooling.md); annotate deliberate escape hatches with a reason.
2. Types are erased. Every I/O boundary (HTTP, env, storage, JSON.parse, postMessage) is parsed with a runtime validator before it becomes a typed value. See [06-backend-node](./references/06-backend-node.md).
3. `unknown` is the default for external data; `any` is a lint error. Non-null assertions are acceptable only immediately after a checked guard.
4. Bundlers and transpilers (esbuild, swc, oxc, Vite, Bun) do not type-check. CI runs `tsc --noEmit` (or the native TS 7 compiler) as a separate gate; see [08-quality-tooling](./references/08-quality-tooling.md).
5. New packages are ESM-first with a single explicit `exports` map. Dual publishing is a deliberate compatibility cost, not a default; see [02-modules-build](./references/02-modules-build.md).
6. `verbatimModuleSyntax` is on; type-only imports use `import type`; a package does not silently mix `require` and top-level `await` semantics.
7. Model states as discriminated unions and parse into them. Prefer literal unions and `as const` objects over `enum`; prefer `satisfies` over widening annotations. See [01-type-system](./references/01-type-system.md).
8. Errors are values or typed exceptions at boundaries, never `catch (e: any)`. Catch clauses take `unknown`; map to domain errors exactly once.
9. No secrets cross into client bundles. Anything exposed through a client-visible prefix (for example `NEXT_PUBLIC_`, `VITE_`) is public forever; see [09-security](./references/09-security.md).
10. React code obeys the rules of hooks and makes the server/client boundary explicit; fetching belongs to the framework or a query library, not to `useEffect`. See [03-react](./references/03-react.md).
11. Tests are deterministic: fixed clocks, seeded randomness, isolated state, no shared mutable fixtures. See [07-testing](./references/07-testing.md).
12. Lockfiles are committed; dependencies are audited in CI and updated on a schedule; published packages use provenance/OIDC trusted publishing. See [09-security](./references/09-security.md).
13. One TypeScript version per repository; toolchain versions are pinned. "Works on my machine" is a bug report, not a resolution.

## Load strategy

- Start with the index below and load at most two references per task; the rules above already cover most reviews.
- Combine one language reference ([01-type-system](./references/01-type-system.md) or [02-modules-build](./references/02-modules-build.md)) with one application reference (React, frameworks, backend, testing) when a task spans both.
- [10-ecosystem-2026](./references/10-ecosystem-2026.md) is the orientation and final-review pass; load it when versions, migrations, or a whole-repo audit are in scope.

## Decision tables

### Type modeling

| Need | Use | Avoid |
| --- | --- | --- |
| Closed set of states | Discriminated union + exhaustive switch | boolean flag pairs |
| Open set of string values | `string` with runtime validation | giant literal union |
| Named constants | `as const` object or literal union | `enum` |
| Object with defaults | Function returning a full object | exported mutable singleton |
| Opaque identifier | Branded type + constructor/parser | bare `string` everywhere |
| Complex inferred shape | `satisfies` against a type | annotation that widens |
| Deep generic machinery | Small, tested type tests | 200-line conditional types in app code |

### Module and build strategy

| Situation | `module` / `moduleResolution` | Notes |
| --- | --- | --- |
| App built by Vite/Rollup | `ESNext` / `bundler` | bundler owns resolution |
| Node app, native ESM | `nodenext` / `nodenext` | full ESM semantics |
| Node with `require(esm)` needs | `nodenext` | set `"type"` correctly |
| Library, dual publish | `node16`-compatible + tsdown/tsup | test both `import` and `require` |
| Legacy CJS-only consumer | last resort | isolate in one adapter package |

### Runtime selection

| Need | Default | Alternative |
| --- | --- | --- |
| General backend / LTS | Node.js 24 LTS | Node 22 LTS |
| Max dev speed, single binary | Bun 1.2+ | Node + swc |
| Permissions, built-in tooling | Deno 2 | Node |
| Global low-latency edge | Cloudflare Workers | Deno Deploy, Vercel Edge |
| Scripts and CLIs | Node or Bun | Deno with `--allow-*` |

### Framework selection

| Project type | Default | Alternative |
| --- | --- | --- |
| Full-stack React, content + app | Next.js App Router | TanStack Start, React Router 7 |
| Lightweight multi-runtime API | Hono | Fastify |
| Structured enterprise service | NestJS | Fastify + manual DI |
| Content-first, minimal JS | Astro | SvelteKit static |
| Vue product app | Nuxt 3.5+ / Vite | Vue SPA |
| Svelte product app | SvelteKit + runes | Svelte SPA |

### Testing stack

| Layer | Tool | Notes |
| --- | --- | --- |
| Unit / component | Vitest + Testing Library | jsdom or browser mode |
| Type-level | expect-type inside Vitest | `tsc --noEmit` in CI |
| E2E | Playwright | trace + sharding |
| HTTP mocking | MSW | never hand-rolled fetch stubs |
| Database | Testcontainers | real engine, disposable |
| Property-based | fast-check | seeded, shrinking |

## Reference index

| File | Scope | Load when |
| --- | --- | --- |
| [01-type-system.md](./references/01-type-system.md) | Advanced types: conditional/mapped/template-literal, variance, branding, `satisfies`, `const` params, `infer`, type testing, declarations | Designing public type APIs or debugging type errors and compiler performance |
| [02-modules-build.md](./references/02-modules-build.md) | ESM/CJS, `moduleResolution`, exports maps, `verbatimModuleSyntax`, tsc vs swc/esbuild/oxc, tsdown/tsup, dual publishing, npm/JSR | Packaging or consuming libraries, fixing resolution errors, publishing |
| [03-react.md](./references/03-react.md) | React 19+, Server Components, hooks, Zustand, TanStack Query, Server Actions, react-hook-form + zod, performance, Vitest + RTL | Writing or reviewing React application code |
| [04-frameworks.md](./references/04-frameworks.md) | Next.js App Router, Vue 3.5+, Svelte 5 runes, Angular signals, Solid, Astro; selection table | Choosing or working inside a meta-framework |
| [05-runtimes.md](./references/05-runtimes.md) | Node LTS, Bun, Deno 2, edge runtimes; TS support, compatibility, deployment | Target runtime decisions and portability bugs |
| [06-backend-node.md](./references/06-backend-node.md) | Fastify/Hono/NestJS, validation, Prisma/Drizzle/Kysely, auth, queues, WebSockets, config, shutdown, observability | Building or reviewing a TypeScript backend service |
| [07-testing.md](./references/07-testing.md) | Vitest, Playwright, mocking, type testing, fast-check, Testcontainers, coverage, CI sharding, flake control | Designing or repairing a test suite |
| [08-quality-tooling.md](./references/08-quality-tooling.md) | tsconfig hardening per flag, ESLint 9 flat config, Biome/oxlint, Prettier, CI checks, bundle analysis, monorepos | Setting up or tightening project quality gates |
| [09-security.md](./references/09-security.md) | npm supply chain, XSS/Trusted Types, CSP, secrets, SSRF, Node hardening, dependency policy | Reviewing security posture or handling an incident |
| [10-ecosystem-2026.md](./references/10-ecosystem-2026.md) | Ecosystem state, migrations (CJS to ESM, signals, React 19), pitfalls, senior review checklist | Orienting on current versions, planning a migration, final review pass |

## Port

- **Port id** — `skill://senior/typescript` (version in `metadata.port-version`).
- **Kind** — read-only reference pack; no side effects, no tools required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "typescript" })` in OpenCode; Claude Code reads `<skills-dir>/typescript/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers reference it as `load skill senior-typescript (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major.
