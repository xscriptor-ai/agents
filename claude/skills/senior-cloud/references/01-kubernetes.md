# Kubernetes

> Scope: workloads, scheduling, networking, autoscaling, resource and admission policy, upgrades, and debugging for current Kubernetes clusters.

## Version and support policy

- Upstream supports roughly the three most recent minor releases; managed offerings (EKS, GKE, AKS, and equivalents) track their own windows and often lag or lead by a minor. Pin clusters to a supported minor and upgrade at least every two minors so you never face a forced multi-minor jump. Verify the current supported set upstream before planning.
- Version skew: kubelet and kube-proxy may be older than the API server; `kubectl` should be within one minor of the cluster. Skew bounds relax slowly; check the current policy upstream.
- Feature lifecycle: do not build production dependencies on alpha APIs. Beta APIs can still change shape. Many capabilities that were once feature-gated are now on by default (Pod Security Admission, Gateway API core, `ValidatingAdmissionPolicy` CEL-based validation). Confirm graduation status per minor upstream.

## Workload primitives

| Primitive | Use for | Avoid when |
|---|---|---|
| Deployment | Stateless HTTP/gRPC workers, rolling updates | Ordered identity or stable storage needed |
| StatefulSet | Databases, queues, anything needing stable network ID or per-replica PVCs | Stateless workloads (headless service overhead is pointless) |
| DaemonSet | Per-node agents: CNI, CSI, log shippers, node exporters | You only want one replica total |
| Job | Run-to-completion batch, migrations | Long-lived processes |
| CronJob | Scheduled batch | Sub-minute schedules or jobs longer than the interval |
| ReplicaSet | Managed by Deployments only | Direct use (no rollout strategy) |
| Bare Pod | Debugging only | Production (no self-healing, no rollout) |

Set `startingDeadlineSeconds` and `concurrencyPolicy` on CronJobs; overlapping jobs are the default and a common source of duplicate work.

## Pod design rules

- Always set CPU and memory requests. Set limits for memory; be careful with CPU limits (throttling) — many teams drop CPU limits for latency-sensitive services and rely on requests plus namespace quotas. Document the choice.
- QoS classes: **Guaranteed** (requests equal limits) for latency-critical, **Burstable** for most, **BestEffort** never in production.
- Probes: use `startupProbe` for slow boot, `readinessProbe` for traffic gating, `livenessProbe` only for true deadlock detection. Never make liveness depend on a downstream dependency; that turns a partial outage into a restart storm.
- Handle `SIGTERM`: stop accepting new work, drain in-flight requests, exit before `terminationGracePeriodSeconds`. Add a `preStop` sleep when the service was just removed from endpoints.
- Security context baseline: `runAsNonRoot: true`, `seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities.drop: ["ALL"]`.
- Spread replicas with `topologySpreadConstraints` (`maxSkew: 1`, `whenUnsatisfiable: DoNotSchedule`) across zones and nodes. Prefer it over required pod anti-affinity, which is rigid and scheduler-expensive at scale.
- Attach a PodDisruptionBudget to every multi-replica service; without one, node drains can take all replicas at once.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 3
  selector:
    matchLabels: { app: api }
  template:
    metadata:
      labels: { app: api }
    spec:
      securityContext:
        runAsNonRoot: true
        seccompProfile: { type: RuntimeDefault }
      containers:
        - name: api
          image: registry.example.com/api@sha256:REPLACE_WITH_DIGEST
          ports: [{ containerPort: 8080 }]
          resources:
            requests: { cpu: 200m, memory: 256Mi }
            limits: { memory: 512Mi }
          readinessProbe:
            httpGet: { path: /readyz, port: 8080 }
          livenessProbe:
            httpGet: { path: /healthz, port: 8080 }
            periodSeconds: 10
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: { drop: ["ALL"] }
```

## Scheduling

- Order of decisions: node selector/affinity narrows candidates; taints and tolerations filter; topology spread balances; priority and preemption resolve contention.
- `nodeAffinity` required rules exclude nodes permanently — good for architecture (arm64, GPU) but brittle for soft preferences. Use `preferredDuringSchedulingIgnoredDuringExecution` for preferences.
- Taints keep workloads off nodes: `NoSchedule` for dedicated pools (GPU, spot, ingress), `NoExecute` for eviction on node problems. Tolerate only what is necessary; blanket tolerations defeat the point.
- Use `PriorityClass` so critical system components win under pressure. Do not assign `system-cluster-critical` to user workloads.
- Node provisioning: **Karpenter** (NodePools/NodeClaims, just-in-time instances, consolidation, spot) is the common choice on AWS and expanding elsewhere; **Cluster Autoscaler** remains viable for mixed environments. Configure consolidation carefully — aggressive consolidation causes churn for long-running jobs.
- Use the **descheduler** or Karpenter drift/consolidation to rebalance after traffic shifts, not as a first-line scheduler fix.
- Avoid fragmentation: standardize a few instance shapes and keep headroom per zone to absorb failures.

## Networking

- CNI: **Cilium** (eBPF dataplane, network policy, Hubble observability, service mesh modes) and **Calico** are the mainstream self-managed choices; cloud CNIs are fine but often lack rich policy. NetworkPolicy support is table stakes — verify enforcement, not just API acceptance.
- Services: `ClusterIP` for internal, headless for StatefulSets, `NodePort` for dev only, `LoadBalancer` with cloud annotations for external. Enable `internalTrafficPolicy: Local` when you want node-local routing and lower latency.
- DNS: CoreDNS scales with cluster size; `ndots: 5` causes upstream search-path queries — use fully qualified names with a trailing dot (`api.prod.svc.cluster.local.`) or lower `ndots` for hot paths. NodeLocal DNSCache reduces conntrack pressure on large clusters.
- North-south: **Gateway API** is the forward-looking standard (`GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`, `TCPRoute`); Ingress v1 is stable but feature-frozen. Use one gateway implementation per cluster where possible and attach certs via `cert-manager` or cloud certificate services.
- Egress: control and audit outbound traffic with explicit egress gateways or static egress IPs; NAT gateway costs scale with data volume, so route private traffic over VPC endpoints/private service connect.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: prod }
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
```

