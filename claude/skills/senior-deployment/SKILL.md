---
name: senior-deployment
description: 'Deployment reference pack for shipping software to production: container
  image builds and supply-chain hygiene, CI pipeline design and security, continuous
  delivery strategies (rolling, blue-green, canary, progressive delivery), infrastructure
  as code and environment topology, secrets and configuration, zero-downtime database
  migrations, deployment observability and rollback, feature flags, and release management.
  Use when writing or reviewing a Dockerfile or build pipeline, designing CI/CD workflows,
  choosing a deployment strategy or rollback plan, provisioning environments with
  IaC, managing secrets and configuration, planning schema migrations or backfills,
  gating releases on SLOs, rolling out features behind flags, or cutting a release
  and writing changelogs.'
---

# Deployment

Reference pack for senior delivery work: containers, CI, CD strategies, IaC and environments, secrets and config, database migrations, deployment observability and rollback, feature flags, and release management. Depth lives in `references/`; this file is the map.

## Baseline (2026)

- Containers are built with BuildKit-era tooling by default, and provenance plus SBOM attestation are expected for production images, not optional. Buildpacks and hosted builders are common where a Dockerfile is not the right abstraction.
- CI is converging on OIDC federation: pipelines assume short-lived cloud and registry credentials instead of storing long-lived keys. Pipelines are treated as production systems with least-privilege permissions.
- Progressive delivery (Argo Rollouts, Flagger, or provider-native canary) is the default for user-facing production changes; plain replace-everything deploys are an anti-pattern for anything with an availability requirement.
- Infrastructure is described in code with remote state, plan-on-PR, apply-on-merge, and drift detection. Ephemeral per-PR preview environments are standard on mature teams.
- Secrets live in a manager with identity-based access and rotation; plaintext in CI variables or repository files is a review blocker.
- Database changes are decoupled from application deploys through expand-contract and online migration tooling.
- Version claims in this pack are floors, ranges, or "verify upstream"; never treat them as pinned exact versions.

## Non-Negotiable Core Rules

1. Build once, promote the same immutable artifact through every environment. Rebuilding per environment invalidates every test and approval that came before. See `./references/01-containers.md` and `./references/04-iac-environments.md`.
2. Images run as non-root, contain no build toolchains or secrets, and carry a digest reference in deployment manifests. Tags are mutable; digests are not. See `./references/01-containers.md`.
3. CI must be reproducible and least-privilege: pinned action/tool versions (commit SHAs for third-party actions), explicit `permissions`, and OIDC instead of long-lived cloud credentials. See `./references/02-ci.md`.
4. Production changes default to progressive delivery with an automated analysis gate and a tested rollback. A deploy plan without a rollback path is incomplete. See `./references/03-cd-strategies.md` and `./references/07-observability-rollback.md`.
5. Environments are provisioned by IaC from the same modules with per-environment inputs; manual console changes to managed resources are drift and must be reconciled or reverted. See `./references/04-iac-environments.md`.
6. Configuration is environment-specific and typed, validated at startup; secrets are fetched at runtime from a manager using workload identity. No secret in an image, a repo, a build log, or a frontend bundle. See `./references/05-secrets-config.md`.
7. Schema changes are backward compatible with the currently running and next version: expand first, deploy, contract later. Migrations run before application rollout and never assume exclusive access. See `./references/06-database-migrations.md`.
8. Every release is identifiable: version, commit, artifact digest, and deploy ID are emitted into telemetry as a release marker. If you cannot answer "which version is serving this request?", the deploy is not observable. See `./references/07-observability-rollback.md` and `./references/09-release-management.md`.
9. Feature flags are short-lived release machinery with an owner and an expiry; they are removed after rollout, and flagged code paths are tested. Long-lived flags are configuration, not releases, and must be classified as such. See `./references/08-feature-flags.md`.
10. Releases have an audit trail: changelog, provenance attestation, approver, and post-release review. Emergency changes follow the same path with reduced ceremony, not a bypass. See `./references/09-release-management.md`.

## Decision Tables

### Deployment Strategy Selection

| Situation | Strategy | Notes |
|---|---|---|
| Stateless service, mature platform, low risk tolerance | Canary with automated analysis | Default for user-facing production |
| Two full environments feasible, instant cutover required | Blue-green | Fast rollback; double capacity during cutover |
| Kubernetes without a progressive-delivery controller | Rolling update with readiness gates and maxSurge/maxUnavailable | Cheapest; slower rollback |
| Schema or stateful protocol change | Expand-contract plus rolling or canary | See `./references/06-database-migrations.md` |
| Internal tool or batch job, no availability requirement | Recreate | Accept the gap; keep it deliberate |
| Cohort or experiment rollout | Feature flags on top of a safe deploy | See `./references/08-feature-flags.md` |

### Environment and Promotion

| Need | Pattern | Notes |
|---|---|---|
| Fast feedback per developer | Ephemeral per-PR environment with TTL | Same IaC modules, smallest viable size |
| Pre-production integration | Long-lived staging, production-like data shape | Never a copy of production PII |
| Regulated or audited releases | Release train with approval gate | Fewer, bolder releases with evidence |
| Trunk-based continuous delivery | Continuous promotion through automated gates | Requires strong test and observability culture |

### Secret and Config Backend

