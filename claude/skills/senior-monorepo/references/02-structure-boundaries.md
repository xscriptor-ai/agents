# Structure and Boundaries

> Scope: apps/packages/libs layout, package taxonomy, dependency direction rules, public APIs, ownership, and enforcement.

Structure is the cheapest form of architecture: it decides what can depend on what before any code is written. A monorepo without enforced boundaries degrades into a distributed tangle with a single lockfile.

## 1. Canonical layout

```
repo/
  apps/                  # deployable units (web, api, worker, mobile)
    web/
    api/
  packages/              # publishable or reusable units
    ui/                  # design system components
    config/              # shared config packages
      tsconfig/
      eslint-config/
    contracts/           # API schemas, generated clients
  libs/                  # non-published shared code (scopes by domain)
    billing/
      feature-invoices/
      data-access/
      util/
  tools/                 # generators, scripts, repo automation
  docs/                  # ADRs, runbooks, onboarding
  e2e/                   # cross-app end-to-end suites
  package.json
  pnpm-workspace.yaml
  turbo.json | nx.json | moon.yml
  tsconfig.base.json
  CODEOWNERS
```

Rules that make this layout work:

- `apps/*` may depend on `packages/*` and `libs/*`, never on another app. Cross-app logic belongs in a package.
- `packages/*` may depend on other packages; they must not import apps.
- `libs/*` are internal; if one becomes a product, promote it to `packages/` deliberately.
- `tools/*` are dev-only and owned by the platform team; runtime code must never import them.
- One concern per directory level. Mixing `apps`, `services`, `frontend`, and `backend` at the root creates taxonomy debates; pick names once and document them.

Alternatives that also work, provided the dependency direction is enforced:

| Layout style | Root dirs | Best when |
| --- | --- | --- |
| Type-first (Nx convention) | `apps/`, `libs/` | JS/TS, heavy code sharing, Nx |
| Product-first | `apps/`, `packages/` | library-heavy or npm-publishing workspaces |
| Domain-first | `domains/<domain>/apps`, `domains/<domain>/libs` | large orgs with autonomous domain teams |
| Polyglot | `apps/`, `libs/`, `services/`, `crates/`, `cmd/` | multiple languages with per-language conventions |
| Flat | `packages/*` only | small repos; every package is a library |

Do not invent a hybrid taxonomy mid-flight; document the mapping and migrate with [08-migration](./08-migration.md).

## 2. Package taxonomy

Tags or directory naming encode package type. Nx's model is a good reference even outside Nx:

| Type | Purpose | May depend on |
| --- | --- | --- |
| `app` | bootstrap, routing, wiring | feature, ui, util, data-access, contracts |
| `feature` | user-facing capability, one route/flow | ui, data-access, util, contracts |
| `ui` | presentational components, no data fetching | util, design tokens |
| `data-access` | API clients, stores, repositories | util, contracts |
| `util` | pure helpers, no framework imports | other util |
| `contracts` | schemas, generated types, protocol definitions | nothing runtime-heavy |
| `config` | tooling configuration only | nothing |
| `e2e` | tests only | anything, but nothing depends on it |

Two independent axes are useful:

- `type:*` — `app`, `feature`, `ui`, `data-access`, `util`, `contracts`, `config`, `e2e`.
- `scope:*` — domain or team boundary, for example `scope:billing`, `scope:checkout`, `scope:shared`.

Dependency rule: a `scope` may depend on `scope:shared` and on itself, never on another scope without an explicit allowance. That single rule prevents most accidental coupling in a growing repo.

## 3. Dependency direction

Default direction, from most general to most specific:

```
types/contracts  ->  util  ->  data-access  ->  ui  ->  feature  ->  app
                     ^                              |
                     +------------------------------+
                        (within a type, same scope)
```

