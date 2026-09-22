# Quality and Tooling

> Scope: tsconfig hardening flag by flag, ESLint 9 flat config, Biome/oxlint, Prettier, CI gate order, bundle budgets, and monorepo wiring.

Version floors (verify upstream; treat as minimums):

| Tool | Current line | Notes |
| --- | --- | --- |
| TypeScript | 5.x, native 7 line in preview | same semantics, faster binaries |
| ESLint | 9+ | flat config is the default format |
| typescript-eslint | 8+ | `projectService` for typed linting |
| Biome | 2+ | formatter + linter in one binary |
| oxlint | current | Rust lint, partial rule parity; oxfmt emerging |
| Prettier | 3+ | formatting reference |
| pnpm | 9/10+ | strict, content-addressed installs |
| Turborepo | 2+ | task graph + remote cache |

## 1. tsconfig hardening, flag by flag

Baseline: `"strict": true`. Everything below is a deliberate add-on; each has a cost.

| Flag | What it catches | Cost | Recommend |
| --- | --- | --- | --- |
| `strict` | the classic family (`strictNullChecks`, `noImplicitAny`, ...) | writing null checks | always |
| `noUncheckedIndexedAccess` | `arr[i]` may be `undefined` | more guards in loops/indexing | apps yes; libraries yes unless array-heavy perf code |
| `exactOptionalPropertyTypes` | `{ a: undefined }` vs optional `a` | friction with optional props | yes for libraries; assess for apps |
| `noImplicitOverride` | missing `override` on subclass members | annotation noise | yes |
| `noFallthroughCasesInSwitch` | accidental case fallthrough | restructure switches | yes |
| `noImplicitReturns` | paths returning `undefined` implicitly | explicit returns | yes |
| `noPropertyAccessFromIndexSignature` | `opts.foo` on index signatures | `opts["foo"]` | optional, strict teams |
| `useUnknownInCatchVariables` | `catch (e: any)` | catch narrowing | yes (in `strict` since 4.4) |
| `allowUnreachableCode: false` | dead branches | none | yes |
| `allowUnusedLabels: false` | stray labels | none | yes |
| `verbatimModuleSyntax` | format ambiguity | `import type` discipline | yes |
| `isolatedModules` | unsafe single-file transforms | none with above | yes |
| `erasableSyntaxOnly` | enums/namespaces/param props | rewrite those constructs | yes if runtime strips types |
| `isolatedDeclarations` | implicit public types | explicit return types | libraries that need fast DTS |
| `skipLibCheck` | dependency `.d.ts` errors | hides broken deps | true in practice, revisit in CI matrix |
| `forceConsistentCasingInFileNames` | case-only import differences | none | yes |
| `noErrorTruncation` | truncated type errors | verbosity | useful when debugging types |
| `noUnusedLocals` / `noUnusedParameters` | dead code | noise without lint | pick one tool (lint or tsc), not both |

Order of adoption: `strict` -> `noUncheckedIndexedAccess` + `noImplicitOverride` + `noFallthroughCasesInSwitch` -> `exactOptionalPropertyTypes` -> `isolatedDeclarations`/`erasableSyntaxOnly` when the build or runtime requires them.

Sample app config:

```jsonc
{
  "compilerOptions": {
    "target": "ES2023",
    "lib": ["ES2023", "DOM", "DOM.Iterable"],
    "module": "preserve",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "noImplicitReturns": true,
    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "skipLibCheck": true,
    "noEmit": true
  },
  "include": ["src", "tests"]
}
```

## 2. ESLint 9 flat config

Flat config is an array of typed objects; there is no cascade of `.eslintrc` files, no `extends` string resolution, and plugins are imported objects.

```js
// eslint.config.js
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import reactHooks from "eslint-plugin-react-hooks";

export default tseslint.config(
  { ignores: ["dist", "coverage", "**/*.generated.ts"] },
  js.configs.recommended,
  tseslint.configs.recommendedTypeChecked,
  {
    languageOptions: {
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
    },
    plugins: { "react-hooks": reactHooks },
    rules: {
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/no-misused-promises": "error",
      "@typescript-eslint/consistent-type-imports": "error",
      "react-hooks/rules-of-hooks": "error",
      "react-hooks/exhaustive-deps": "warn",
    },
  },
);
```

Rules for keeping lint useful:

- Typed linting (`recommendedTypeChecked` + `projectService`) catches the bugs plain ESLint misses (`no-floating-promises`, `await-thenable`); accept the slower lint for that value.
- Keep style out of ESLint: no formatting rules, no sorting debates. One formatter, one truth.
- Zero warnings in CI (`--max-warnings 0`); suppress with a reason and an issue link, not `eslint-disable` strings.
- Lint generated code? Never. Ignore it explicitly.
- Migration from `.eslintrc`: use the official codemod, then delete legacy files; flat config ignores `eslintIgnore`, so re-express ignores in the config.

## 3. Biome and oxlint

