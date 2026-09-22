# GitOps

> Scope: pull-based delivery design with Argo CD and Flux — repository structure, environment promotion, drift handling, secrets, and progressive delivery.

## Principles

1. **Declarative**: the desired state of every environment is expressed as manifests.
2. **Versioned and immutable**: the source of truth is a Git commit; history is the audit log.
3. **Pulled automatically**: an in-cluster agent reconciles; CI does not need cluster credentials.
4. **Continuously reconciled**: divergence is detected and either corrected or surfaced.

The practical payoff is rollback by `git revert` and a reviewable trail of every production change. The practical cost is that everything, including secrets and generated manifests, needs a strategy. See `./08-supply-chain-security.md` for signing and verification of what Git deploys.

## Tool selection

| Dimension | Argo CD | Flux |
|---|---|---|
| Model | Application CRD + controller; UI-centric | Toolkit of controllers (source, kustomize, helm, notification) |
| UI | Rich web UI, diff, sync, rollback | CLI-first; optional UI add-ons (Weave GitOps) |
| Multi-cluster | ApplicationSets; hub-and-spoke, cluster generator | Kustomization per cluster; flux bootstrap per cluster |
| Progressive delivery | Argo Rollouts | Flagger |
| Secrets | Any (SOPS, Sealed Secrets, ESO) | SOPS first-class; Sealed Secrets, ESO also supported |
| Helm | Native support plus hooks | HelmRelease via helm-controller |
| Learning curve | Lower for app teams, ops needs to plan projects/RBAC | Lower for platform teams comfortable with composition |
| Best fit | Manual gates, multi-tenant platform with UI expectations | Fully automated fleets, GitOps as a library of controllers |

Both are CNCF-graduated; the decision is organizational, not technical. Do not run both in the same cluster.

## Repository structures

| Structure | Shape | Tradeoffs |
|---|---|---|
| Environment dirs in one repo | `envs/{dev,staging,prod}/...` | Simplest; watch RBAC and review noise |
| App + env split | App repo has code and chart; config repo has env values | Clean ownership; two PRs per release |
| App-of-apps | One root Application pointing at child Applications | Bootstrap and grouping; can become a snowflake |
| ApplicationSet | Generator produces Applications from clusters, dirs, PRs | Scales multi-cluster; generators must be understood |
| Flux hierarchy | Root Kustomization -> infra -> apps, each with `dependsOn` | Explicit ordering; deep nesting is hard to debug |
| Per-team repos | Team owns its manifests; platform owns bootstrap | Strong tenancy; platform must standardize interfaces |

Conventions that prevent pain:

- One directory per environment; never one branch per environment. Branches diverge and defeat promotion.
- Keep rendered manifests out of Git unless you need auditability of the exact applied bytes; if you do render, do it in CI and commit the result to a clearly marked path.
- Cluster-specific configuration (domain, account IDs, regions) lives in the leaf env directory, not in shared templates.
- Bootstrap is code too: the root Application or Flux sync lives in a repo and is applied by a documented bootstrap procedure.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: api-prod
  namespace: argocd
spec:
  project: team-a
  source:
    repoURL: https://github.com/example/config.git
    targetRevision: main
    path: envs/prod/api
  destination:
    server: https://kubernetes.default.svc
    namespace: api
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: ["CreateNamespace=true", "ServerSideApply=true"]
```

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: { name: api, namespace: flux-system }
spec:
  interval: 10m
  sourceRef: { kind: GitRepository, name: config }
  path: ./envs/prod/api
  prune: true
  wait: true
  dependsOn: [{ name: infra }]
```

## Environment promotion

Promotion classes, from most to least desirable:

1. **PR-based promotion**: CI opens a PR that bumps the image digest or chart version in the next environment. Humans or policy approve. Best auditability; slightly slow.
2. **Automated promotion with gates**: a controller (Argo CD Image Updater, Renovate, Flux image automation) writes the bump, and policy plus health gates decide whether to continue.
3. **Release-branch promotion**: environment branches/tags; acceptable but watch drift between branches.
4. **Build-once per environment**: rebuilding for prod breaks artifact identity. Never.

Mechanics:

- Promote immutable references: image digest plus chart version. Tags can be moved; digests cannot.
- Keep environment differences in overlays (`kustomize`) or values files (Helm), not in duplicated manifests.
- Promotion should be a single commit across environments in order: dev -> staging -> prod.
- Record the source commit/build ID in annotations so any running workload traces back to code.
- Database migrations are their own pipeline step with backward-compatible sequencing; see `./06-iac.md` for infrastructure promotion parity.

## Drift detection and remediation

