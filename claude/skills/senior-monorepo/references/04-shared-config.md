# Shared Configuration and Package Wiring

> Scope: shared tsconfig/ESLint/Prettier/test config packages, project references, internal package consumption patterns, build outputs, and exports maps.

Credentials, lint rules, and compiler flags must not vary by package. Put configuration in versioned packages, consume it everywhere, and let the task graph rebuild consumers when it changes.

## 1. Config as packages

```
packages/config/
  tsconfig/           # @acme/tsconfig
    base.json
    library.json
    app.json
    package.json
  eslint-config/      # @acme/eslint-config
    index.js
    react.js
    node.js
    package.json
  prettier-config/    # @acme/prettier-config
  vitest-config/      # @acme/vitest-config
```

Rules:

- Config packages are `private: true` and `version: 0.0.0` unless external consumers exist; they are consumed with `workspace:*`.
- Export JSON/JS objects, not scripts with side effects; a config package must be side-effect free.
- Config changes are code changes: they require a changeset if published, a CODEOWNERS owner, and a rebuild of affected consumers (declare them as task inputs).
- Never copy a config file into a package "just for this one setting". Use `extends`/spread and an override.
- Keep the number of config packages small; one per tool family, not one per framework unless the divergence is real.

## 2. Shared tsconfig

Layer configs so each package extends the narrowest useful base.

```jsonc
// packages/config/tsconfig/base.json
{
  "$schema": "https://json.schemastore.org/tsconfig",
  "compilerOptions": {
    "target": "ES2023",
    "lib": ["ES2023"],
    "module": "preserve",
    "moduleResolution": "bundler",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "forceConsistentCasingInFileNames": true
  }
}
```

```jsonc
// packages/config/tsconfig/library.json
{
  "extends": "./base.json",
  "compilerOptions": {
    "composite": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "rootDir": "src",
    "outDir": "dist"
  }
}
```

Practice:

- The root `tsconfig.base.json` (if kept) only wires path aliases and references; real defaults live in the config package.
- Do not use path aliases to bypass package boundaries. Alias package names to their built or source entrypoints, never to `../other/src/file`.
- One TypeScript version at the root. Per-package TypeScript versions produce incompatible types and editor confusion.
- `skipLibCheck: true` is standard for apps; libraries still compile their own declarations and test `attw`/`publint`.
- When the runtime uses a bundler, set `module: preserve`/`moduleResolution: bundler`; for Node-native ESM use `nodenext` on the entry packages. Consistency matters more than the exact choice.

## 3. Project references and incremental builds

TypeScript project references turn `tsc -b` into a correct incremental build with declarations shared between packages.

```jsonc
// packages/ui/tsconfig.json
{
  "extends": "@acme/tsconfig/library.json",
  "include": ["src"],
  "references": [{ "path": "../tokens" }]
}
```

```bash
tsc -b packages/ui          # builds dependencies first
tsc -b --watch              # incremental dev loop
```

Notes:

- `composite: true` requires `declaration: true`, explicit `rootDir`, and inclusion of every source file.
- Reference the built declaration output, not the source of another package, when packages are compiled. Source-first consumption is the alternative pattern (below).
- Cache `*.tsbuildinfo`: declare it as a build output (commonly `.tsbuildinfo` next to `dist`) so CI restores it.
- Build configs (`tsconfig*.json`, `package.json` exports) must be task inputs; if they are not, cache invalidation misses real changes.

## 4. Shared ESLint (flat config)

```js
// packages/config/eslint-config/index.js
import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["**/dist/**", "**/coverage/**", "**/*.generated.*"] },
  js.configs.recommended,
  tseslint.configs.recommendedTypeChecked,
  {
    languageOptions: {
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
    },
    rules: {
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/consistent-type-imports": "error",
    },
  },
);
```

```js
// packages/ui/eslint.config.js
import base from "@acme/eslint-config";
export default [...base, { rules: { "no-console": "off" } }];
```

Rules:

- One root lint command (`eslint .` or `nx run-many -t lint`) so CI and editors agree.
- Typed linting needs a `tsconfig` that includes the file; `projectService` eases multi-package setups. Verify current typescript-eslint options upstream.
- Formatting stays out of ESLint; one formatter only.
- Framework configs are separate exports (`@acme/eslint-config/react`), not conditionals inside one config.
- Lint rules that enforce architecture belong here (module boundaries); see [02-structure-boundaries](./02-structure-boundaries.md).

## 5. Prettier and formatting

- One shared config package (`@acme/prettier-config`) referenced from each package's `package.json` or a root `.prettierrc` that extends it.
- CI runs `prettier --check .`; editors run on save.
- Generated files, lockfiles, and vendored code are ignored via `.prettierignore`, not per-package configs.
- Formatting commits are separate from logic. A repo-wide reformat lands once, on a quiet day, with no feature changes mixed in.
- Do not run two formatters (`prettier` plus `biome format`/`dprint`); pick one.

