---
description: "Monorepo management — tool comparison (Nx, Turborepo, Lerna, pnpm workspaces), shared config, dependency management, build caching, CI optimization, versioning"
---

# Monorepo

## Tool Comparison

| Tool | Language | Build Cache | Task Orchestration | Remote Caching | Codegen |
|------|----------|-------------|-------------------|----------------|---------|
| **Nx** | TS/JS, Go core | Yes | Yes, DAG-based | Nx Cloud | Yes |
| **Turborepo** | TS/JS, Rust core | Yes | Yes, pipeline | Vercel Remote | No |
| **pnpm workspaces** | TS/JS | No (plugin addon) | No | No | No |
| **Lerna** | TS/JS | No (legacy) | No (task delegation) | No | No |
| **Bazel** | Polyglot | Yes, granular | Yes | Yes, remote | No |
| **Rush** | TS/JS | Yes | Yes (Rush commands) | Yes | Yes (Heft) |

### Recommendation

| Scenario | Tool |
|----------|------|
| Frontend-heavy monorepo (React, Vue, shared libs) | Turborepo or Nx |
| Full-stack monorepo (FE + BE + mobile) | Nx |
| Polyglot monorepo (Go, TS, Python, Rust) | Bazel |
| Simple shared packages | pnpm workspaces |

## Repository Structure

```
repo-root/
  packages/
    ui/              # Shared UI components
    utils/           # Shared utilities
    eslint-config/   # Shared ESLint config
  apps/
    web/             # Frontend app (Next.js, Vite)
    api/             # Backend app (NestJS, FastAPI)
    mobile/          # Mobile app (React Native)
    docs/            # Documentation site
  tools/
    scripts/         # Shared scripts
    generators/      # Code generators
  .github/
    workflows/       # CI pipelines
  package.json       # Root workspace config
  pnpm-workspace.yaml
  nx.json            # Nx config
  tsconfig.base.json # Shared tsconfig
```

## Shared Configuration

- Base configs in root: `tsconfig.base.json`, `.eslintrc.base.js`, `.prettierrc`.
- Each package extends or overrides as needed.
- Use `@repo/typescript-config`, `@repo/eslint-config` pattern.

```jsonc
// packages/tsconfig/tsconfig.base.json
{
  "compilerOptions": {
    "strict": true,
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "declaration": true,
    "composite": true
  }
}
```

## Dependency Management

| Concern | Practice |
|---------|----------|
| Hoisting | Use pnpm with strict isolation (no phantom deps) |
| Shared deps | Pin versions at root, use overrides/resolutions |
| Deduplication | Run `pnpm dedupe` after adding deps |
| Lockfile | Commit lockfile, review changes in PR |
| Audit | Run `pnpm audit` / `npm audit` in CI |

## Build Caching

- Local cache: `.nx/cache/` or `.turbo/` (gitignored).
- Remote cache: Nx Cloud, Turborepo remote cache, or custom S3.
- Invalidation on: source hash, dependency changes, tool version changes.

### Cache Key Components

```
hash(source + dependencies + config + env_vars) -> cache hit/miss
```

## CI Optimization

| Strategy | Savings | Implementation |
|----------|---------|----------------|
| Affected detection | 70-90% | `nx affected:test --base=main` |
| Parallel task execution | 40-60% | `nx run-many -t build -p 4` |
| Remote caching | 50-80% | Shared cache across CI runners |
| Dependency graph splitting | 30-50% | Run affected apps independently |

### GitHub Actions Example

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: pnpm/action-setup@v4
      - run: pnpm install
      - run: npx nx affected:build --base=origin/main
      - run: npx nx affected:test --base=origin/main --parallel=4
```

## Code Generation

| Tool | Purpose | Example |
|------|---------|---------|
| Nx generators | Create libs, apps, components | `nx g @nx/react:component` |
| Plop | Custom project generators | `plop component` |
| Hygen | Template-based scaffolding | `hygen component new` |

## Versioning Strategies

| Strategy | Mechanism | Use Case |
|----------|-----------|----------|
| Independent | Each package versioned separately | Libraries, shared packages |
| Synchronized | Single version for all packages | Shipping all apps together |
| Fixed (Lerna) | Single version, all packages release together | Classic monorepo approach |
| Changesets | Per-PR version decisions | Teams wanting changelog automation |

### Recommendation

Use Changesets for most monorepos — automatic changelog generation, per-package versioning, and PR-driven workflow.

```bash
pnpm add -w @changesets/cli
pnpm changeset init
# On each PR: pnpm changeset
# On merge to main: pnpm changeset version && pnpm changeset publish
```
