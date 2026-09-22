# CD Strategies

Scope: rolling, blue-green, canary, and progressive delivery with Argo Rollouts or Flagger, metric-driven analysis gates, and rollback mechanics.

## Strategy Selection

| Strategy | Mechanics | Rollback | Cost | Use when |
|---|---|---|---|---|
| Recreate | Stop old, start new | Slow (full restart) | Lowest | Internal tools, batch workers with no availability requirement |
| Rolling | Replace instances in batches within a surge budget | Medium (roll back batch by batch) | Low | Default Kubernetes strategy for stateless services |
| Blue-green | Two full fleets, switch traffic atomically | Fast (switch back) | High (double capacity during cutover) | Instant cutover and instant rollback valued; schema changes are compatible |
| Canary | Send a slice of traffic to the new version, expand on health | Fast (shift traffic back) | Low to medium | User-facing production; the default when automated analysis exists |
| Progressive delivery | Canary or blue-green plus automated metric analysis and promotion steps | Fast and automated | Low plus observability investment | Mature platform with SLOs and dashboards |
| A/B test | Route by user attributes, often with flags | Instant via flag | Low | Product experiments; not a substitute for canary safety |

Rules that apply to all strategies:

- Deploy by digest, never by tag. See `./01-containers.md`.
- Readiness gates determine when an instance receives traffic; liveness gates restart it. Misconfigured probes cause more deploy incidents than bad code.
- `maxSurge` and `maxUnavailable` encode your risk tolerance; for critical services prefer surge over unavailability. Never set `maxUnavailable` to 100% and call it rolling.
- PodDisruptionBudgets protect against voluntary disruption, not deploy bugs.
- Graceful shutdown: handle SIGTERM, stop accepting new work, drain in-flight requests within the termination grace period. See `./07-observability-rollback.md`.
- One deploy in flight per service per environment. Serialize with concurrency controls or an admission mechanism.

## Rolling Updates

Kubernetes default. Mechanics:

- New ReplicaSet scales up by `maxSurge`; old scales down by `maxUnavailable`.
- The rollout completes when all new pods are ready and old pods are gone.
- `progressDeadlineSeconds` fails a stuck rollout; set it deliberately (large services need more than the default).

Requirements for zero downtime:

- Multiple replicas (at least two, three for meaningful availability).
- Correct readiness probes that fail before the process stops serving.
- `preStop` hooks or application drain logic when connection draining exceeds the platform default.
- Long-lived connections (websockets, gRPC streams) need connection draining or client-side retry with backoff.
- Stateful sets require ordered rollout awareness; database compatibility per `./06-database-migrations.md`.

Rollback: `kubectl rollout undo` or redeploy the previous revision. Fast only if the replica history and image are still available; keep the previous revisions.

## Blue-Green

Mechanics:

- Two identical fleets (blue is live, green is idle or scaled to a smoke level).
- Deploy to idle, run smoke and migration checks, then switch the router/load balancer/service selector.
- Keep the old fleet warm for the rollback window, then scale it down.

Considerations:

- Database migrations must be compatible with both colors simultaneously (expand-contract, `./06-database-migrations.md`).
- Session state must be externalized; sticky sessions to a color defeat the cutover.
- DNS-based cutover is not instant (TTL and resolver caching); prefer a load balancer or service mesh switch.
- Double capacity is the cost; for large fleets, partial blue-green (a small green pool plus canary) is often better.
- Timer-based rollback reminder: forgetting to scale down the old fleet is a standing cost bug.

## Canary

Mechanics:

- Deploy the new version to a small replica set or a subset of pods.
- Shift a small percentage of traffic, observe, then increase in steps (for example 1 to 5 to 25 to 50 to 100 percent).
- Abort on failure, shifting traffic back to the stable version.

Traffic splitting options:

| Mechanism | Granularity | Notes |
|---|---|---|
| Replica ratio (stable/canary) | Pod-level | Simple; crude at low traffic |
| Ingress/load balancer weights | Request-level | Needs weighted routing support |
| Service mesh | Request-level, header-aware | Strongest control; extra platform dependency |
| Gateway API or provider-native | Request-level | Managed option; verify feature parity upstream |

Analysis inputs:

- Error rate and latency percentiles (p95/p99), by version.
- Saturation: CPU, memory, queue depth.
- Custom business KPIs where they are stable enough to gate on.
- Logs and traces for errors unique to the canary.

Requirements:

