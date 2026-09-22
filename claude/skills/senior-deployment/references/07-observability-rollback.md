# Observability and Rollback

Scope: release markers, health checks, SLO-based deploy gating, deploy dashboards, rollback automation, and disaster-recovery drills.

## Release Markers

A release marker is a timestamped annotation in telemetry that says "version X was deployed at T to environment E". Without it, correlating a behavior change to a deploy is guesswork.

Emit into telemetry:

| Field | Example | Purpose |
|---|---|---|
| Version | semver or CalVer | Human-facing identity |
| Commit | full SHA | Source of truth |
| Artifact digest | image or package digest | What is actually running |
| Deploy ID | pipeline run ID | Links to the pipeline and approval |
| Deployed at | ISO timestamp | Overlay on dashboards |
| Deployed by | actor or automation identity | Audit |

- Emit as a deployment event to the telemetry backend, as an annotation on dashboards, and as a resource attribute on traces/metrics/logs where practical.
- Kubernetes: annotate Deployments/pods, and let the collector or Operator enrich telemetry with the version. See the observability pack if installed.
- Make "which version is serving this request" answerable after the fact from a trace or log line.
- Keep a releases ledger queryable across environments (`./09-release-management.md`).
- Alert on version skew across replicas beyond a healthy rollout window; a partially rolled deployment is itself a signal.

## Health Checks

| Probe | Question | Failure action | Must not |
|---|---|---|---|
| Startup | Has the process finished initializing? | Keep waiting, then restart | Run forever; block readiness of dependents |
| Readiness | Can this instance serve traffic now? | Remove from load balancing | Depend on flaky deep dependencies |
| Liveness | Is the process wedged beyond recovery? | Restart container | Be a cascading failure vector |
| Synthetic | Can a user achieve a critical journey? | Page and possibly roll back | Replace unit and integration tests |

Rules:

- Readiness reflects local ability to serve; deep dependency checks belong in monitoring, not in the probe that removes capacity.
- Liveness must be conservative: an application under load responding slowly is alive. Aggressive liveness probes turn a latency spike into a restart loop.
- Shutdown: on SIGTERM, fail readiness first, drain, then exit within the grace period. See `./03-cd-strategies.md`.
- Have a dedicated health endpoint that does not require authentication but does not leak internals, and is excluded from access logs' noise and from trace sampling budgets.
- Version the health contract: `/healthz` returns build metadata carefully (no secrets, no environment dumps).
- Probe timeouts and thresholds are tuned per service and tested; copy-pasted defaults are a common incident cause.

## SLO-Based Deploy Gating

Deploy gating compares the candidate version against the stable baseline, not against an absolute ideal.

Inputs:

- Golden signals per version: error rate, latency percentiles, saturation, throughput.
- Traces with version attributes to localize new errors.
- Business KPIs where they are stable and high-volume enough.
- Log-derived error classes unique to the candidate.

Gate design:

| Gate | Baseline | Threshold style | Action |
|---|---|---|---|
| Error rate | Stable version, same window | Ratio-based, e.g. candidate no worse than baseline plus a margin | Abort or roll back |
| Latency p95/p99 | Stable version, same window | Relative increase bound | Abort after sustained breach |
| Saturation | Capacity limits | CPU/memory/queue headroom floor | Pause and inspect |
| Availability | Synthetic probes | Success ratio floor | Immediate rollback |
| Error budget | SLO target | Burn-rate based | Stop deploys when the budget is exhausted |

- Prefer burn-rate signals from SLOs where they exist: a deploy that consumes budget fast is failing, even if no alert has fired. See the observability pack for SLI/SLO mechanics.
- Require enough traffic before trusting a comparison. Document the minimum sample size; below it, pause and extend or fall back to manual review.
- Distinguish candidate-specific failure from environment-wide failure: if the whole cluster is sick, rolling back the deploy may not help. Check the baseline in the same window.
- Automate the abort. A gate that only notifies a human is a dashboard, not a gate.
- Treat "analysis could not run" as a failed gate by default; missing data during a deploy is itself suspicious.

## Deploy Dashboards

A deploy dashboard answers: what changed, what is happening, should I continue or abort.

Panels:

- Current rollout state per environment: version, digest, progress, paused steps, analysis results.
- Golden signals split by version or revision, with the release marker drawn in.
- Error classes new in the candidate versus baseline.
- Saturation and queue depth for the affected service and its direct dependencies.
- SLO burn rate and remaining error budget.
- Links: pipeline run, release notes, runbook, rollback action.

Rules:

- Dashboards are code, versioned and provisioned automatically; no hand-built panels that drift from reality. See the observability pack for dashboard-as-code patterns.
- Keep one screen: if the deploy dashboard requires scrolling and tab switching, it will not be used during an incident.
- Every panel should answer a go/no-go question; decorative panels cost attention.
- Include the rollback link prominently and make sure it works from the dashboard.

## Rollback

Rollback is the primary recovery mechanism and must be cheaper than debugging forward during an incident.

Triggers:

- Automated gate failure during progressive delivery (`./03-cd-strategies.md`).
- SLO burn or alert that starts within the deploy correlation window.
- Human judgment: rising error reports, support tickets, or a visible defect.

Mechanics:

- Redeploy the previous artifact digest with the previous configuration. No rebuild, no pipeline beyond the deploy job.
- For blue-green, switch traffic back. For canary, shift weight to stable. For rolling, redeploy the previous revision.
- Feature flags provide a faster, narrower lever for the offending behavior. See `./08-feature-flags.md`.
- Database compatibility keeps rollback safe; if it does not exist, the rollback is a forward fix (`./06-database-migrations.md`).
- Configuration and secret rollback: version them with the release so config can be reverted atomically.

Runbook requirements:

- One-command or one-click rollback with documented preconditions.
- Named owner and escalation path.
- Estimated time to restore (measured, not guessed).
- Post-rollback checks: error rate returns to baseline, queues drain, data integrity verified.
- Evidence capture before recovery where safe: logs, traces, analysis output. Do not destroy the failing deployment until evidence is collected (or replicate it in a preserved environment).

Practice:

- Game day: perform a rollback in production-like conditions at least quarterly; time it and fix the friction found.
- Roll back one change, not everything: if three changes are in flight, identification matters more than speed.
- After rollback, the artifact is not automatically banned; fix, test against the failure mode, and redeploy with the marker in place.

## Disaster Recovery

Deployment resilience and data resilience are different problems; both need drills.

- Define RTO (time to restore) and RPO (data loss tolerance) per service; derive backup frequency and restore tooling from them.
- Backups are unverified until restored: run scheduled restore tests into an isolated environment, and record results.
- Test regional or zone failover where the architecture claims multi-region.
- Exercise dependency loss: what happens when the secret manager, registry, DNS, or the primary database is unavailable at deploy time? Cache artifacts and credentials for just long enough.
- Document degraded modes: which features are disabled, what is still correct, and how users are informed.
- Keep the registry and artifact store as part of the DR plan; without the image, rollback is impossible.
- Drill outcomes become backlog items with owners; an untracked drill finding is theater.

## Anti-Patterns

- No release markers; version inferred from deploy time approximations.
- Liveness probes that restart pods under load, causing an outage spiral.
- Deep dependency checks in readiness probes, so a downstream blip removes all capacity.
- Manual canary analysis by refreshing a dashboard.
- Rollback plans that require a rebuild or a schema reversal.
- Backups never restored until the real incident.
- Dashboards built by hand and never reviewed.
- Alerts with no owner and no runbook link.
- Deploying during an active incident without freezing other pipelines.
- Post-rollback immediate redeploy of the same broken artifact.

## Checklist

- [ ] Release markers emitted to telemetry and dashboards with version and digest.
- [ ] "Which version served this request" answerable from logs or traces.
- [ ] Startup, readiness, liveness, and synthetic probes are distinct and tuned.
- [ ] Graceful shutdown drains readiness before exit.
- [ ] Deploy gates compare candidate versus baseline with defined thresholds and automated abort.
- [ ] Missing analysis data fails the gate by default.
- [ ] Deploy dashboard is one screen, version-split, and provisioned as code.
- [ ] Rollback is one command, rehearsed, and timed within the last quarter.
- [ ] Database and config compatibility preserved for the rollback window.
- [ ] Backups restored in a drill; RTO/RPO documented and met.
