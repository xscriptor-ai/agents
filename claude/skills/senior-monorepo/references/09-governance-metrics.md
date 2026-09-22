# Governance and Metrics

> Scope: CODEOWNERS, drift detection, healthy-monorepo metrics and budgets, documentation, and the platform team model.

A monorepo is shared infrastructure. Governance is what keeps sharing from turning into coupling: named owners, detectable drift, and numbers everyone can see.

## 1. Ownership with CODEOWNERS

`CODEOWNERS` (GitHub) or the platform equivalent maps paths to reviewers. It is the cheapest accountability mechanism in a monorepo.

```
# .github/CODEOWNERS
*                       @acme/platform

/apps/web/              @acme/web-team
/apps/api/              @acme/backend-team
/packages/ui/           @acme/design-system
/packages/contracts/    @acme/architecture @acme/backend-team
/packages/config/       @acme/platform
/tools/                 @acme/platform
/.github/               @acme/platform
/pnpm-workspace.yaml    @acme/platform
/pnpm-lock.yaml         @acme/platform

# generated code is owned by the spec owner, not the generator runner
/packages/gen/**        @acme/architecture
/**/generated/**        @acme/architecture
```

Rules:

- Most specific rule wins; order matters in the file (later rules take precedence in GitHub Code Owners). Verify current semantics upstream.
- Every top-level directory has an owner; never rely on the `*` fallback for a package.
- Lockfile and workspace config belong to the platform team; they are global contracts.
- Generated code and specs have a single owner each; split ownership causes contradictory fixes.
- Ownership is reviewed when packages move, merge, or are deprecated.
- Pairing rules (team plus platform) on protected paths prevent silent breakage without creating a bottleneck.
- Measure ownership coverage: percentage of project directories matched by a non-fallback rule. Target 100%; report the gap monthly.

## 2. Rulesets and required checks

- Protect the default branch: linear history or merge queue, required reviews for owned paths, required status checks.
- Required checks should be a small, stable set: install/lint/typecheck/build/test as configured by the graph. Keep names stable; renaming a check silently unblocks merges.
- Use rulesets (GitHub) or push rules (GitLab) to protect release tags, workflow files, and generated directories.
- Release environments require approval and are scoped to the release workflow; no human publishes from a laptop.
- CI configuration files are code-owned by the platform team; changes to them get a security-minded review.

## 3. Drift detection

Drift is any divergence that no single change intended. Detect it mechanically; do not rely on reviewer memory.

| Drift type | Check | Tooling |
| --- | --- | --- |
| Dependency version skew | same dep declared with multiple incompatible ranges | `syncpack list-mismatches`, `sherif`, `pnpm why -r` |
| Toolchain drift | Node/package-manager/tool versions differ between packages and CI | `.nvmrc`, `engines`, `packageManager`, CI matrix comparison |
| Config drift | tsconfig/ESLint options diverge silently | extend-only policy; config inheritance check |
| Ownership drift | packages with no CODEOWNERS match | script against project list |
| Boundary drift | unapproved cross-package imports | boundary lint rules, `turbo boundaries` |
| Generated drift | committed output differs from regeneration | `git diff --exit-code` after codegen |
| Dependency freshness | packages pinned to stale majors | Renovate dashboard, `pnpm outdated -r` |
| Dead packages | no consumers, no changes in months | dependency graph query, git log |
| Duplicate packages | two implementations of the same capability | inventory by scope tags |
| License drift | new licenses incompatible with policy | license audit in CI |
| Secrets drift | credentials in package configs or outputs | secret scanning, cache artifact scanning |

Example policy script shape:

```bash
# CI: fail on workspace hygiene violations
pnpm exec syncpack list-mismatches || exit 1
pnpm exec sherif --check || exit 1
node tools/scripts/check-ownership.mjs || exit 1
node tools/scripts/check-orphans.mjs || exit 1
```

Rules:

- Every automated drift check has an owner and a documented fix path; a check nobody can fix becomes noise.
- Prefer warnings in PRs and errors on main for new checks; graduate to errors everywhere after cleanup.
- Run drift checks on a schedule as well as on PRs, so dormant drift is caught without a code change.

## 4. Metrics that matter

Measure the system, not individual activity. Publish a small dashboard; more metrics usually mean less attention.

