# Tool Selection

> Scope: Nx, Turborepo, pnpm workspaces, Bazel, Moon, and Make compared on capability, fit, and migration cost.

Version floors (verify upstream; treat as minimums):

| Tool | Current line | Core | Notes |
| --- | --- | --- | --- |
| pnpm | 9/10+ | TS/JS | workspaces, catalogs, strict `node_modules` |
| Turborepo | 2.x | Rust | task graph over package-manager workspaces |
| Nx | 20+/21+ | TS plugins, Rust cache | project graph, generators, plugins, cloud |
| Bazel | 7/8+ | Java | Bzlmod is the default module system |
| Moon | 1.x | Rust | polyglot tasks plus `proto` toolchain manager |
| GNU Make | 4.3+ | C | universal, timestamp-based, no package graph |

## 1. What a task runner must provide

Evaluate tools against these capabilities, not against feature checklists.

1. **Graph** — knows which packages depend on which, and in what order tasks must run.
2. **Scheduling** — runs independent tasks in parallel with deterministic ordering and correct streaming.
3. **Affected detection** — turns a git diff into the minimal set of packages and tasks to run.
4. **Caching** — hashes declared inputs and restores declared outputs, locally and remotely.
5. **Distribution** — remote cache or remote execution shared across machines and CI runners.
6. **Isolation and correctness** — declared environment, hermetic-enough inputs, no ambient state.
7. **Observability** — answers "what ran, why did it run, how long, was it cached".

A workspace manager (pnpm/npm/Yarn) provides install correctness and filtering; it does not provide 3-7. That gap is exactly what a task runner fills.

## 2. Capability matrix

| Capability | pnpm workspaces | Turborepo | Nx | Bazel | Moon | Make |
| --- | --- | --- | --- | --- | --- | --- |
| Dependency install | yes, strict | delegates to PM | delegates to PM | external (rules) | delegates to PM/toolchain | no |
| Task graph | partial (recursive) | yes | yes | yes | yes | manual |
| Affected detection | no | yes | yes | yes (query) | yes | no |
| Local cache | store only | yes | yes | yes | yes | no |
| Remote cache | no | yes | yes (Nx Cloud/self) | yes (native protocol) | yes (self/remote) | no |
| Remote execution | no | no | no (distributed tasks limited) | yes | no | no |
| Generators/codegen | no | `turbo gen` | extensive plugin generators | rules + genrules | templates | no |
| Polyglot native | JS only | JS tasks, any binary | plugins + arbitrary tasks | full | full | any |
| Hermeticity | n/a | moderate | moderate | strict | moderate | weak |
| Plugin ecosystem | large | small | very large | very large | small | n/a |
| Learning curve | low | low | medium | high | medium | low |
| Config format | YAML | JSON/JSONC | JSON | Starlark | YAML/TOML | makefiles |
| Incremental adoption | easy | easy | easy | hard | medium | easy |

## 3. pnpm workspaces

The install layer is the foundation of every JS/TS monorepo; choose it first, independently of the runner.

```yaml
# pnpm-workspace.yaml
packages:
  - "apps/*"
  - "packages/*"
  - "tools/*"
```

```jsonc
// root package.json
{
  "private": true,
  "packageManager": "pnpm@<pinned version>",
  "scripts": {
    "build": "pnpm -r --filter './packages/**' build",
    "test:changed": "pnpm -r --filter '...[origin/main]' test"
  }
}
```

Strengths: strict, content-addressed `node_modules` (no phantom dependencies), `workspace:` protocol, catalogs, reliable recursive and filtered runs, `pnpm deploy` for pruned deployments.

Weaknesses: filters approximate but do not replace a task graph; no task cache, no affected with correct dependency semantics (`...[base]` is useful but coarse), no remote sharing.

Use bare workspaces when the repo is small, build/test time is low, and the team values simplicity. Add a runner the moment CI walls out or cache hit rates become a recurring topic. See [03-dependencies](./03-dependencies.md) for protocol and catalog details.

## 4. Turborepo

A Rust task runner over any package-manager workspace. It owns the graph and cache, not the install.

```jsonc
// turbo.json
{
  "$schema": "https://turbo.build/schema.json",
  "globalDependencies": ["tsconfig.base.json"],
  "globalEnv": ["CI"],
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "inputs": ["$TURBO_DEFAULT$", "!**/*.md"],
      "outputs": ["dist/**", ".next/**", "!.next/cache/**"],
      "env": ["NEXT_PUBLIC_*"]
    },
    "test": { "dependsOn": ["build"], "outputs": [], "cache": false },
    "lint": { "cache": true },
    "dev": { "cache": false, "persistent": true }
  }
}
```

Operational notes:

- `dependsOn: ["^build"]` means "build dependencies first"; `["build"]` means "my own build first". Confusing these is the most common configuration bug.
- `outputs` drives cache restoration; an empty `outputs` means nothing is restored, which is correct only for tasks with no artifacts.
- `--affected` (with `TURBO_SCM_BASE`/`TURBO_SCM_HEAD`) or `--filter` selects the work set; both depend on sufficient git history.
- Remote cache runs on Vercel infrastructure or self-hosted; use `signature: true` so cache artifacts are signed and untrusted writers cannot poison consumers. Verify the current hosting and pricing model upstream.
- `turbo prune <pkg> --docker` produces a minimal workspace for container builds.
- `turbo boundaries` (tag rules in `turbo.json`) can fail builds on undeclared cross-package imports; use it together with lint rules from [02-structure-boundaries](./02-structure-boundaries.md).

Best fit: JS/TS product monorepos, frontend-heavy teams, teams that want a small config surface and remote cache without adopting a framework.

## 5. Nx

A batteries-included system: project graph, task runner, generators, plugins, module-boundary lint rules, and release tooling.

```jsonc
// nx.json
{
  "targetDefaults": {
    "build": { "dependsOn": ["^build"], "cache": true, "inputs": ["production", "^production"] },
    "test": { "cache": true, "inputs": ["default", "^production"] }
  },
  "namedInputs": {
    "default": ["{projectRoot}/**/*", "sharedGlobals"],
    "production": ["default", "!{projectRoot}/**/*.spec.ts"],
    "sharedGlobals": ["{workspaceRoot}/tsconfig.base.json"]
  }
}
```

```jsonc
// packages/ui/project.json (or inferred from package.json)
{
  "name": "ui",
  "tags": ["scope:shared", "type:ui"],
  "targets": {
    "build": { "executor": "@nx/js:tsc", "outputs": ["{options.outputPath}"] }
  }
}
```

Operational notes:

- Plugins infer targets from existing tool config (`@nx/vite`, `@nx/webpack`, `@nx/eslint`), so the repo keeps standard files; pin plugin versions to the Nx major.
- `nx affected -t build test --base=origin/main --head=HEAD` is the standard PR command; `--parallel` and `--maxParallel` control workers.
- `nx graph` is the most valuable feature in practice: a visual, queryable dependency graph that shortens architecture reviews.
- `nx release` supports versioning and publishing with conventional commits or changesets; adopt it only if you are not already committed to Changesets. See [07-versioning-release](./07-versioning-release.md).
- Nx Cloud provides remote cache, distributed task execution, and analytics. Self-hosted caching exists but is less capable than the cloud product; verify features and pricing upstream.

Best fit: large JS/TS repos with many package types, teams that value generators and code organization rules, full-stack repos (React, Node, mobile), and organizations that want release tooling included.

Trade-offs: more concepts and configuration, faster release cadence, and plugin lockstep upgrades. A small repo pays overhead for capabilities it will not use.

## 6. Bazel

The reference implementation of hermetic, correct, distributed builds. Everything is an action with declared inputs and outputs; the cache is content-addressed and correct by construction when rules are hermetic.

Strengths:

- Polyglot with one graph: JS/TS (`rules_js`, `rules_ts`), Go, Python, Rust, Java, C++, protobuf.
- Remote execution across a farm of workers; remote cache is part of the protocol.
- Correct incremental and affected behavior at a scale no JS tool matches.
- Strong supply-chain story: pinned module versions (`MODULE.bazel.lock`), vendored dependencies, reproducible toolchains.

Costs:

- Starlark `BUILD`/`MODULE` files, toolchains, and rules to learn; every language needs rule maintenance.
- Debugging is its own discipline; error messages are opaque until experience builds.
- Developers need `bazel` semantics (sandboxing, visibility, `--config`) that other tools hide.
- Migration of an existing JS repo is measured in quarters, not sprints.

Best fit: large polyglot organizations, monorepos with millions of lines, regulated environments requiring reproducible builds, and repos already feeling hermeticity pain. For a JS-only repo of moderate size, Bazel is almost always the wrong cost/benefit. See [08-migration](./08-migration.md) before committing.

## 7. Moon

A Rust task runner with an integrated toolchain manager (`proto`) and polyglot-first design.

```yaml
# moon.yml (project-level)
language: typescript
tasks:
  build:
    command: tsc -b
    inputs: ["src/**/*", "tsconfig.json"]
    outputs: ["dist"]
  test:
    command: vitest run
    deps: ["~:build"]
```

Strengths: one config style across languages, file groups and task inheritance (`.moon/tasks/*.yml`), affected detection, local/remote caching, and toolchain pinning without Bazel's Starlark burden.

Weaknesses: smaller ecosystem and community than Nx/Turborepo; fewer ready-made plugins; you may write more custom task wiring.

Best fit: polyglot repos (TS + Go + Python + Rust) where Bazel is too heavy and Turborepo does not cover non-JS tasks; teams wanting reproducible toolchains.

## 8. Make

GNU Make remains the lowest-common-denominator runner and a reasonable choice for C/C++/embedded or legacy repos, or as a thin front door (`make ci`) that delegates to a real runner.

```make
PNPM_PKGS := $(wildcard packages/*)

.PHONY: install build test changed clean
install:
	pnpm install --frozen-lockfile

build: install
	pnpm -r --filter './packages/**' build

changed: install
	pnpm -r --filter '...[origin/main]' test

clean:
	rm -rf packages/*/dist
```

