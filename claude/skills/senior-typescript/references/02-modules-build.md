# Modules, Build, and Publishing

> Scope: ESM/CJS interop, `module`/`moduleResolution` choices, exports maps, `verbatimModuleSyntax`, aliases, transpilers versus type-checkers, library bundlers, dual publishing, and npm/JSR release practice.

Version floors (verify upstream; treat as minimums):

| Feature | Availability | Notes |
| --- | --- | --- |
| `moduleResolution: bundler` | TS 5.0+ | for bundler-owned graphs |
| `module: preserve` | TS 5.4+ | keeps `import`/`require` as written |
| `require(esm)` | Node 22.12+ / 23+ | unflagged; exact per-minor behavior varies |
| `module-sync` export condition | Node 22.10+ | sync `require` of ESM graph |
| TypeScript type stripping | Node 22.18+ / 24+ | run `.ts` directly for erasable syntax only |
| `--erasableSyntaxOnly` | TS 5.8+ | enforces type-strippable source |
| Trusted publishing (OIDC) | npm registry, current line | no long-lived tokens |
| JSR | stable | npm compat via `npm:` specifiers |

## 1. Pick `module` and `moduleResolution` together

These options are a pair; mismatches produce runtime `ERR_MODULE_NOT_FOUND` or phantom type resolution. The compiler cannot catch resolution that a bundler or runtime does differently.

| Target | `module` | `moduleResolution` | Consumer |
| --- | --- | --- | --- |
| Bundled browser app | `ESNext` or `preserve` | `bundler` | Vite, Rollup, webpack, esbuild |
| Node app, native ESM | `nodenext` | `nodenext` | Node `"type": "module"` |
| Node app, CJS legacy | `node16`/`nodenext` | same | Node without `"type"` |
| Library, broad compat | `node16` (emitting) | `node16` | both `import` and `require` |
| Deno | `ESNext` | `bundler` or Deno defaults | Deno 2 |
| Bun | `ESNext` | `bundler` | Bun |

Rules:

- `moduleResolution: node` (node10) is legacy; do not start new work there.
- `bundler` implies `resolvePackageJsonExports` and friends; it forbids `.js` extension-rewriting assumptions a bundler makes moot.
- With `nodenext`, relative imports need explicit extensions (`.js`, `.mjs`, `.cjs`) in the emitted graph.
- `allowImportingTsExtensions` only works with `noEmit` or `rewriteRelativeImportExtensions` (TS 5.7+); otherwise the emitted graph is wrong.

## 2. Exports map anatomy

Modern resolution reads package.json, not the directory tree. `main`/`types` remain only as fallbacks for old resolvers.

```jsonc
{
  "name": "acme-lib",
  "type": "module",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",      // must come first in each block
      "import": "./dist/index.js",
      "require": "./dist/index.cjs",
      "default": "./dist/index.js"
    },
    "./server": {
      "types": "./dist/server.d.ts",
      "import": "./dist/server.js"
    },
    "./package.json": "./package.json"
  },
  "files": ["dist"],
  "sideEffects": false,
  "engines": { "node": ">=20" }
}
```

| Field | Purpose | Trap |
| --- | --- | --- |
| `exports` | encapsulation + conditions | omitting it lets deep imports in |
| `types` condition | declaration resolution | must precede `import`/`require` |
| `imports` (`#alias`) | internal subpath imports | needs matching exports for consumers |
| `typesVersions` | TS-version-specific types | avoid; support one modern TS |
| `sideEffects` | tree-shaking hint | `false` on a package with real side effects breaks apps |
| `files` | publish allowlist | `dist` built before `npm pack` |

Condition ordering matters: Node takes the first matching key. Put `types` first, then `import`, then `require`, then `default`. The official docs enumerate the full condition set (`node`, `browser`, `development`, `production`, `module-sync`); use the least number that solves the problem.

## 3. ESM/CJS interop

| From | To | Behavior |
| --- | --- | --- |
| ESM | CJS | default import = `module.exports`; named imports work when statically analyzable |
| CJS | ESM | `require(esm)` on current Node lines; otherwise dynamic `import()` only |
| Bundled ESM | CJS dependency | interop shims; test the built output |
| CJS | ESM with TLA | not allowed in `require`; use `import()` |

