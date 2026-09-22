---
name: senior-monorepo
description: 'Monorepo reference pack (2026): tool selection across Nx, Turborepo,
  pnpm workspaces, Bazel, Moon, and Make; layout plus enforced dependency boundaries;
  workspace protocols, catalogs, peer dependencies, hoisting, and dedupe; shared tsconfig,
  ESLint, and Prettier packages; task graphs, affected detection, remote caching,
  CI sharding, and merge queues; workspace generators plus API and schema codegen;
  Changesets, fixed vs independent versioning, release trains, and publishing; polyrepo-to-monorepo
  migration; CODEOWNERS, drift detection, and monorepo health metrics. Use when creating,
  migrating, reviewing, or operating a monorepo: choosing or replacing a task runner,
  fixing slow or flaky CI, defining package boundaries and ownership, deduplicating
  dependencies, wiring shared configuration, automating releases, or auditing monorepo
  health. Depth lives in references/, one topic per file.'
---

# Monorepo

A monorepo is one repository holding multiple deployable or publishable units that share a dependency graph, a toolchain, and a single change set. It buys atomic cross-package changes, consistent versions, one CI story, and cheap code reuse. It costs investment in task orchestration, caching, boundary enforcement, and governance. A monorepo is not a folder layout; it is an operating model.

This pack is an entrypoint plus nine deep references. Read the core rules first; they encode defaults that rarely deserve debate. Then load only the references the task needs. Each reference starts with a one-line scope and carries version floors, decision tables, minimal runnable snippets, anti-patterns, and checklists.

Content targets the stable ecosystem of 2026: Nx 20+/21+, Turborepo 2.x, pnpm 9/10+, Bazel 7/8 with Bzlmod, Moon 1.x, GNU Make 4.3+, Changesets, and current CI platforms (GitHub Actions, GitLab CI). Versions move monthly: treat stated numbers as floors, pin what you use, and verify upstream before quoting numbers in deliverables.

## Non-negotiable core rules

1. One package manager, one lockfile, one Node/toolchain version per repository. `packageManager` is pinned in the root manifest; CI installs frozen (`pnpm install --frozen-lockfile`, `npm ci`). See [03-dependencies](./references/03-dependencies.md).
2. Internal dependencies use the workspace protocol (`workspace:*`), never `file:` paths or published ranges against in-repo packages. See [03-dependencies](./references/03-dependencies.md).
3. Boundaries are declared and machine-enforced. Default direction: `types -> utils -> data-access -> feature -> app`. Violations fail lint, not review. See [02-structure-boundaries](./references/02-structure-boundaries.md).
4. Every package exposes an explicit public API through `exports` and an entrypoint; deep imports into another package's `src/` are banned. See [02-structure-boundaries](./references/02-structure-boundaries.md) and [04-shared-config](./references/04-shared-config.md).
5. Shared configuration lives in versioned packages (`@acme/tsconfig`, `@acme/eslint-config`), not in copy-pasted root files or per-package drift. See [04-shared-config](./references/04-shared-config.md).
6. Every cacheable task declares inputs, outputs, and environment. A missing input or env var silently poisons the remote cache for everyone. See [05-caching-ci](./references/05-caching-ci.md).
7. Pull requests run affected-only; the default branch runs the full graph. Shallow clones break affected detection, so CI must fetch enough history. See [05-caching-ci](./references/05-caching-ci.md).
8. Remote cache is trusted infrastructure: scoped credentials, no secrets in artifacts, cache writes restricted to trusted branches, poisoning treated as an incident. See [05-caching-ci](./references/05-caching-ci.md).
9. Generated code is reproducible and never hand-edited: pinned generator versions, committed output or a CI drift check, explicit `DO NOT EDIT` headers. See [06-codegen](./references/06-codegen.md).
10. The version policy is explicit and documented per group: fixed, linked, or independent. Internal-only packages are `private` and excluded from release automation. See [07-versioning-release](./references/07-versioning-release.md).
11. Publishing is automated with provenance, from a clean CI checkout, never by hand and never from a dirty tree. See [07-versioning-release](./references/07-versioning-release.md).
12. Every package has an owner in `CODEOWNERS` (or the platform equivalent), including generated and tooling packages. Ownership coverage is measured, not assumed. See [09-governance-metrics](./references/09-governance-metrics.md).
13. Drift is detected mechanically: version skew, config divergence, unowned projects, and undeclared dependencies all have checks. See [09-governance-metrics](./references/09-governance-metrics.md).
14. CI time, cache hit rate, and flake rate are tracked budgets. Unchecked growth is a defect, not a fact of life. See [05-caching-ci](./references/05-caching-ci.md) and [09-governance-metrics](./references/09-governance-metrics.md).

## Decision tables

### Task runner and workspace tool