Known limits and pitfalls:

- Timestamp-based incrementality is not content-based; `git checkout` can lie.
- No affected detection and no remote cache; you rebuild or script your own.
- `.PHONY` is required for non-file targets; forgetting it causes "nothing to be done".
- Recursive `$(MAKE)` breaks `-j` correctness unless order-only prerequisites are declared:
  `packages/%: | node_modules` style rules help, but the graph stays manual.
- Shell portability (tabs, `SHELL`, `set -e`) is a recurring source of CI-only failures.

Use Make as glue, not as the monorepo engine, unless the domain is genuinely non-JS and simple. `just` is a friendlier command runner for the glue role; verify its current support surface upstream.

## 9. Adjacent tools worth knowing

| Tool | What it is | Consider when |
| --- | --- | --- |
| Rush | Microsoft's pnpm-based workspace manager with change files | enterprise JS repos needing strict policies |
| Lerna | legacy publish tool, now a thin layer over Nx/Turbo | only maintaining an existing Lerna repo |
| Lage | Microsoft task runner, `lage` pipeline config | small TS repos wanting a light runner |
| Wireit | npm-scripts enhancement with caching and dependencies | avoiding a new runner for small repos |
| Pants / Buck2 | polyglot build systems, Bazel-adjacent | teams that want Bazel semantics with different ergonomics |
| just / go-task | command runners, no graph | developer entrypoints and local glue |

Verify maintenance status and feature parity upstream before betting on any of these; the build-tool market consolidates and shifts quickly.

## 10. Migration cost

| From -> To | Effort | Risk | Notes |
| --- | --- | --- | --- |
| pnpm workspaces -> Turborepo | days | low | add `turbo.json`, keep scripts; adopt `--affected` |
| pnpm workspaces -> Nx | days to weeks | low-medium | graph inference works with existing configs; tags require decisions |
| Turborepo -> Nx | weeks | medium | target/input model differs; cache and CI must be re-validated |
| Nx -> Turborepo | weeks | medium | lose generators/graph UI unless replaced by scripts |
| any JS runner -> Bazel | months | high | full rules/toolchain investment; run a pilot first |
| Make -> any runner | weeks | medium | scripts and implicit ordering must be made explicit |
| Turborepo/Nx -> Moon | weeks | medium | rewrite task definitions; polyglot gains must justify it |

Rules for any migration:

1. Never migrate tooling and repository structure in the same change window.
2. Keep a green main branch: migrate one concern at a time, behind config flags where possible.
3. Measure before and after with the same metrics (CI wall time, cache hit rate, install time). See [09-governance-metrics](./09-governance-metrics.md).
4. Budget for CI rework; caching correctness is the hard part, not config translation.

## 11. Decision table by scenario

| Scenario | Recommendation | Why |
| --- | --- | --- |
| 2-10 JS packages, fast CI | pnpm workspaces only | no runner tax; revisit at ~10 packages |
| 10-100 JS/TS packages, frontend-heavy | Turborepo + pnpm | small config, strong cache, easy adoption |
| 20-500 JS/TS projects, many types, releases | Nx + pnpm | generators, graph, boundary rules, release tooling |
| Polyglot, no desire for Starlark | Moon | one task model across languages, toolchain pinning |
| Polyglot at scale, hermetic/reproducible required | Bazel | correctness and remote execution |
| C/C++/embedded or legacy scripts | Make, modernized | minimal disruption |
| Publishing libraries only | pnpm workspaces + Changesets | release flow is the whole job; no runner needed |

## 12. Anti-patterns

- Choosing a tool by benchmark blog post instead of a two-week pilot on the real repo.
- Running two runners in the same repo without a clear ownership split.
- Replacing the package manager and the runner simultaneously.
- Caching by filename alone; ignoring env, lockfile, and tool versions. See [05-caching-ci](./05-caching-ci.md).
- Adopting Bazel for a 20-package JS repo "for the future".
- Defining targets only in CI YAML; they belong in the repo config so everyone gets them.
- Treating `pnpm -r` as a task graph: it runs in topological order but caches nothing.
- Letting plugin versions drift across Nx packages, causing graph inference failures.

## Checklist

- [ ] The runner was chosen against the seven capabilities, with a pilot and measured results.
- [ ] One package manager, one lockfile, pinned `packageManager`, frozen CI installs.
- [ ] Task graph declared in-repo (turbo.json, nx.json, moon.yml, BUILD files), not only in CI.
- [ ] Each cacheable task declares inputs, outputs, env, and cache policy.
- [ ] Affected detection uses an explicit merge base and full-enough git history.
- [ ] Remote cache credentials are scoped; signatures or trust boundaries considered.
- [ ] Migration sequence documented, reversible, and separated from structural changes.
- [ ] Escape hatches known: `--force`, cache bypass, graph inspection commands.

Related: [02-structure-boundaries](./02-structure-boundaries.md) for tags and boundary rules, [05-caching-ci](./05-caching-ci.md) for hashing and remote cache operations, [08-migration](./08-migration.md) for execution plans.