```ts
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const legacy = require("legacy-cjs-package"); // when you must, in ESM

// Dynamic import of either format
const mod = await import("dual-package");
```

`__esModule` interop is why `esModuleInterop` exists. In new code, prefer `module: nodenext` (which implies `esModuleInterop`) and write explicit default imports. Do not rely on `export =` types from a CJS dependency being transparent.

## 4. `verbatimModuleSyntax` and type-only imports

```ts
import type { User } from "./types.js";     // erased at emit
import { parseUser } from "./parse.js";     // kept
export type { User };                       // re-export types explicitly
```

- `verbatimModuleSyntax` keeps import/export syntax exactly as written instead of guessing; it makes each file's format explicit.
- Requires `import type`/`export type` for types; otherwise you ship a runtime import of a type-only module.
- Pairs with `isolatedModules` (bundlers compile files independently) and `erasableSyntaxOnly` (Node type stripping).
- Forbidden forms under these flags: `enum`, `namespace` with runtime members, parameter properties in constructors, and `import x = require(...)`.

## 5. Path aliases

`paths` are a compiler-only mapping. Runtimes and bundlers know nothing about them unless configured, so every alias needs a runtime counterpart.

```jsonc
// tsconfig.json — type-checking view
{ "compilerOptions": { "baseUrl": ".", "paths": { "@/*": ["./src/*"] } } }
```

| Environment | Runtime mapping |
| --- | --- |
| Vite | `resolve.alias` or `vite-tsconfig-paths` |
| Node | package `imports` (`#lib/*`) or a loader |
| Jest/Vitest | `resolve.alias` in test config |
| ts-node / tsx | tsconfig-paths loader |

Prefer Node subpath imports (`import "#config"` with an `imports` map) for server code: they resolve in Node, TypeScript, and most bundlers with one declaration. Avoid `baseUrl` entirely in new projects; use relative `paths` from `tsconfig.json`.

## 6. Transpilers: who type-checks

| Tool | Type-check | Speed | Use for |
| --- | --- | --- | --- |
| `tsc` | yes | slowest | libraries, CI gate, DTS |
| `tsgo` (native TS 7 preview) | yes | much faster | CI type gate, verify stability upstream |
| swc | no | very fast | Next.js, large transpile farms |
| esbuild | no | very fast | Vite deps, tsup, scripts |
| oxc | no | very fast | oxlint/oxfmt, emerging transforms |

Non-negotiable: a bundler or transpiler passing is not evidence of type safety. CI runs `tsc --noEmit` (or native equivalent) once over the whole workspace; with project references use `tsc -b` for incremental builds.

Gotchas when transpiling without checking: decorators need configured semantics (stage-3 versus legacy), `const enum` is not supported under `isolatedModules` (use `as const` objects), and type-only imports must be explicit.

## 7. Library build tools

| Tool | Engine | Formats | DTS | Choose when |
| --- | --- | --- | --- | --- |
| `tsc` | tsc | any | native | tiny libs, max compatibility, no bundling |
| `tsdown` | Rolldown | esm+cjs | yes (isolatedDeclarations-friendly) | modern default for packages |
| `tsup` | esbuild | esm+cjs | yes | mature, widely used |
| `unbuild` | rollup+esbuild | esm+cjs | yes | Nuxt ecosystem |
| Vite library mode | Rollup | esm (+cjs) | plugin | already in a Vite repo |

```jsonc
// package.json scripts for a tsdown-built package
{
  "scripts": {
    "build": "tsdown src/index.ts --format esm,cjs --dts",
    "prepack": "npm run build",
    "check:exports": "publint && attw --pack ."
  }
}
```

Always run `publint` and `@arethetypeswrong/cli` (`attw`) before publishing: they catch missing `types` conditions, `.d.ts` format mismatches, and masquerading ESM/CJS. These checks are cheap and catch the most common packaging bugs.

## 8. Dual publishing

Dual publishing means shipping both ESM and CJS. Costs: two builds, the dual-package hazard (two module instances), conditional exports that must stay in sync, and `.d.cts`/`.d.mts` declaration pairs.

Decision table:

