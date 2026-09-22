# Caching and CI

> Scope: task graphs, input hashing, local and remote caching, affected detection, CI sharding, merge queues, and flaky-task isolation.

CI is the monorepo's user interface. If it is slow, incorrect, or flaky, every other investment is taxed. Caching is a correctness problem before it is a speed problem: a wrong cache is worse than no cache.

## 1. Declare the task graph

The graph lives in the repository, not in CI YAML, so local and CI runs behave identically.

Turborepo:

```jsonc
// turbo.json
{
  "globalDependencies": ["tsconfig.base.json", "pnpm-lock.yaml", ".node-version"],
  "globalEnv": ["CI", "NODE_ENV"],
  "tasks": {
    "build": { "dependsOn": ["^build"], "outputs": ["dist/**", ".next/**", "!.next/cache/**"] },
    "typecheck": { "dependsOn": ["^build"], "outputs": [] },
    "test": { "dependsOn": ["build"], "outputs": ["coverage/**"] },
    "e2e": { "dependsOn": ["build"], "cache": false, "outputs": [] },
    "lint": { "outputs": [] },
    "dev": { "cache": false, "persistent": true }
  }
}
```

Nx:

```jsonc
// nx.json
{
  "targetDefaults": {
    "build": { "dependsOn": ["^build"], "cache": true, "inputs": ["production", "^production"], "outputs": ["{projectRoot}/dist"] },
    "test": { "dependsOn": ["build"], "cache": true, "inputs": ["default", "^production"] },
    "e2e": { "cache": false }
  },
  "namedInputs": {
    "default": ["{projectRoot}/**/*", "sharedGlobals"],
    "production": ["default", "!{projectRoot}/**/*.spec.ts", "!{projectRoot}/**/*.md"],
    "sharedGlobals": ["{workspaceRoot}/tsconfig.base.json", "{workspaceRoot}/tools/**"]
  }
}
```

Rules:

- `^build` means dependencies first; `build` means this project first. Reviewers should check this distinction in every config change.
- Every task that produces files declares `outputs`; every task that consumes env declares it. Empty outputs with caching on is a common silent bug.
- `persistent` tasks (dev servers, watchers) are never cached and must not block the graph.
- Global dependencies are the narrow set of root files that genuinely affect every package (base config, lockfile, toolchain pin).

## 2. How hashing works

A task's cache key is roughly:

```
hash( task name + command + package source globs + dependency task hashes + lockfile slice + declared env + tool versions )
```

Consequences:

- The same source with a different env value is a different key. Missing env declarations cause both false misses (rebuild) and false hits (wrong artifact).
- Changing a dependency's source changes the dependent's key through `^build` hashes; this is why graph correctness matters.
- Changing the lockfile usually changes every key; that is intentional.
- Hidden inputs (generated files not declared, files outside the package root, absolute paths, timestamps) break determinism. Hunt them when cache hits look random.
- Debug with `turbo run build --summarize` (or `.turbo/runs/*.json`) and `nx run build --verbose` / `NX_VERBOSE_LOGGING=true` to inspect the computed hash inputs.

Never include:

- Timestamps, hostnames, absolute paths, or random values in build outputs.
- Credentials or `.env` contents in hashed outputs or uploaded artifacts.
- `node_modules` wholesale; hash the lockfile and package manifests instead.

## 3. Local cache

- Turborepo: `.turbo/cache` (gitignored); Nx: `.nx/cache`.
- Local misses on a clean checkout are expected; local hits make developer loops fast and reduce CI cost indirectly by enabling local reproduction of CI failures.
- Keep the cache directory out of version control and out of build outputs. A cache directory that is itself an output creates recursive invalidation.
- Bound cache size: prune stale entries (`turbo prune` for deploys; cache eviction is automatic but disk pressure is real on dev machines).

## 4. Remote cache

| Option | Notes |
| --- | --- |
| Nx Cloud | remote cache + distributed task execution + analytics; hosted or self-hosted; verify current plans upstream |
| Vercel Remote Cache | native to Turborepo; hosted or self-hosted (`turbo login`/`turbo link`); verify current terms and limits upstream |
| Self-hosted S3/GCS/R2 | implement or use the runner's artifact API; full control, you own auth, retention, and correctness |
| CI-native cache (GitHub Actions) | useful for package-manager stores and tool caches, not a substitute for task-artifact caching |

Operations:

1. Scope credentials per repository; read-only for pull requests from forks where possible.
2. Sign cache artifacts (`signature: true` in Turborepo) so consumers can verify provenance. Without trust boundaries, anyone who can write can poison what everyone runs.
3. Separate PR and main caches if correctness risk is unacceptable (for example, do not let unmerged branches write to the shared cache).
4. Monitor hit rate and artifact size; unbounded artifacts (full `.next` directories, VM images) make the cache slow and expensive.
5. Treat a cache-poisoning report as a security incident: purge affected keys, rotate tokens, audit writers.

## 5. Affected detection

- Compute the diff against the merge base, not against the previous commit on the branch.
- Turborepo: `turbo run build --affected` with `TURBO_SCM_BASE`/`TURBO_SCM_HEAD`, or `--filter='...[origin/main]'`.
- Nx: `nx affected -t build test --base=origin/main --head=HEAD`.
- CI must fetch enough history: `actions/checkout` with `fetch-depth: 0` (or fetch the base branch explicitly). A shallow clone makes every PR look like a full rebuild or, worse, a partial one.
- Always run the full graph on the default branch; affected-only on merges hides integration failures.
- Tooling changes (`tools/`, root configs, CI files) usually affect everything; declare them as global inputs rather than special-casing in CI.
- Path-based filters (`--filter=./apps/web`) are for explicit routing, not for correctness; use them only when the task truly is app-local.

