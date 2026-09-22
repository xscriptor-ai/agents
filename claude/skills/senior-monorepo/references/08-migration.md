# Migration to a Monorepo

> Scope: polyrepo consolidation, incremental adoption, history preservation, hybrid strategies, and common failure modes.

Migration is an engineering project with a deadline, a pilot, and a rollback plan. Most failures come from treating it as a `git mv` exercise.

## 1. Decide whether to migrate

| Signal for merging | Signal against merging |
| --- | --- |
| Frequent cross-repo changes with coordinated releases | Teams ship independently with different cadences |
| Dependency version skew between repos | Strong isolation/security boundaries between products |
| Duplicated config, CI, and tooling maintenance | Repos with genuinely different toolchains and no shared code |
| Reuse is blocked by publishing overhead | Repo size or clone time already painful |
| Review/ownership friction from scattered PRs | Regulatory requirement for physical separation |
| You want one dependency graph and one CI story | No platform capacity to operate shared infrastructure |

Quantify before deciding: number of cross-repo PRs per month, duplicated tool versions, average integration delay, and CI cost per repo. If cross-repo work is rare, a monorepo buys complexity you will not use.

## 2. Phase 0: baseline

- Inventory repositories: languages, package managers, Node/toolchain versions, CI systems, release flows, test strategies, secrets, and deploy targets.
- Build a dependency map: which repo consumes which, through what artifact (npm package, container, OpenAPI client, git submodule).
- Measure current pain: build times, integration failures, dependency skew, onboarding time.
- Choose the target: layout ([02-structure-boundaries](./02-structure-boundaries.md)), runner ([01-tools](./01-tools.md)), release policy ([07-versioning-release](./07-versioning-release.md)).
- Decide the source-of-truth model: monorepo primary, mirrors read-only; or hybrid during transition.
- Agree on success criteria and a deadline; without them, migration becomes permanent scaffolding.

## 3. Import patterns

| Pattern | Mechanics | Pros | Cons |
| --- | --- | --- | --- |
| Merge into an existing repo | add imported repo as a directory, preserve history where possible | one landing zone, incremental | root configs must absorb new toolchains |
| Fresh monorepo, import projects | create new repo, import each project | clean history and configs | coordination cost; two repos during transition |
| History-preserving import | `git filter-repo` or `git subtree add` | blame and bisect survive | merge conflicts if the source repo stays active |
| History-squash import | copy files, one "import" commit | simple, small repo | lose blame; archaeology breaks |
| Submodule/vendor | keep repos, reference them | no migration | not a monorepo; boundary stays hard |

History-preserving import with `git filter-repo` (verify current syntax upstream):

```bash
# In a clone of the source repo, rewrite to a subdirectory, then fetch into the monorepo.
git filter-repo --to-subdirectory-filter packages/billing
# In the monorepo:
git remote add billing /path/to/rewritten
git fetch billing
git merge --allow-unrelated-histories billing/main
```

Rules:

- Freeze writes to the source repo during the import, or you will reconcile twice.
- Tag the source repo at the import commit so future archaeology has an anchor.
- Do not mix structural moves and content changes in one commit; the diff should read as a move.
- Record the import mapping (old repo/path -> new path) in `docs/` for one year minimum.

## 4. Incremental adoption and hybrid strategies

You do not need a big-bang cutover.

1. **Tooling first** — bring the target package manager, config package, and task runner into the monorepo with a single pilot project.
2. **Shared libraries first** — import low-risk libraries that multiple teams already copy or publish. They create the first internal dependency edges and prove the workspace protocol.
3. **One app at a time** — import apps behind their existing pipelines; keep their build and deploy mostly intact, then migrate to the monorepo task graph.
4. **Decommission last** — turn off old repositories only after the monorepo pipeline has been green for a full release cycle.

Hybrid patterns during transition:

| Pattern | Description | Exit condition |
| --- | --- | --- |
| Source of truth split by domain | monorepo owns libs, polyrepo owns one app | app imported |
| Read-only mirror | CI publishes snapshots from monorepo to old repos/packages | consumers migrated |
| Publish-and-consume bridge | monorepo publishes internal packages; old repos consume them as versions | old repos imported |
| Reverse migration | extract a package back out when isolation is required | enforced boundary, separate CI |

Keep the number of transitional states small and time-boxed. Every hybrid adds a synchronization loop someone must own.

## 5. Sequencing a single repo import