- Traffic volume sufficient for the analysis window to be statistically meaningful. A 1% canary on 10 requests per minute proves nothing.
- Version label on metrics and traces so the analysis can compare canary against baseline. See `./07-observability-rollback.md`.
- Predefined thresholds and abort behavior, not human eyeballs on a dashboard.

## Progressive Delivery Platforms

Argo Rollouts and Flagger are the common Kubernetes implementations. They provide:

- Rollout CRDs replacing Deployments, with steps, pauses, and traffic routing.
- Metric analysis (Prometheus, Datadog, New Relic, cloud monitoring) with success thresholds, failure limits, and intervals.
- Traffic shaping via ingress controllers or service meshes.
- Automated abort and rollback to the last healthy revision.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: api
spec:
  replicas: 6
  strategy:
    canary:
      steps:
        - setWeight: 5
        - pause: { duration: 10m }
        - analysis:
            templates:
              - templateName: error-rate
        - setWeight: 50
        - pause: { duration: 10m }
        - setWeight: 100
```

Analysis template essentials:

- Query compares canary to stable over the same window.
- Success condition and failure limit are explicit; one failing interval is not always a failure.
- `startingStep` or a warm-up delay avoids judging a cold canary.
- The template is versioned with the service and tested against historical data before first use.

Operational rules:

- Do not combine two progressive controllers on the same workload.
- Keep the analysis query cheap; a heavy query on the critical path delays deploys and can itself cause timeouts.
- Alert on rollouts that abort and on analysis that cannot evaluate (missing metrics is a failure mode, not a pass).
- Practice the abort path; an untested rollback is a hope, not a plan.

## Automated Analysis

Designing gates:

| Signal | Good gate | Bad gate |
|---|---|---|
| Error rate | Ratio vs stable, sustained over the window | Absolute count with no baseline |
| Latency | p95/p99 ratio canary vs stable | Average latency (hides tails) |
| Saturation | Resource usage against limits | Raw CPU without limits context |
| Business KPI | Conversion delta with sufficient traffic | Revenue per minute at low volume |
| Availability | Synthetic probe success by version | One ping to the service root |

- Define the failure action before enabling the gate: abort, pause for human decision, or roll back automatically.
- Separate "analysis failed" from "analysis unavailable". The former blocks, the latter should page rather than silently promote.
- Keep the analysis window long enough to cover slow failures (leaks, connection exhaustion) and short enough to keep deploys moving. Ten to thirty minutes per step is a common range; verify against your traffic profile.

## Rollback Mechanics

Rollback must be a routine operation, not an incident.

- Artifact immutability: the previous digest still exists in the registry and is deployable. Retention policies must protect the last N releases.
- Configuration rollback: config and secrets are versioned too; a bad config change needs the same rollback path.
- Database compatibility: the old code must run against the new schema for the rollback window. This is the hard constraint that expand-contract exists to satisfy (see `./06-database-migrations.md`).
- Feature flags can decouple: disable the flag to remove the new behavior while leaving the artifact deployable. See `./08-feature-flags.md`.
- One-command rollback with a tested runbook and an owner. Time it in a game day.
- Post-rollback: keep the evidence (analysis results, logs, traces) and open a follow-up instead of immediately redeploying the same artifact.

## Anti-Patterns

- Deploying to 100% of instances at once because "it is just a small change".
- Canary without metrics comparison, judged by watching a dashboard manually.
- Rollback plans that require rebuilding the old artifact.
- Schema changes that break the N-1 version, making rollback impossible.
- Probes that always pass, or that call deep dependencies and can cascade failures.
- Multiple deploys racing for the same service.
- Canarying a change that only manifests at full traffic or after hours, with a ten-minute gate.
- Ignoring `maxUnavailable` defaults that can take down the whole service.
- Auto-promotion with no pause and no analysis, i.e. a rolling update with extra YAML.

## Checklist

- [ ] Strategy chosen deliberately per service and recorded.
- [ ] Deploys reference immutable digests; previous releases retained.
- [ ] Readiness, liveness, and startup probes verified against real behavior.
- [ ] Graceful shutdown and connection draining tested.
- [ ] Traffic-splitting mechanism selected and capacity validated.
- [ ] Analysis queries compare canary to stable and are cheap to run.
- [ ] Failure action (abort, pause, rollback) is explicit and automated.
- [ ] Rollback rehearsed within the last quarter and timed.
- [ ] Schema changes compatible with rolling back one version.
- [ ] One deploy in flight per service; concurrency controlled.