| Context | Store | Injection |
|---|---|---|
| Cloud-native workloads | Cloud secret manager (identity-based) | CSI driver, operator sync, or SDK fetch |
| Multi-cloud or on-prem | Vault-compatible manager or SOPS-encrypted files | CSI, init container, or runtime fetch |
| Kubernetes-only, GitOps | SOPS or sealed secrets committed encrypted | Controller decrypts in-cluster |
| Local development | Encrypted local files, never real production secrets | Developer-scoped credentials only |

### Schema Change Triage

| Change | Expand-contract required | Notes |
|---|---|---|
| Add nullable column or table | No | Add with no default rewrite where the engine allows |
| Add NOT NULL column | Yes | Backfill then constrain in a later release |
| Rename column or table | Yes | Add new, dual-write, migrate readers, drop old |
| Change type or column order | Yes | New column, backfill, switch, drop |
| Add index on a large hot table | Depends | Use concurrent/online index builds; verify lock behavior upstream |
| Drop anything | Yes | Contract only after every reader is migrated |

### Deploy or Flag

| Question | Answer |
|---|---|
| Is the change reversible by redeploying the previous artifact? | Deploy; no flag needed |
| Does it need instant kill without a deploy? | Flag (ops/kill switch) |
| Is it user-visible and being evaluated per cohort? | Flag (experiment or release) |
| Does it change data shape irreversibly? | Migration process, not a flag |
| Will it live longer than one or two release cycles? | Configuration, not a flag |

## Reference Index

| File | Scope | Load when |
|---|---|---|
| `./references/01-containers.md` | Multi-stage builds, base image selection, layer caching, image hygiene, buildpacks, multi-arch, SBOM and scanning | Writing or reviewing a Dockerfile or image build, shrinking images, fixing cache misses, adding provenance or scanning |
| `./references/02-ci.md` | Pipeline design, GitHub Actions patterns, caching, matrices, required checks, signing, OIDC and pipeline security | Designing or debugging CI, speeding up workflows, hardening permissions, wiring required checks |
| `./references/03-cd-strategies.md` | Rolling, blue-green, canary, progressive delivery with Argo Rollouts or Flagger, automated analysis, rollback | Choosing a rollout strategy, configuring traffic shifting or analysis gates, adding rollback |
| `./references/04-iac-environments.md` | Environment topology, ephemeral preview environments, IaC per environment, state, drift, promotion | Provisioning environments, structuring IaC for multiple environments, detecting or fixing drift |
| `./references/05-secrets-config.md` | Secret managers, workload-identity auth, rotation, 12-factor config, injection patterns, secret scanning | Managing secrets or config, removing long-lived credentials, responding to a leaked secret |
| `./references/06-database-migrations.md` | Expand-contract, backward-compatible changes, online DDL, backfills, verification, rollback | Planning a schema change, backfilling data, migrating without downtime |
| `./references/07-observability-rollback.md` | Release markers, SLO-based gating, health checks, deploy dashboards, rollback and DR drills | Gating a release on metrics, debugging a bad deploy, designing rollback or DR procedures |
| `./references/08-feature-flags.md` | Flag categories, targeting and progressive exposure, lifecycle and cleanup, testing with flags | Introducing flags, designing targeting or kill switches, cleaning up flag debt |
| `./references/09-release-management.md` | Versioning, changelogs, artifact provenance, release trains, approvals, post-release review | Cutting a release, writing changelogs, defining approval flow, running a release retrospective |

## Load Order

- New service from zero: `./references/01-containers.md`, `./references/02-ci.md`, `./references/04-iac-environments.md`, then `./references/03-cd-strategies.md` and `./references/07-observability-rollback.md`.
- Reviewing a deploy plan: `./references/03-cd-strategies.md`, `./references/06-database-migrations.md` (if schema changes), `./references/07-observability-rollback.md`.
- Migration or backfill: `./references/06-database-migrations.md`, with `./references/08-feature-flags.md` when old and new paths must coexist.
- Secrets, rotation, or leak response: `./references/05-secrets-config.md`, with `./references/02-ci.md` for pipeline identity.
- Release process or compliance: `./references/09-release-management.md`, with `./references/04-iac-environments.md` for promotion.
- Load only the references the task needs; do not inject the whole pack into context.

## Review Workflow

For a non-trivial delivery change, this is the default pass order:

1. Confirm the artifact is built once and promoted by digest (`./references/01-containers.md`, `./references/04-iac-environments.md`).
2. Check the pipeline for least privilege, pinned dependencies, and OIDC (`./references/02-ci.md`).
3. Validate the rollout strategy, analysis gates, and rollback path (`./references/03-cd-strategies.md`, `./references/07-observability-rollback.md`).
4. Verify secrets and config are external, typed, and validated (`./references/05-secrets-config.md`).
5. Walk every schema change through expand-contract and check backfill safety (`./references/06-database-migrations.md`).
6. Classify flags, assign owners and expiry, and confirm cleanup (`./references/08-feature-flags.md`).
7. Check provenance, changelog, approvals, and post-release review hooks (`./references/09-release-management.md`).

## Port

- **Port id** — `skill://senior/deployment` (version in `metadata.port-version`, currently `2.0.0`).
- **Kind** — read-only reference pack; no side effects, no tools required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "deployment" })` in OpenCode; Claude Code reads `<skills-dir>/deployment/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers reference it as `load skill senior-deployment (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major.

## Contract

- References are numbered `01`-`09`; keep them mutually consistent and cross-linked with relative paths.
- Version claims are floors or qualified with "verify upstream"; never present invented exact versions as fact.
- Anti-patterns and checklists close every reference; treat unchecked boxes as review findings.
- No emojis, English only, and no tooling that mutates the user's systems.