| Situation | Default | Alternative |
| --- | --- | --- |
| JS/TS app monorepo, frontend-heavy, remote cache wanted | Turborepo + pnpm workspaces | Nx |
| Large JS/TS repo, generators, plugins, project graph UI, release tooling | Nx | Turborepo |
| Polyglot (TS, Go, Python, Rust) with hermetic, distributed builds | Bazel (Bzlmod) | Moon, Pants |
| Polyglot repo, small platform team, wants toolchain management | Moon | Nx with plugins |
| Library publishing workspace only | pnpm workspaces (+ Changesets) | npm/Yarn workspaces |
| Make-based legacy or C/C++ embedded repo | GNU Make, modernized | Bazel, Meson |

### Repository layout

| Need | Place | Notes |
| --- | --- | --- |
| Deployable units | `apps/<name>` | thin; wired from libs |
| Publishable libraries | `packages/<name>` | public API + build output |
| Non-published shared code | `libs/<scope>/<name>` or `packages/` | keep taxonomy consistent |
| Tooling, generators, scripts | `tools/` | owned by platform team |
| Cross-cutting docs and ADRs | `docs/` | architecture decisions with dates |

### Internal dependency contract

| Consumer | Dependency type | Version spec |
| --- | --- | --- |
| App consumes internal lib | `dependencies` | `workspace:*` |
| Lib consumes lib at runtime | `dependencies` | `workspace:^` |
| Singleton runtime (React, ORM client) | `peerDependencies` | range covering supported majors |
| Type-only dependency | `devDependencies` or `peerDependenciesMeta.optional` | avoid runtime coupling |
| One-off CLI or generator | `devDependencies` | pin exactly |

### Versioning and release

| Situation | Policy |
| --- | --- |
| Packages released together as one product | fixed group (single version) |
| Interdependent packages that must not diverge far | linked group |
| Independent libraries with separate audiences | independent |
| Internal apps and config-only packages | `private`, ignored by release tooling |
| Public API changes | semver major, changeset required in PR |

### CI caching

| Concern | Practice |
| --- | --- |
| Compute tasks | local cache plus remote cache keyed on inputs |
| PR scope | affected-only with merge-base diff |
| Hot path | shard test suites by historical duration |
| Correctness | full graph on default branch, no cache exemption |
| Debugging | `--force`, `--summarize`, verbose hash inspection |

## Load strategy

- Start with the index below; load at most two references per task. The core rules already cover most reviews.
- Pair one structural reference ([02-structure-boundaries](./references/02-structure-boundaries.md) or [03-dependencies](./references/03-dependencies.md)) with one operational reference ([05-caching-ci](./references/05-caching-ci.md) or [07-versioning-release](./references/07-versioning-release.md)) when a task spans design and delivery.
- [08-migration](./references/08-migration.md) and [09-governance-metrics](./references/09-governance-metrics.md) are the strategic passes; load them for whole-repo audits, reorganizations, and platform planning.
- When tool behavior differs from this pack, the installed tool version wins; verify upstream and prefer the pinned configuration in the repository.

## Reference index

| File | Scope | Load when |
| --- | --- | --- |
| [01-tools.md](./references/01-tools.md) | Nx vs Turborepo vs pnpm workspaces vs Bazel vs Moon vs Make: capabilities, fit, migration cost, decision table | Choosing or replacing the task runner, or justifying the current one |
| [02-structure-boundaries.md](./references/02-structure-boundaries.md) | apps/packages/libs layout, package taxonomy, ownership, dependency direction, public APIs, enforcement tooling | Designing a repo layout or fixing boundary violations |
| [03-dependencies.md](./references/03-dependencies.md) | Workspace protocols, catalogs, peer deps, hoisting, dedupe, overrides, version policy, update automation | Adding dependencies, resolving version conflicts, or automating upgrades |
| [04-shared-config.md](./references/04-shared-config.md) | Shared tsconfig/ESLint/Prettier/test config packages, project references, internal package consumption, build outputs and exports | Setting up shared config or wiring internal package builds |
| [05-caching-ci.md](./references/05-caching-ci.md) | Task graphs, hashing, local/remote caching, affected detection, CI sharding, merge queues, flaky task isolation | Making CI fast, correct, and flake-resistant |
| [06-codegen.md](./references/06-codegen.md) | Workspace generators, schema-to-types pipelines, protobuf/OpenAPI codegen, generated-code consistency and drift checks | Adding code generation or fixing generated-code drift |
| [07-versioning-release.md](./references/07-versioning-release.md) | Changesets, fixed vs linked vs independent versioning, release trains, canary/snapshot, publishing, changelogs | Designing release flow or publishing packages |
| [08-migration.md](./references/08-migration.md) | Polyrepo to monorepo, incremental adoption, hybrid strategies, history preservation, common failure modes | Planning or executing a consolidation or split |
| [09-governance-metrics.md](./references/09-governance-metrics.md) | CODEOWNERS, drift detection, healthy-monorepo metrics, budgets, documentation, platform team model | Auditing health, assigning ownership, or setting SLOs |

## Port

- **Port id** — `skill://senior/monorepo` (version in `metadata.port-version`).
- **Kind** — read-only reference pack; no side effects, no tools required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "monorepo" })` in OpenCode; Claude Code reads `<skills-dir>/monorepo/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers reference it as `load skill senior-monorepo (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major.