## 6. A reference PR pipeline

```yaml
name: ci
on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  verify:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@<pinned-sha>
        with: { fetch-depth: 0 }
      - uses: pnpm/action-setup@<pinned-sha>
      - uses: actions/setup-node@<pinned-sha>
        with: { node-version-file: .nvmrc, cache: pnpm }
      - run: pnpm install --frozen-lockfile
      - name: Lint and types
        run: pnpm exec turbo run lint typecheck --affected
      - name: Build and test
        run: pnpm exec turbo run build test --affected --concurrency=50%
      - name: Full verification on main
        if: github.ref == 'refs/heads/main'
        run: pnpm exec turbo run build test --force
```

Notes:

- Pin actions by SHA; tags move.
- Cancel superseded runs; a monorepo queue is the top cause of slow feedback.
- Keep job count small and parallelize inside the runner. Splitting into many jobs multiplies install cost unless the runner's remote cache handles it.
- Gate merges on the full-graph main run, not only the affected PR run.

## 7. Sharding and parallelism

| Technique | How | Watch out |
| --- | --- | --- |
| Package sharding | matrix over `pnpm list --depth -1` or `nx show projects` filtered to changed | install repeated per shard; use store cache |
| Test-file sharding | `vitest --shard=i/n`, `jest --shard=i/n`, `playwright test --shard=i/n` | keep shards balanced by historical duration, not file count |
| Task-level concurrency | `turbo --concurrency`, `nx --parallel` | oversubscription on small runners causes timeouts |
| Graph-partitioned CI | assign packages to runners by graph clusters | complex; only worth it at large scale |
| Split setup | prebuild common deps in a "prepare" job, then fan out | artifacts must be addressable and cache-correct |

Balance shards with recorded durations; naive round-robin assignment drifts to a slow tail. Re-measure weekly or on graph changes.

## 8. Merge queues

- GitHub merge queue and GitLab merge trains test the merge result, not just the branch, preventing semantic conflicts between green PRs.
- Queue runs use a synthetic merge commit; cache keys change, so expect lower hit rates for the tested commit. Cache by source hashes, not commit hashes, to keep reuse.
- Keep the merge-queue job set minimal and fast: lint, types, build, targeted tests. Long e2e suites belong on main or nightly.
- Required checks must be identical in name across PR and queue contexts, or the queue stalls silently.
- Configure batching where available; batching reduces queue drain time but widens the blast radius of a failure.

## 9. Flaky tasks

Flakes destroy trust in the cache and in CI generally. Treat them as defects with owners.

- Record which tasks fail and retry; a task that needs retries to pass is flaky even when green.
- Isolate flaky tests (`test.fixme`, quarantine tag) into a dedicated, allowed-to-fail job while they are fixed; never leave them retrying silently in the main pipeline.
- Common monorepo causes: shared ports, shared databases, time-dependent tests, unbounded parallelism, missing env in tests that assume CI defaults, and cache hits that restore stale outputs into tests.
- For e2e: retry only to collect artifacts, then fail on retry (`--retries=1` to get traces; do not pass a flake as success).
- Track flake rate as a metric; see [09-governance-metrics](./09-governance-metrics.md).
- `--continue`/`continueOnError` keeps the pipeline informative (other tasks still run) but must not hide failures from the final status.

## 10. Cache correctness traps

| Trap | Effect | Detection |
| --- | --- | --- |
| Env var missing from `env` | wrong artifact reused | grep config for `process.env` in build scripts |
| File outside declared inputs | stale build | reproduce with `--force`, compare hashes |
| Output not declared | work redone, or missing artifact in CI | check cache restore logs |
| Non-deterministic output (timestamps, paths) | cache never hits | build twice, diff outputs |
| Postinstall mutation of source | key unchanged, output changed | forbid source mutation in scripts |
| Unsigned remote cache | poisoning risk | enable signatures, scope tokens |
| Tests with external side effects cached | skipped tests, false green | `cache: false` for e2e/integration |

## 11. Metrics to expose

- Install time, full build time, affected build time (p50/p95).
- Local and remote cache hit rates per task (not just aggregate).
- Queue time and CI wall time per PR.
- Flake rate and retry count per task.
- Affected ratio (how much of the graph a typical PR touches).

See [09-governance-metrics](./09-governance-metrics.md) for targets and dashboards.

## 12. Anti-patterns

- Caching everything including e2e and deploy steps.
- Copying CI YAML between repos instead of declaring tasks in-repo.
- `fetch-depth: 1` with affected detection.
- Running the full graph for every PR "to be safe"; it trains the team to ignore CI cost.
- Long-lived caches without eviction or size limits.
- Retrying flaky jobs until green; the failure is the signal.
- One mega-job with no parallelism, or 40 jobs with duplicated installs.
- Treating remote cache as free infrastructure with no ownership.

## Checklist

- [ ] Task graph declared in-repo with inputs, outputs, env, and cache policy.
- [ ] Affected detection uses merge base and full-enough git history.
- [ ] Remote cache configured, scoped, monitored, and (where supported) signed.
- [ ] Default branch runs the full graph; PRs run affected.
- [ ] Shards balanced by duration; setup cost measured.
- [ ] Merge queue configured with a stable required-check set.
- [ ] Flakes tracked with owners and quarantine, not retried into silence.
- [ ] Cache hit rate, CI time, and flake rate reported on a dashboard.

Related: [01-tools](./01-tools.md) for runner choice, [02-structure-boundaries](./02-structure-boundaries.md) for keeping the graph clean, [09-governance-metrics](./09-governance-metrics.md) for budgets.