1. Create the target directory with a placeholder README and CODEOWNERS entry.
2. Copy the source files without build outputs, lockfiles, or CI secrets.
3. Add workspace membership (glob already covers the path) and internal dependency rewrites (`file:`/relative -> `workspace:`).
4. Unify toolchain: one Node version, one TypeScript version, shared configs.
5. Make the package build, lint, typecheck, and test under the monorepo graph.
6. Simplify CI: delete the old workflow once the monorepo pipeline covers the package.
7. Add ownership, docs, and a smoke test of the deployed artifact.
8. Announce the freeze of the old repo; archive it (do not delete) after the first successful release.

Checkpoint after each import: main is green, CI time is within budget, and no cross-package deep imports were introduced.

## 6. Migrating dependencies and tooling

- Replace `file:` and relative links with `workspace:` protocol; see [03-dependencies](./03-dependencies.md).
- Consolidate lockfiles; expect one large dependency resolution event. Dedupe before merging so the diff is readable.
- Move shared configs into config packages ([04-shared-config](./04-shared-config.md)) before mass-migrating packages; otherwise you copy divergent configs.
- Align test frameworks and versions in the same pass; mixed runners multiply CI complexity.
- Rebuild CI as a graph pipeline, not a concatenation of the old workflows ([05-caching-ci](./05-caching-ci.md)).
- Keep one temporary escape hatch: a package that cannot yet run under the shared toolchain gets an explicit exemption with an expiry date.

## 7. Common failure modes

| Failure | Symptom | Prevention |
| --- | --- | --- |
| CI time explosion | PR feedback goes from minutes to an hour | affected detection, caching, sharding before import |
| Boundary collapse | everything imports everything within weeks | tags and lint rules from day one ([02-structure-boundaries](./02-structure-boundaries.md)) |
| Ownership vacuum | no one reviews cross-cutting changes | CODEOWNERS per package before import; platform team for tooling |
| Lockfile conflicts | constant resolution churn | small PRs, dedupe, schedule dependency work |
| Tool drift | each package pins different versions | shared config packages, single toolchain version |
| Platform bottleneck | one team approves every structural change | empower package owners; platform owns the system, not the code |
| Lost release independence | everything must release together | explicit version policy, independent groups where needed |
| Big-bang migration | months of shadow work, no value delivered | pilot first, incremental imports, measure each phase |
| Irreversible move | cannot extract a package later | keep package APIs clean and dependencies declared so extraction stays possible |
| History loss | blame/bisect unusable | history-preserving import or documented squash decision |

## 8. Rollback and exit strategy

- A package extraction plan is mandatory: clean `exports`, declared dependencies, no repo-internal absolute paths, and a build that produces a publishable artifact. Any package that meets these can be extracted in days.
- Keep CI for the old repo until the new pipeline has run a full release cycle.
- If the migration stalls, stop importing and stabilize what was imported. A half-migrated repo with broken ownership is worse than two polyrepos.
- Document the decision to stay hybrid, including the owner and review date.

## 9. Post-migration hardening

- Add drift checks (version skew, config divergence, orphaned packages) from [09-governance-metrics](./09-governance-metrics.md).
- Set and enforce CI budgets; measure the first month and publish the numbers.
- Onboard every team with a walkthrough of the graph, release flow, and ownership model.
- Run a retro at 30 and 90 days: what got faster, what got slower, what tooling needs another pass.
- Archive old repositories with a pointer README to the new location.

## 10. Anti-patterns

- Migrating all repositories at once without a pilot.
- Moving code while also rewriting it; do one or the other.
- Importing build outputs, `node_modules`, or `.env` files.
- Keeping old CI workflows alive "just in case" for months.
- No CODEOWNERS entry for imported packages.
- Copying package lockfiles into the monorepo.
- Using `file:` links as a permanent bridge, breaking dedupe and publish.
- Declaring victory before the first deploy/release from the monorepo.

## Checklist

- [ ] Decision documented with quantified signals for and against migration.
- [ ] Baseline inventory and dependency map exist.
- [ ] Target layout, runner, and release policy chosen before importing.
- [ ] Pilot project imported and measured before broad migration.
- [ ] History strategy chosen (preserve or documented squash).
- [ ] Workspace protocol replaces all cross-repo links.
- [ ] CODEOWNERS, shared config, and CI graph cover every imported package.
- [ ] Rollback/extraction path tested at least once.
- [ ] Old repositories archived with pointers after one green release cycle.

Related: [01-tools](./01-tools.md) for runner choices, [02-structure-boundaries](./02-structure-boundaries.md) for the target layout, [05-caching-ci](./05-caching-ci.md) for CI rework.