| Consumer base | Recommendation |
| --- | --- |
| Modern only (Node 20+, bundlers) | ESM only — simplest, shipping fewer files |
| Mixed, CJS consumers exist | Dual publish, test both entry points in CI |
| CJS-only tooling ecosystem | CJS only for that one adapter package; keep core ESM |
| Published utility with wide reach | Dual publish + `publint`/`attw` gates |

Test matrix for dual packages: `node -e "require('./dist/index.cjs')"`, `node --input-type=module -e "import('./dist/index.js')"`, plus `attw --pack .`. Add a TypeScript consumer smoke test that imports both entry points.

## 9. npm publishing

Checklist-grade practice:

- `npm pack --dry-run` and inspect the file list before every first release.
- Publish with provenance: `npm publish --provenance --access public` on a CI provider that supports OIDC, or configure trusted publishing so no token exists at all.
- `files` allowlist plus `.npmignore` only as a fallback; never publish `src`, tests, or sourcemaps without reason (declaration maps are often worth keeping).
- Enforce `engines` and document the supported Node range; run the test matrix on the floor version.
- Use `changesets` or release-please for versioning; tag releases; keep a CHANGELOG generated from commits.
- `npm audit signatures` verifies registry signatures of installed dependencies.

## 10. JSR publishing

JSR is the ESM/TypeScript-native registry used by Deno and consumable from npm via `npm:` / `jsr:` specifiers.

```jsonc
// jsr.json
{
  "name": "@acme/lib",
  "version": "1.2.0",
  "exports": "./src/index.ts",
  "publish": { "include": ["src/**/*.ts", "README.md", "LICENSE"] }
}
```

- JSR consumes TypeScript source directly; ship explicit types ("slow types" are rejected when they cannot be inferred without running the compiler).
- `deno publish` runs the gate; from npm-only toolchains use `npx jsr publish`.
- Avoid Node built-ins in a JSR package published for Deno; use `node:` specifiers if you must.

## 11. Migration notes: CJS to ESM

1. Set `"type": "module"` and rename CJS-only files to `.cjs`.
2. Replace `require`/`module.exports`/`__dirname` with `import`, `export`, and `import.meta.dirname` (or `fileURLToPath`).
3. Convert `require()` of JSON to import attributes (`with { type: "json" }`) where the runtime supports it, or read with `fs`.
4. Add explicit extensions in relative imports when targeting Node directly.
5. Deal with TLA: only ESM supports it; make initialization explicit and ordered.
6. Update tooling configs in the same PR; run the dual-entry smoke tests.
7. Ship as a major version if the public package layout changes.

Common blockers: CJS-only dependencies (wrap in one adapter, or switch if maintained), Jest configs (Vitest or `ts-jest` ESM mode), and `__dirname` in config files.

## Anti-patterns

| Anti-pattern | Symptom | Fix |
| --- | --- | --- |
| `moduleResolution: node` in new code | deep imports work locally, break in ESM | `bundler` or `nodenext` |
| No `exports` map | consumers deep-import internals | add exports, treat as API |
| `types` after `import` condition | "types show as any" reports | put `types` first |
| `main` only | CJS/ESM mismatch at runtime | explicit exports conditions |
| Path alias without runtime mapping | works in editor, fails at run | mirror in bundler/runtime |
| Building with esbuild and calling it done | type errors ship | separate `tsc --noEmit` gate |
| Publishing without `publint`/`attw` | broken types for subset of users | gate the release |

## Checklist

- [ ] `module`/`moduleResolution` match the actual consumer (table above).
- [ ] `exports` map with `types` first; `files` allowlist; `sideEffects` correct.
- [ ] `verbatimModuleSyntax` on; all type-only imports explicit.
- [ ] Type-check gate in CI distinct from build/transpile.
- [ ] `publint` and `attw` pass for every published package.
- [ ] Dual-package CI smoke tests when shipping both formats.
- [ ] Provenance or trusted publishing enabled; lockfile committed.
- [ ] Supported Node range documented and tested on the floor.

Related: [01-type-system](./01-type-system.md) for declaration patterns, [05-runtimes](./05-runtimes.md) for how each runtime resolves modules, [08-quality-tooling](./08-quality-tooling.md) for monorepo build graphs.
