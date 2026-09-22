# Dependency Management

> Scope: workspace protocols, catalogs, peer dependencies, hoisting and dedupe, version policy, overrides, and update automation.

Dependency management in a monorepo has three layers: install correctness (package manager), version policy (constraints and singletons), and automation (updates, audits, drift). Most incidents come from conflating them.

## 1. Workspace protocol

Internal dependencies must resolve locally, always, and must be rejected if the local package is missing.

| Protocol | Meaning | Use for |
| --- | --- | --- |
| `workspace:*` | exact local package, any version | apps and tightly coupled internal deps |
| `workspace:^` | `^` local version at pack/publish time | libraries consumed by other packages |
| `workspace:~` | `~` local version | rarely; tight coupling within a patch range |
| `workspace:^1.2.0` | range with a minimum | published compatibility floors |
| `file:../pkg` | filesystem link | never in a workspace; breaks dedupe and publish |
| `link:../pkg` | symlink without install | never in a workspace |
| plain `1.2.3` | registry version | external packages only; against an internal package it silently installs from the registry |

```jsonc
// packages/ui/package.json
{
  "dependencies": { "@acme/tokens": "workspace:^" },
  "devDependencies": { "@acme/tsconfig": "workspace:*" }
}
```

Rules:

- The root manifest is `private: true`; only packages intended for publishing leave it unset.
- CI verifies that no manifest contains `file:` or `link:` references to workspace paths.
- When a package is published, `workspace:^` is rewritten to the real version (pnpm/npm/Yarn all do this at pack time). Verify with `npm pack --dry-run` before the first release.
- `workspace:*` on a published package rewrites to the exact version; use it for internal-package lockstep, `workspace:^` otherwise.

## 2. Catalogs

Catalogs centralize version decisions so every package uses the same range for the same dependency. pnpm 9.5+ implements `catalog:` in `pnpm-workspace.yaml`; check current support if using other managers.

```yaml
# pnpm-workspace.yaml
packages:
  - "apps/*"
  - "packages/*"
catalog:
  react: ^19
  react-dom: ^19
  typescript: ~5.9
  vitest: ^3
  zod: ^4
catalogs:
  react18:
    react: ^18
    react-dom: ^18
catalogMode: strict
```

```jsonc
{ "dependencies": { "react": "catalog:", "react-dom": "catalog:" } }
```

Notes:

- `catalogMode: strict` forbids direct version ranges, forcing every dependency through the catalog. This is the strongest consistency policy and the highest-friction one.
- Use named catalogs only for genuine parallel majors (for example a legacy React 18 app while the platform moves to 19). Two names for one major is drift.
- Catalogs govern declarations, not resolution; overrides (below) still handle transitive conflicts.
- The catalog is the single place to audit "what versions do we run" per dependency.

## 3. node_modules layout and hoisting

| Manager | Layout | Phantom deps | Notes |
| --- | --- | --- | --- |
| pnpm | strict symlinked store, `.pnpm/` | prevented by default | best isolation; `node-linker=hoisted` escapes hatch |
| npm workspaces | hoisted, nested on conflict | possible | simple; audit with `npm ls` |
| Yarn classic | hoisted | possible | legacy |
| Yarn Berry (PnP or node-modules) | PnP or virtual | prevented in PnP | PnP needs tool compatibility checks |
| Bun | hoisted with isolated install option | possible | verify current workspace semantics upstream |

Practices:

- Prefer the strict layout; a phantom dependency is a latent breakage that appears the day a transitive dep disappears.
- `public-hoist-pattern` and `shamefully-hoist` are compatibility escape hatches for stubborn tools (older CLIs, some test runners). Each use gets a comment and an issue to remove it.
- Never install dependencies implicitly at the root to "make it work"; declare them where they are imported.
- The lockfile is committed and reviewed. Lockfile-only diffs are still diffs: they carry supply-chain changes.
- Keep `engines` and `packageManager` pinned; mismatched managers silently rewrite lockfiles.

## 4. Peer dependencies

Libraries must not force a second copy of a singleton runtime into an app's graph.

| Dependency kind | Declare as | Examples |
| --- | --- | --- |
| Singleton runtime the consumer must own | `peerDependencies` | React, Vue, Angular core, ORM client, `zod` in plugin ecosystems |
| Runtime code the lib controls | `dependencies` | small utilities, internal helpers |
| Types only | `devDependencies` + optional peer | `@types/*`, framework types |
| Optional integration | `peerDependencies` + `peerDependenciesMeta.optional` | date libraries, adapters |

Rules:

- Test the peer ranges in CI: install the minimum supported and the latest in a matrix when the library is published.
- Widen ranges only when tests prove compatibility; narrowing is a breaking change.
- Avoid `dependencies` for anything the app also uses directly, or you will ship duplicates.
- `pnpm install` auto-installs peers by default in recent versions; disable for published library workspaces if strictness matters, and declare peers explicitly in the library manifest.

## 5. Version constraints and single-version policy

| Policy | Meaning | Use when |
| --- | --- | --- |
| Single version | exactly one version of a dependency repo-wide | runtime singletons, large libraries, framework core |
| Range drift allowed | each package picks its range | leaf utilities with no shared state |
| Catalog strict | all declarations from one catalog | consistency is a hard requirement |