| Metric | Definition | Healthy direction |
| --- | --- | --- |
| Install time | frozen install on a cold runner | stable; alert on >20% regression |
| PR CI wall time (p50/p95) | merge-base diff to final check | p50 minutes, p95 bounded |
| Queue time | wait before a runner starts | low; alert on queue growth |
| Cache hit rate | remote hits / cacheable tasks | high and stable; investigate drops |
| Affected ratio | projects run / projects total per PR | low by design, not by gaming |
| Flake rate | tasks needing retry or failing intermittently | <1-2% per task |
| Build failure rate on main | red main commits per week | near zero; investigate clusters |
| Change lead time | first commit to production/release | stable or improving |
| Ownership coverage | projects with a real owner | 100% |
| Boundary violations | new violations per week | zero tolerated |
| Dependency freshness | share of deps on supported majors | reviewed monthly |
| Repo size / clone time | full and shallow clone durations | bounded; alert on growth |
| Onboarding time | first merged PR for a new engineer | measured, improving |

Anti-metrics to avoid: lines of code, commit counts per developer, number of packages, PR count. They reward the wrong behavior and say nothing about the system.

## 5. Budgets and alerts

Set explicit budgets and treat breaches as defects:

- CI p95 for a normal PR under a fixed budget (for example 15 minutes); exceeding it triggers an investigation, not a shrug.
- Remote cache hit rate above a floor (for example 70% for repeated CI runs); a drop usually means a hashing mistake or a new non-deterministic input.
- Full main build under a budget; growth tracked per month.
- Flake rate below 1% per task; a task above threshold gets quarantined and fixed.
- Install time budget; lockfile changes that double install time are blocked until resolved.

Wire alerts to the platform team's channel, with links to the failing signal and a runbook. See [05-caching-ci](./05-caching-ci.md) for how cache and CI metrics are produced.

## 6. Documentation

Minimum documentation set for a healthy monorepo:

| Document | Location | Content |
| --- | --- | --- |
| Root README | `README.md` | what the repo contains, how to install/build/test, links |
| Package README | each package | purpose, owner, public API, examples, status |
| CONTRIBUTING | `CONTRIBUTING.md` | branch/PR flow, changesets, boundaries, review expectations |
| Architecture decisions | `docs/adr/` | decisions with dates and consequences |
| Runbooks | `docs/runbooks/` | CI, cache, release, and incident procedures |
| Onboarding | `docs/onboarding.md` | day-one setup, graph tour, ownership map |
| Migration/import log | `docs/migrations/` | old repo -> new path mapping and dates |

Rules:

- Documentation is tested where possible: links checked in CI, commands copy-pasteable, README examples executed in a smoke job.
- Keep one canonical place per fact; duplicated docs drift faster than code.
- A package without a README is not ready to be shared.
- Update docs in the same PR that changes behavior.

## 7. The platform team model

- The platform team owns the system: tooling, caching, CI, release automation, governance checks. It does not own every package.
- Package owners own their code, API, tests, and on-call for their domain.
- The platform team runs a service mindset: published SLOs, an intake path, and a changelog for tooling changes.
- Structural changes (layout, runner, boundaries) require an ADR and platform + stakeholder review.
- Rotation or office hours prevent the platform team from becoming a ticket queue.
- Measure platform work by developer outcomes (CI time, flake rate, onboarding) rather than ticket counts.

## 8. Anti-patterns

| Anti-pattern | Symptom | Fix |
| --- | --- | --- |
| Fallback owner for everything | no one feels responsible | per-directory owners, coverage check |
| CODEOWNERS out of date | review requests stall or skip experts | ownership review on every move; automated coverage |
| Metrics used for performance review | gaming, hiding problems | system metrics only, published transparently |
| No budgets | slow erosion until CI is unusable | explicit budgets with alerts |
| Drift checks with no owner | warnings ignored | assign owner and fix path, or delete the check |
| Documentation duplicated | conflicting instructions | one canonical source |
| Platform team as sole contributor | bottleneck, burnout | distribute package ownership, enable self-service |
| Zero tolerance for red main misapplied | hotfix freezes | fast revert/revert-forward culture with metrics |

## Checklist

- [ ] CODEOWNERS covers every package, tooling directory, and generated path; coverage measured.
- [ ] Branch protection and rulesets enforce reviews and stable required checks.
- [ ] Drift checks run in CI and on a schedule: skew, config, ownership, generated, orphans.
- [ ] Core metrics (CI wall time, cache hit rate, flake rate, queue time) are on a dashboard.
- [ ] Budgets have owners, alerts, and runbooks.
- [ ] README/CONTRIBUTING/ADR/onboarding docs exist and links are checked in CI.
- [ ] Platform team scope, SLOs, and intake path are documented.
- [ ] Structural changes require an ADR; changes reviewed with stakeholders.

Related: [01-tools](./01-tools.md) for the system being governed, [05-caching-ci](./05-caching-ci.md) for metric production, [02-structure-boundaries](./02-structure-boundaries.md) for ownership-aware boundaries.
