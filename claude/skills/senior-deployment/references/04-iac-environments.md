# IaC and Environments

Scope: environment topology and isolation, infrastructure as code structure per environment, ephemeral preview environments, state and drift management, and artifact promotion between environments.

## Environment Topology

| Environment | Lifetime | Data | Purpose | Access |
|---|---|---|---|---|
| Local | Developer session | Synthetic | Fast iteration, unit and component tests | Developer |
| Ephemeral preview | Per pull request, TTL hours to days | Synthetic or anonymized subset | Review UI and integration behavior of a change | Team plus reviewers |
| Integration/QA | Long-lived | Synthetic, refreshed | Cross-service integration, migration rehearsal | Team |
| Staging | Long-lived | Production-shaped, anonymized | Release rehearsal, performance smoke, final verification | Team, restrict writes |
| Production | Permanent | Real | Serve users | Break-glass only, audited |
| Sandbox | Long-lived | Synthetic | Experiments, demos, training | Broad, isolated from prod |

Rules:

- Every environment has an owner, a budget, and a purpose. Unused environments are cost and drift sources; reap them.
- Isolate by account/project/subscription or at minimum by network boundary and IAM. Production credentials must not be assumable from lower environments.
- Lower environments must not contain real customer PII. Use anonymized or synthetic data generation, or masked subsets with a documented policy.
- Keep environment parity where it matters: runtime version, deployment mechanism, IaC modules, and secret injection. Parity in every detail is a myth; parity in production-critical axes is mandatory.
- Fewer environments beats more. Each environment multiplies cost, drift, and maintenance. A team with six half-maintained environments would usually be better with three healthy ones.

## IaC per Environment

Structure options:

| Pattern | Description | Use when |
|---|---|---|
| One root, workspaces | Same code, state per workspace | Small, uniform stacks |
| Directory per environment | `envs/dev`, `envs/stage`, `envs/prod` composed from shared modules | Default for production systems; explicit and greppable |
| Stack per component plus composition | Networking, data, app as separate states, wired by outputs | Large systems; blast-radius control |
| Environment-agnostic modules plus tfvars | Modules in `modules/`, values per environment | Recommended baseline for any multi-env setup |
| Generated composition (Terragrunt-style) | DRY wrappers over many states | Many similar stacks; adds a tool dependency |

Baseline recommendations:

- Shared modules own resource shape; environment directories own inputs (sizes, counts, domains, regions).
- Never fork a module per environment. Forks drift and diverge.
- Separate state per environment and per blast-radius boundary (network, data, cluster, app). A single state for everything makes one mistake global.
- Remote state with locking and versioning; state files contain secrets and must be access-controlled and encrypted at rest. See `./05-secrets-config.md`.
- Reconcile providers and modules with an automated dependency updater and test upgrades in the lowest environment first.
- Changes to shared modules require a plan in every environment before merge; show the diffs in review.
- Policy as code (for example OPA/Rego, Cedar-style policies, or provider guardrails) enforces tagging, encryption, and public-access rules in CI and at deploy time.
- Tag everything with environment, service, owner, and cost center so cost and access reviews work.

## State, Locking, and Drift

- Remote backend with locking is non-negotiable for shared environments. Local state is for throwaway experiments only.
- State is not a cache of truth; the provider is. Reconcile regularly.
- Drift detection runs on a schedule: plan (read-only) against each environment and alert on non-empty diffs. Some tools call this continuous reconciliation; verify feature names upstream.
- Drift triage: classify as expected (provider-managed fields, autoscaling), urgent (security-relevant changes), or accidental (console edits). Only accidental and urgent drift is auto-remediable.
- Guardrails: disable or restrict console mutation of IaC-managed resources where the provider allows it.
- Break-glass changes made in the console must be imported back into code or reverted within a fixed window, with a ticket. Untracked manual changes are how environments become snowflakes.
- Refresh before apply; a stale state plus a fast-moving provider is a recipe for destroying and recreating resources.

## Ephemeral Preview Environments

Purpose: prove a change works end to end in a realistic topology before merge, and let reviewers see the UI.

Design:

- One environment per pull request, named by repository plus PR number, created on `opened`/`synchronize`, destroyed on `closed`.
- Provision from the same IaC modules and the same container image digest built by CI (`./02-ci.md`). A preview that builds different code proves nothing.
- TTL and reaping are mandatory. Orphaned previews are the most common cost incident in preview programs.
- Data: seed from a fixture set or an anonymized snapshot. Never a live replica of production.
- Budget caps and quotas per preview (namespace resource quotas, cloud budgets/alerts).
- Networking: unique hostname per PR (for example `pr-123.preview.example.com`) with automated DNS and TLS.
- Databases: use a per-preview schema or database on a shared instance for small teams; per-preview instances where isolation matters. Handle migrations automatically, including rollback of preview data.
- Secrets: scoped, non-production credentials or short-lived dynamic credentials (`./05-secrets-config.md`).
- Cleanup verification: a nightly job that finds and destroys unclaimed previews and reports leaks.
- Cost visibility: tag preview resources so their spend is attributable and capped.