## 6. Shared test and tooling configs

| Config | Package | Notes |
| --- | --- | --- |
| Unit test | `@acme/vitest-config` | shared `defineConfig` with coverage thresholds and setup files |
| E2E | `@acme/playwright-config` | base projects, trace policy, shard support |
| Tailwind | `@acme/tailwind-config` | shared preset/theme tokens; app-level content globs |
| Storybook | shared base config | keep stories inside the package that owns the component |
| Docker | `tools/docker/*` templates | one base image per runtime version |
| Toolchain versions | root `.nvmrc`, `packageManager`, `engines` | one truth; verified in CI |

## 7. Two internal-package consumption patterns

| Pattern | How it works | Pros | Cons |
| --- | --- | --- | --- |
| Just-in-Time (source) | Consumer's bundler compiles the dependency's source via `exports` to `./src/index.ts` under a dev condition | fast inner loop, no build ordering, no dist to clean | bundler must compile everything; published artifacts must strip dev conditions; type-checking scope grows |
| Compiled | Dependency builds `dist/` first; consumer imports built output | publishable as-is, clear API boundary, cacheable build artifacts | build ordering and outputs must be correct; dev loop needs watch mode |

Just-in-Time exports example:

```jsonc
// packages/ui/package.json
{
  "name": "@acme/ui",
  "exports": {
    ".": {
      "development": "./src/index.ts",
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js"
    }
  },
  "publishConfig": {
    "exports": {
      ".": { "types": "./dist/index.d.ts", "import": "./dist/index.js" }
    }
  }
}
```

Choose one pattern per package class and document it. Mixing both within a package produces "works locally, breaks in prod" bugs. Compiled packages are mandatory for anything published.

## 8. Build outputs and exports hygiene

- Standardize output directories: `dist/` for compiled JS/TS packages, `build/` only for apps if the framework demands it. Do not mix `lib/`, `esm/`, `cjs/` per package without reason.
- `files` lists exactly what ships (`dist`, `README.md`); everything else is excluded.
- `exports` conditions order matters: `types` first, then `import`/`require`, then `default`. Subpaths must be explicit; wildcard subpaths only when the API really is a directory tree.
- `sideEffects: false` only when true; a wrong `sideEffects` flag silently drops CSS or polyfills from bundles.
- Ship source maps and declaration maps for libraries; do not ship raw `src/` unless the Just-in-Time pattern requires it.
- Validate before publishing: `npm pack --dry-run`, `publint`, and `attw` (`--profile node16` and `esm-only` as appropriate). See [07-versioning-release](./07-versioning-release.md).
- For apps, do not reuse a library's `exports` build settings; app builds are bundled and can emit with different targets.

## 9. Environment and tool versions

- Node/Python/Go/Rust versions are declared once: `.nvmrc`/`.tool-versions`/`mise.toml`, `engines`, and CI matrix read from them.
- Environment variables are validated at startup against a schema shared across apps (for example a `@acme/env` package with zod); see [06-codegen](./06-codegen.md) for schema-to-types pipelines.
- Never commit `.env` files; commit `.env.example` and validate required keys in CI for apps that need them.
- Tool versions (task runner, package manager, bundler, test runner) are pinned in manifests, not "latest".

## 10. Anti-patterns

| Anti-pattern | Symptom | Fix |
| --- | --- | --- |
| Copy-pasted tsconfig per package | flag drift, inconsistent type behavior | config package + `extends` |
| Path aliases into `../other/src` | hidden coupling, bundler edge cases | package exports only |
| Per-package TypeScript versions | incompatible types across packages | one root version |
| Shared config with side effects | unpredictable imports | pure exported objects |
| Publishing `src/` accidentally | bloated packages, broken types | `files` + `attw` checks |
| `sideEffects: false` without checking | missing CSS/polyfills in prod | audit imports and bundle |
| Mixed Just-in-Time and compiled deps | prod failures after local success | one pattern per package class |
| Config package unowned | silent quality decay | CODEOWNERS entry, required review |

## Checklist

- [ ] Shared config packages exist for tsconfig, ESLint, formatter, and test runners.
- [ ] Every package extends shared config; overrides are explicit and few.
- [ ] Project references used where incremental `tsc -b` is the build path.
- [ ] One internal-package pattern per class, documented; dev conditions stripped at publish.
- [ ] `exports`, `files`, and `sideEffects` are deliberate for every package.
- [ ] Build outputs are consistent and declared as task outputs.
- [ ] Tool and runtime versions pinned once; CI verifies them.
- [ ] `publint`/`attw`/`npm pack --dry-run` gate published packages.

Related: [02-structure-boundaries](./02-structure-boundaries.md) for API surface rules, [03-dependencies](./03-dependencies.md) for workspace protocols, [05-caching-ci](./05-caching-ci.md) for making config changes invalidate caches.