- Dependencies point inward/downward: specific code may import general code, never the reverse.
- Cycles are forbidden, including "cycles through a barrel" and "cycles through types".
- A `feature` must not import another `feature` directly; extract the shared part to `util`/`data-access` or compose at the app level via events, props, or routing.
- Apps compose; they do not export reusable logic. If an app exports, it is a package.
- Environment-specific code (browser-only, node-only) is isolated in leaf packages so the dependency graph can express compatibility.

Encode these rules, do not trust memory:

```jsonc
// nx.json enforce-module-boundaries / eslint config
{
  "depConstraints": [
    { "sourceTag": "scope:shared", "onlyDependOnLibsWithTags": ["scope:shared"] },
    { "sourceTag": "scope:billing", "onlyDependOnLibsWithTags": ["scope:billing", "scope:shared"] },
    { "sourceTag": "type:feature", "onlyDependOnLibsWithTags": ["type:ui", "type:data-access", "type:util", "type:contracts"] },
    { "sourceTag": "type:ui", "onlyDependOnLibsWithTags": ["type:util", "type:contracts"] },
    { "sourceTag": "type:util", "onlyDependOnLibsWithTags": ["type:util", "type:contracts"] },
    { "sourceTag": "type:contracts", "onlyDependOnLibsWithTags": ["type:contracts"] }
  ]
}
```

## 4. Public API and entrypoints

A package without an explicit public API has none: every internal path becomes a dependency contract by accident.

- Declare `exports` in `package.json`; the root export is the supported surface.

```jsonc
// packages/ui/package.json
{
  "name": "@acme/ui",
  "type": "module",
  "exports": {
    ".": { "types": "./dist/index.d.ts", "import": "./dist/index.js" },
    "./tokens.css": "./dist/tokens.css",
    "./package.json": "./package.json"
  },
  "files": ["dist"]
}
```

- For internal source-consumed packages (no build step), export source with a `types` condition or use a `development` condition. See [04-shared-config](./04-shared-config.md).
- Barrels (`index.ts`) are the API, not a convenience. Keep them curated: do not `export *` from feature internals, and avoid barrels that re-export everything and create cycles.
- Type-only exports are explicit (`export type`), so consumers do not pull runtime code for types.
- Path aliases in `tsconfig` must not create an alternate entrance into another package's `src/`. Alias to package names, not to files.
- Breaking a public API requires a semver-major release and a changeset; see [07-versioning-release](./07-versioning-release.md).

## 5. Enforcement

| Layer | Tool | What it catches |
| --- | --- | --- |
| Lint | `@nx/enforce-module-boundaries` | tag violations, deep imports, cycles, lazy-load misuse |
| Lint | `eslint-plugin-boundaries`, `eslint-plugin-import` (`no-restricted-paths`) | custom element-type rules, forbidden paths |
| Graph | `dependency-cruiser` | cycles, orphans, forbidden directions in non-Nx repos |
| Runner | `turbo boundaries` | undeclared cross-package imports in Turborepo workspaces |
| Types | project references / `tsc -b` | imports that cannot resolve through package APIs |
| Policy | `sherif`, custom scripts | missing entrypoints, inconsistent fields, version skew |
| Review | CODEOWNERS | ownership gaps and unauthorized surface changes |

Example `dependency-cruiser` rule:

```js
// .dependency-cruiser.cjs
module.exports = {
  forbidden: [
    { name: "no-app-to-app", severity: "error",
      from: { path: "^apps/([^/]+)/" }, to: { path: "^apps/(?!$1)" } },
    { name: "no-deep-imports", severity: "error",
      from: { pathNot: "^packages/ui/" },
      to: { path: "^packages/[^/]+/src/" } }
  ],
  options: { tsConfig: { fileName: "tsconfig.base.json" }, doNotFollow: { path: "node_modules" } }
};
```

Practical rules for enforcement:

1. Run boundary checks in lint (`nx lint`, `eslint .`), not in a separate nightly job; developers must see failures locally.
2. Keep the rules in one config file, not scattered comments. Link the file from `CONTRIBUTING.md`.
3. Fail on cycles first; they are objective and uncontroversial. Then add tag rules.
4. Exemptions are temporary and tracked: an inline disable needs an owner and an expiry issue.
5. When a rule is widely violated, the rule or the structure is wrong; decide which and change it explicitly.

## 6. Ownership

Structure defines technical boundaries; ownership defines human ones.

- Map directories to teams in `CODEOWNERS`, most specific rule last.
- Every package directory must match at least one rule; unowned packages rot fastest.
- Generated and vendored directories get their own owner (usually the platform or the producer team), not "everyone".
- Protected paths (public API, contracts, CI config, release tooling) require the owning team plus the platform team.
- Ownership is reviewed when packages move; a directory rename without a CODEOWNERS update silently orphans the package.

See [09-governance-metrics](./09-governance-metrics.md) for coverage measurement and drift checks.

## 7. Splitting and moving packages

- Move code only with its tests, its owner, and its consumers in the same change set.
- Promotion path: `libs/` -> `packages/` when external consumers or a release cadence appear; never the reverse without a deprecation window.
- A package earns extraction when at least two consumers exist and the API is stable; premature extraction creates churn.
- Deletion is a feature: remove empty or single-consumer packages rather than letting the repo accrete.
- Renames are breaking changes for consumers: ship an alias/reexport package for one release cycle when the package is published.

## 8. Polyglot layouts

When the repo contains multiple languages, keep per-language idioms but one top-level contract:

- JS/TS: `apps/`, `packages/`, per [04-shared-config](./04-shared-config.md).
- Go: `services/<name>/`, `cmd/`, `internal/`, `pkg/` inside each module; one module per independently versioned unit.
- Python: `services/<name>/`, `packages/<name>/` with `pyproject.toml` per package, workspace via `uv` or `poetry` groups.
- Rust: `crates/<name>` in a root workspace `Cargo.toml`.
- Shared contracts: `packages/contracts` (protobuf/OpenAPI) or `proto/`, consumed by all languages; see [06-codegen](./06-codegen.md).

Cross-language dependencies should flow through generated contracts or network APIs, not through checked-in copies of code.

## 9. Anti-patterns

| Anti-pattern | Symptom | Fix |
| --- | --- | --- |
| No tags or boundary rules | arbitrary imports, cycles | add `type:`/`scope:` tags and enforce |
| Deep imports into `src/` | refactors break unrelated apps | exports map plus lint rule |
| `shared`, `common`, `utils` mega-package | everything depends on everything | split by domain; name by capability |
| Barrel `export *` from internals | hidden public API, cycles | curated exports |
| Apps imported by packages | tangled deploy graph | move shared code to packages |
| `file:` links to avoid workspace protocol | broken dedupe, path fragility | use `workspace:*` |
| Directory rename without CODEOWNERS update | orphaned ownership | include ownership in the move PR |
| One team owns "the monorepo" | bottleneck, platform burnout | distribute package ownership; platform owns the system |

## Checklist

- [ ] Top-level taxonomy chosen and documented; no synonyms (`libs` vs `packages` vs `shared`) fighting.
- [ ] Every package tagged by `type` and `scope`, or the equivalent documented convention.
- [ ] Dependency direction rules written down and machine-enforced in lint/CI.
- [ ] Each package has a curated `exports` surface; deep imports fail checks.
- [ ] Cycles are a build failure, not a code-review discussion.
- [ ] CODEOWNERS covers every package and tooling directory; coverage measured.
- [ ] App-to-app and package-to-app imports are forbidden and detected.
- [ ] Promotion, extraction, and deletion paths are documented.
- [ ] Polyglot repos share contracts through generated packages, not copied code.

Related: [01-tools](./01-tools.md) for runner capabilities, [04-shared-config](./04-shared-config.md) for package build/output wiring, [09-governance-metrics](./09-governance-metrics.md) for ownership and drift metrics.