Anti-patterns:

- Preview environments that require manual setup steps from the reviewer.
- Previews with production credentials or production data.
- No TTL, no owner, no quota.
- Previews that only build the frontend and stub the backend; they miss integration failures.
- One shared "preview" environment for all PRs; concurrent changes collide.

## Promotion

The rule: build once, promote the artifact, change only configuration between environments.

Promotion models:

| Model | Description | Use when |
|---|---|---|
| Push-based | CI holds environment credentials and deploys sequentially | Small teams, simple topologies |
| Pull-based / GitOps | A controller in-cluster reconciles from a config repository | Auditability and drift control required |
| Hybrid | CI publishes an image and updates a version manifest; GitOps reconciles | Common production pattern |

- The promotion event is a version bump in an environment manifest or a parameter, not a rebuild.
- Config differences between environments are explicit inputs (instance sizes, replica counts, feature defaults), reviewed like code.
- Approval gates sit on the promotion step, not on the build. See `./09-release-management.md`.
- Secrets are never in the promotion artifact; they are resolved by the target environment at runtime.
- Record what was promoted, by whom, when, and from which commit; this is the release ledger (`./09-release-management.md`).
- Rollback promotes the previous digest; the previous environment manifest is retained.
- Prefer promoting through a fixed order, with staging verification results attached to the production promotion.

## Environment Configuration

- Configuration is data, not code branches. Environment checks in application logic (`if env == "prod"`) should collapse into configuration (`if features.x`). See `./05-secrets-config.md`.
- Feature defaults differ per environment deliberately: risky features default off in production and on in staging.
- Environment-specific endpoints (queue URLs, bucket names) are injected; no environment names in code.
- Keep a machine-readable inventory of environments and their properties; humans and automation both need it.

## Naming and Inventory

- Fix a naming scheme before the second environment exists: `<org>-<service>-<env>-<region>-<resource>` is a workable default. Names appear in DNS, IAM policies, dashboards, and cost reports; renaming later is a migration.
- Environment names are stable identifiers: use `production`/`staging`/`preview-<pr>`, not `prod2` or `new-prod`. Aliases age badly.
- Maintain a machine-readable inventory of environments (name, account, region, owner, tier, cost center) and generate documentation from it. Stale wiki pages are worse than no pages.
- Tag/label every resource consistently; policy-as-code rejects untagged resources.
- Keep a single glossary for environment tiers and their guarantees so that "staging" means the same thing to every team.

## Cost Governance

- Give each environment a budget and an alert; preview and sandbox environments are the usual offenders.
- Right-size lower environments deliberately: they should be small, but large enough to surface performance pathologies where that is the purpose of the environment.
- Schedule non-production environments off outside working hours where the workload allows; keep staging data-safe but warm enough to be usable.
- Attribute cost by environment, service, and team so optimization work has an owner.
- Review environment spend quarterly; an environment nobody can justify is a candidate for deletion, not for downsizing.

## Migration Notes

- Moving from console-managed infrastructure: import resources into IaC in a branch, prove a no-op plan, then enable drift detection. Do not start with drift auto-remediation; you will fight import gaps for weeks.
- Moving from one giant state to per-component states: use state moves and split incrementally, environment by environment, lowest risk first.
- Moving from copy-pasted environment directories to modules: extract one resource type at a time, verify no-op plans in every environment, then continue.
- Moving preview environments from a shared instance to per-PR: start with a TTL and a quota on the shared path before adding isolation, so the first failure mode is bounded.
- Moving from push-based to GitOps promotion: run both paths read-only in parallel until the controller's reconciliation matches the current state, then cut writes over.

## Anti-Patterns

- Click-ops changes reconciled "later" that never get reconciled.
- One Terraform state for all environments and services.
- Copy-pasted environment directories that have silently diverged.
- Preview environments with no TTL or budget.
- Production data copied to lower environments without masking.
- Rebuilding artifacts per environment under the same version.
- Secrets stored in IaC variables or state without an encryption and access plan.
- Environment-specific branches (`release/staging`) instead of environment configuration.
- Promoting by "deploy the same branch again" rather than the same digest.
- Treating drift alerts as noise and muting them.

## Checklist

- [ ] Every environment has an owner, purpose, budget, and reaping policy.
- [ ] Isolation boundary between production and non-production is enforced by identity, not convention.
- [ ] Modules shared; environment differences are inputs only.
- [ ] State is remote, encrypted, locked, and partitioned by blast radius.
- [ ] Scheduled drift detection with triage and a break-glass reconciliation process.
- [ ] Preview environments are per-PR, digest-accurate, TTL-bound, and budget-capped.
- [ ] Lower environments use synthetic or anonymized data only.
- [ ] Promotion moves the same artifact by digest with config as the only delta.
- [ ] Promotion events are recorded with actor, artifact, and source commit.
- [ ] Policy as code enforces tagging, encryption, and exposure rules.