| Dimension | ESLint + typescript-eslint | Biome 2 | oxlint |
| --- | --- | --- | --- |
| Language | Node/JS plugins | Rust | Rust |
| Lint + format | separate (Prettier) | one binary | lint only (formatter maturing) |
| Type-aware rules | yes, deep | partial (project domain) | limited |
| Speed | slowest | fast | fastest |
| Ecosystem | full plugin market | growing, conversion from ESLint config | partial parity |
| Best fit | apps needing typed rules | greenfield, speed, single config | pre-commit speed layer |

Practical arrangements: ESLint typed rules as the correctness gate; Biome or oxlint as a fast local/CI complement; Prettier if the team standardizes on it, or Biome as both formatter and basic linter in smaller projects. Never run two formatters.

## 4. Prettier and formatting policy

- One formatter per repo, enforced in CI (`prettier --check .`); editors format on save.
- Keep the config tiny (`printWidth`, `semi`, `singleQuote`, plugins). Formatting arguments end here.
- Plugins worth having: Tailwind class sorting, import organization, framework plugins for `.svelte`/`.vue`.
- Generated files are ignored; lockfiles are never formatted.
- Formatting is a separate commit from logic changes, or a one-time repo-wide commit that does not mix with features.

## 5. CI gate order

Cheapest and most deterministic first; fail fast:

1. Install with frozen lockfile (`pnpm install --frozen-lockfile` / `npm ci`).
2. Format check.
3. Lint (flat config, zero warnings).
4. Type-check (`tsc --noEmit` or `tsgo --noEmit`), using incremental/project references.
5. Unit + component tests with coverage.
6. Build (all packages; verify outputs).
7. Integration tests (Testcontainers), then e2e (Playwright, sharded).
8. Package checks for published libs (`publint`, `attw`, size limits).
9. Bundle analysis on the app (budget check, not a block unless exceeded).

In monorepos, run affected-only for PRs (turbo/nx affected graph) but full on the default branch. Cache everything except test results.

## 6. Bundle analysis and budgets

- Analyzers: `rollup-plugin-visualizer` (Vite/Rollup), `source-map-explorer` (any sourcemapped bundle), framework-specific inspectors.
- Budgets: `size-limit` in CI with per-entry limits; fail on regression beyond a threshold.
- Tree-shaking hygiene: `"sideEffects": false` only when true; avoid top-level side effects; import specific paths from large libraries; verify with the visualizer, not assumptions.
- Code splitting: route-level by default; dynamic import for modals/editors/charts; preload likely next routes.
- Check both raw and gzip/brotli sizes; watch for duplicated dependency versions (pnpm `why`/`dedupe`).
- Server bundles matter too: cold start scales with imported code in serverless/edge.

## 7. Monorepo notes

| Concern | Practice |
| --- | --- |
| Package manager | pnpm workspaces (strict node_modules) or npm workspaces |
| Task running | Turborepo / Nx with declared inputs/outputs |
| TypeScript graph | project references + `composite`, `tsc -b` for incremental |
| Internal deps | `workspace:*` protocol; never `file:` links |
| Versioning | Changesets; one version policy per package |
| Publishing | `publishConfig` per package; shared build config package |
| Lint/format | one root config; packages extend |
| TS version | one version at the root, hoisted; no per-package drift |

Project references sketch:

```jsonc
// packages/core/tsconfig.json
{ "extends": "../../tsconfig.base.json", "compilerOptions": { "composite": true, "outDir": "dist" } }
// apps/web/tsconfig.json
{ "extends": "../../tsconfig.base.json", "references": [{ "path": "../../packages/core" }] }
```

Gotchas: `composite` requires declarations and `rootDir` discipline; path aliases must not bypass package boundaries (import `@acme/core`, not `../../core/src`); and CI must rebuild when `tsconfig` changes, so include configs in task inputs.

## Anti-patterns

| Anti-pattern | Symptom | Fix |
| --- | --- | --- |
| `strict: false` in new code | type system off | start strict, never relax |
| `skipLibCheck` masking own errors | hidden broken code | keep for deps, fix own `.d.ts` |
| Formatting via ESLint | rule conflicts, churn | one formatter |
| Typed lint disabled for speed | floating promises ship | keep typed rules on changed files |
| No bundle budget | slow creep | size-limit in CI |
| Per-package TS versions | incompatible types | single root version |
| Deep relative imports across packages | broken boundaries | package exports only |

## Checklist

- [ ] `strict` plus the hardening set chosen explicitly; every exception documented.
- [ ] One formatter, enforced in CI; zero ESLint warnings.
- [ ] Typed linting enabled; `no-floating-promises` and friends are errors.
- [ ] CI order: install -> format -> lint -> types -> tests -> build -> e2e -> package checks.
- [ ] Bundle budgets enforced for client and server entries.
- [ ] Monorepo: pnpm workspaces, turbo/nx affected graph, project references, one TS version.
- [ ] Published packages gated by `publint` and `attw`.

Related: [02-modules-build](./02-modules-build.md) for packaging gates, [07-testing](./07-testing.md) for test wiring, [10-ecosystem-2026](./10-ecosystem-2026.md) for the tooling landscape.