Then add explicit allow policies for DNS egress and required peers; default-deny without a DNS allow rule is the most common self-inflicted outage.

## Autoscaling

| Layer | Tool | Scales on | Notes |
|---|---|---|---|
| Pod replicas | HPA | CPU, memory, custom, external | Stabilization windows prevent flapping |
| Pod resources | VPA | Historical usage | Run in recommendation mode in production unless auto updates are proven |
| Pod replicas (events) | KEDA | Queue depth, lag, cron, any event source | Enables scale-to-zero with request buffering |
| Nodes | Karpenter / Cluster Autoscaler | Pending pods, utilization | Pair with PDBs and topology spread |
| Cluster-proportional | CPA | Cluster size | For DNS, ingress, and similar per-cluster controllers |

- HPA formula: `desiredReplicas = ceil(currentReplicas * currentMetricValue / targetMetricValue)`. Always set `behavior.scaleDown.stabilizationWindowSeconds` (for example 300s) to avoid churn.
- Do not point HPA and VPA at the same metric; VPA also fights memory-based HPA. Split: HPA on requests-per-second or queue depth, VPA on resources.
- Scale-to-zero on Kubernetes requires a buffer (KEDA HTTP add-on, Knative, or your own queue) — otherwise the user pays the cold-start latency. See `./05-serverless.md` for cold-start tradeoffs.
- Node scale-down requires PDBs to be honored; pod-level PDBs plus `empty` budget handling can block consolidation and silently raise cost.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: api }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: api }
  minReplicas: 3
  maxReplicas: 30
  behavior:
    scaleDown: { stabilizationWindowSeconds: 300 }
  metrics:
    - type: Resource
      resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } }
```

## Resource management and policy

- **ResourceQuota** caps a namespace's total requests/limits and object counts. Pair it with **LimitRange** defaults so pods that omit requests still get sane values instead of blocking on quota.
- **PodDisruptionBudget**: `minAvailable` percentages scale better than integers for replica counts that change; understand that PDBs only cover voluntary disruptions (drains, upgrades), not crashes.
- **Admission order**: mutating webhooks first, then validating. Keep webhook `timeoutSeconds` short (for example 5-10s), scope `rules` narrowly, and use `failurePolicy: Ignore` only for non-security-critical policies — `Fail` on a broad rule can lock out the whole cluster if the webhook goes down.
- Policy engines: **Pod Security Admission** labels namespaces (`enforce: restricted`, `audit`, `warn`) and needs no extra components; **Kyverno** is Kubernetes-native YAML policies; **Gatekeeper/OPA** suits organizations already invested in Rego. **ValidatingAdmissionPolicy** with CEL covers simple invariants without a webhook.
- With GitOps, never hand-write policy exceptions: policy exceptions are code, reviewed and expiring. See `./08-supply-chain-security.md` for image verification policies.

## Upgrades

1. Read the release notes for every minor you cross; check removed APIs (`kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis`, Pluto, or similar scanners).
2. Upgrade staging with production-like add-ons first; run conformance or smoke suites.
3. Upgrade the control plane (managed: one click/API; self-managed: one minor at a time, never skip).
4. Upgrade nodes with surge capacity: add new nodes, cordon and drain old ones, respect PDBs, then remove. Blue/green node pools are the safest pattern.
5. Upgrade add-ons in dependency order: CNI, CSI, DNS, metrics, ingress/gateway, policy, mesh, autoscaler.
6. Watch for 24-48h after; keep the previous node pool available for rollback until confident.
7. Control plane rollback is generally unsupported upstream — the real rollback is rebuilding or restoring the previous version deliberately. Test that path.

## Debugging playbook

| Symptom | Likely cause | Check |
|---|---|---|
| Pending | Insufficient resources, taints, affinity, PVC unbound | `kubectl describe pod` events, quota, node capacity |
| ImagePullBackOff | Missing imagePullSecret, wrong digest, rate limit | Events, node network, registry creds |
| CrashLoopBackOff | App error, bad config, failing liveness | `kubectl logs --previous`, config mounts |
| OOMKilled | Memory limit too low or leak | `kubectl top pod`, memory profile |
| Evicted | Node disk/memory pressure | Node conditions, ephemeral storage usage |
| Readiness never true | Probe misconfigured, slow dependency | Probe command, endpoint state |
| DNS failures | CoreDNS overload, NetworkPolicy, conntrack | DNS test pod, CoreDNS metrics |
| Stuck Terminating | Finalizer, volume detach, unresponsive kubelet | `kubectl get pod -o yaml` finalizers |

- Reach for `kubectl debug` (ephemeral containers) before SSH; nodes should be immutable.
- `kubectl get events --sort-by=.lastTimestamp` and `kubectl describe` cover most first-pass diagnosis.
- For control-plane issues, check admission webhooks first: a hung or failing webhook presents as broad API timeouts.

## Anti-patterns

- Bare pods, or Deployments without probes and requests.
- `latest` image tags and no digest pinning.
- One giant namespace shared by unrelated teams with cluster-admin service accounts.
- Liveness probes that call downstream services.
- `hostPath` mounts, privileged containers, and `hostNetwork` without a documented reason.
- CPU limits on every latency-sensitive service causing throttling during bursts.
- PDB with `minAvailable: 0` (renders it useless) or `maxUnavailable: 0` (blocks all drains).
- Ad-hoc `kubectl apply` against production outside GitOps.

## Checklist

- [ ] All workloads have requests, appropriate limits, and probes.
- [ ] Replicas >= 2 with topology spread across zones; PDBs attached.
- [ ] Namespace labels enforce Pod Security Admission at `restricted` (or documented exception).
- [ ] NetworkPolicy default-deny plus explicit DNS and peer allows.
- [ ] Images pinned by digest; admission verifies signatures (`./08-supply-chain-security.md`).
- [ ] Quota and LimitRange set per namespace.
- [ ] Autoscaling configured with stabilization and sane min/max.
- [ ] Upgrade path tested in staging, including add-on order.
- [ ] Runbooks exist for the top failure modes above.