Detect skew before it bites:

```bash
pnpm why -r <package>            # who depends on it and why
pnpm dedupe --check              # would dedupe change the lockfile
pnpm outdated -r                 # outdated across the workspace
pnpm audit --prod                # known vulnerabilities (also run in CI)
```

Non-JS equivalents: `npm ls`, `yarn why`, and for policy tools `syncpack` or `sherif` to list mismatched versions across manifests.

If several versions of a critical dependency exist, fix the cause (conflicting peer ranges, duplicated majors) rather than forcing resolution with overrides.

## 6. Overrides and patches

- `overrides` (npm/pnpm) and `resolutions` (Yarn) force a transitive version repo-wide. Use them for security hotfixes and genuine incompatibilities, not for tidiness.
- Every override is documented with the reason and a removal condition; overrides outlive their justification by years.
- Test after changing an override: forced versions can break the very package that needed the old one.
- `pnpm patch <pkg>` / `patch-package` create a local patch when an upstream fix does not exist. Patches are emergency measures: keep them minimal, pin the base version, and open an upstream PR.
- Never patch via `postinstall` scripts that rewrite files; they are invisible to review and break under remote caching.

## 7. Update automation

Renovate is the strongest fit for workspaces; Dependabot is adequate for simple repos. Verify configuration syntax against the current tool version upstream.

Renovate essentials for monorepos:

```jsonc
// renovate.json
{
  "extends": ["config:recommended", ":dependencyDashboard", ":semanticCommits"],
  "lockFileMaintenance": { "enabled": true, "schedule": ["before 6am on monday"] },
  "postUpdateOptions": ["pnpmDedupe"],
  "rangeStrategy": "bump",
  "packageRules": [
    { "groupName": "react", "matchPackageNames": ["react", "react-dom", "react", "/^@types\\/react/"] },
    { "groupName": "test tooling", "matchPackageNames": ["vitest", "playwright", "@vitest/**"] },
    { "matchUpdateTypes": ["major"], "dependencyDashboardApproval": true },
    { "matchDepTypes": ["peerDependencies"], "rangeStrategy": "widen" }
  ]
}
```

- Group by ecosystem and tool family; ungrouped bots create review fatigue and rebase churn.
- Enforce major-update approval: majors deserve a human decision, a changeset, and a test run.
- Let the bot run the full affected pipeline; a dependency bump that does not pass tests is not mergeable.
- Schedule lockfile maintenance separately from version bumps; mixed diffs are unreviewable.
- Keep a dependency dashboard; "no updates for six months" is a risk signal, not stability.
- Dependabot equivalent: `directory: "/"` plus `groups` and `multi-ecosystem-groups` in `.github/dependabot.yml`; verify current syntax upstream.

## 8. Security and audit in a workspace

- Run `pnpm audit --prod` (or the manager equivalent) in CI on a schedule and on lockfile changes; also run SBOM generation for published artifacts.
- Use `onlyBuiltDependencies`/`ignoredBuiltDependencies` (pnpm) to whitelist lifecycle scripts. Postinstall scripts are the primary npm supply-chain vector; default to blocking new ones.
- Pin GitHub Actions to commit SHAs; pin generator and release tooling versions.
- For published packages, enable npm provenance/trusted publishing; see [07-versioning-release](./07-versioning-release.md).
- Treat the root lockfile as a security artifact: it is the exact dependency set for every app, so a compromised transitive dependency is repo-wide, not app-local.

## 9. Anti-patterns

| Anti-pattern | Symptom | Fix |
| --- | --- | --- |
| Mixed `file:` and `workspace:` links | dedupe failures, broken publishes | workspace protocol only |
| `shamefully-hoist=true` | phantom deps return | fix the offending tool or isolate it |
| Root `node_modules` as a dumping ground | undeclared imports work locally, fail in CI/prod | declare per package |
| Duplicate React/query libs | hooks errors, bundle bloat | peer deps + single-version policy |
| Unreviewed override | mystery resolved versions | document, test, set expiry |
| Renovate with no grouping | rebase fatigue, stale PRs | group, batch, schedule |
| Lockfile merge conflicts resolved by deletion | version regressions | regenerate lockfile, review diff |
| Catalog named after a team, not a major | hidden divergence | one catalog unless a real major split |

## Checklist

- [ ] All internal deps use `workspace:`; CI rejects `file:`/`link:`.
- [ ] Version decisions centralized (catalog or single-version policy) for critical deps.
- [ ] Strict `node_modules` layout; every hoist exception documented.
- [ ] Singleton runtimes declared as peers with tested ranges.
- [ ] No unexplained duplicate versions of framework or state libraries.
- [ ] Overrides and patches documented with removal conditions.
- [ ] Renovate/Dependabot configured with grouping, schedules, and major-approval gates.
- [ ] Audit and SBOM checks run in CI; lifecycle scripts whitelisted explicitly.
- [ ] Lockfile review is part of every dependency PR.

Related: [01-tools](./01-tools.md) for workspace-manager choice, [04-shared-config](./04-shared-config.md) for internal package consumption, [09-governance-metrics](./09-governance-metrics.md) for drift detection.