- **Argo CD**: automatic sync plus `selfHeal` corrects drift; `OutOfSync` diff view explains it. Turn on `ServerSideApply` for large CRDs. Set `ignoreDifferences` deliberately and narrowly (for example HPA-managed `replicas`), never wholesale.
- **Flux**: every Kustomization reconciles on an interval; drift is corrected on the next cycle. Use `--watch` style short intervals for critical namespaces and longer intervals elsewhere.
- Sources of legitimate drift: HPA replicas, cluster autoscaler, mutating admission webhooks (sidecars injected after apply), defaulting by controllers. Encode the exception once.
- Alert on drift that persists: an environment that continuously self-heals is hiding an uncontrolled mutation path.
- Never grant humans direct apply rights except documented break-glass; after break-glass, reconcile Git the same day.

## Secrets in GitOps

| Approach | How it works | Use when | Caveats |
|---|---|---|---|
| SOPS + age/KMS | Encrypt values in Git; controller decrypts | Monorepo-first teams; Flux native | Key distribution and rotation are on you |
| Sealed Secrets | Cluster controller public key encrypts | Single-cluster simplicity | Re-encrypt per cluster; rotation is awkward |
| External Secrets Operator | Git holds references; secrets live in Vault/Cloud SM | Multi-cluster, centralized rotation | Requires secret-store IAM design |
| Secrets Store CSI | Pods mount secrets from external store | Runtime injection without K8s Secret | Mount semantics differ per provider |
| Plain Sealed/encrypted with shared key in CI | Avoid | — | CI key becomes a universal secret |

Rules: no plaintext secrets in Git ever; encrypt at the leaf, not the root; scope encryption keys per environment; prefer external stores when rotation matters; audit who can read decrypted values.

## Progressive delivery

- **Argo Rollouts**: `Rollout` CRD replaces Deployment; canary steps, pauses, analysis templates querying Prometheus/Datadog; blue-green with preview services.
- **Flagger**: automates canary/blue-green for Deployments with either controller; uses service mesh or ingress traffic splitting.
- Gate promotion on service-level metrics from `./04-sre.md` (error rate, latency), not on pod readiness alone.
- Always define `abort` behavior and a maximum canary duration; a canary that never finishes is an incident with no owner.
- Supported split backends: service mesh (Istio/Linkerd), Gateway API, and ingress controllers. Plain ClusterIP alone cannot split traffic — pick a backend first.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata: { name: api }
spec:
  replicas: 5
  strategy:
    canary:
      steps:
        - setWeight: 10
        - pause: { duration: 5m }
        - setWeight: 50
        - pause: { duration: 10m }
      analysis:
        templates: [{ templateName: error-rate }]
        startingStep: 1
  selector: { matchLabels: { app: api } }
  template: { metadata: { labels: { app: api } }, spec: { containers: [{ name: api, image: api@sha256:REPLACE }] } }
```

## Multi-cluster and tenancy

- Choose a topology: hub with remote clusters (Argo CD) or self-managing clusters (Flux). Hybrid ("management cluster runs Argo CD, clusters run Flux") is common and adds a second control plane to operate.
- Cluster registration is code: Argo CD Secrets/ApplicationSets or Flux bootstrap manifests. Manual registration drifts.
- Use AppProjects / Flux tenancy (`--watch-label-selector` or per-namespace service accounts) to scope what each team's pipeline can touch.
- For cross-cluster promotion, keep ordering explicit: clusters with `dependsOn` or sync waves; never infer ordering from alphabetical names.
- Disaster recovery: the Git repo plus bootstrap is the recovery artifact. Test rebuilding a cluster from Git quarterly. If rebuild takes days, the platform is not GitOps.

## Anti-patterns

- Environment branches as the promotion mechanism.
- CI credentials with cluster-admin; push-based deploys mixed with pull reconciliation on the same resources.
- Committing rendered manifests and hand-editing them.
- Blanket `ignoreDifferences` to silence noisy diffs.
- Secrets encrypted with a key every developer holds.
- One giant Application per cluster with no ownership boundaries.
- Canary analysis on pod readiness only.
- No `prune` for years, then a prune-enabled sync deleting dozens of orphaned resources at once. Enable prune deliberately and review orphans regularly.

## Checklist

- [ ] Single source of truth per environment; no branch-based env promotion.
- [ ] Bootstrap documented and reproducible from an empty cluster.
- [ ] Promotion uses digests; environment diffs live in overlays/values.
- [ ] Drift alerts exist and `ignoreDifferences` entries have owners.
- [ ] Secrets strategy chosen; no plaintext in Git; rotation documented.
- [ ] Progressive delivery backend selected with analysis metrics.
- [ ] Sync waves/`dependsOn` encode ordering, including CRDs before CRs.
- [ ] RBAC: teams scoped to their projects/namespaces; break-glass audited.
- [ ] Cluster rebuild tested.
