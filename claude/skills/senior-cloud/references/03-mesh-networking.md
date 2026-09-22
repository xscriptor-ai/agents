# Service Mesh and Networking

> Scope: east-west and north-south service networking — Istio ambient and sidecar, Linkerd, Cilium, Gateway API, mTLS, traffic shifting, and multi-cluster.

## Do you need a mesh?

| Requirement | Mesh needed? | Reasonable default |
|---|---|---|
| Encrypt all service-to-service traffic (zero trust) | Yes | Istio ambient or Linkerd |
| Per-route retries, timeouts, circuit breaking | Yes (or gateway-only) | Mesh, or Gateway API at the edge for north-south |
| Canary traffic splitting inside the cluster | Yes | Mesh or a service-mesh-capable ingress |
| Network policy and flow observability only | No | Cilium NetworkPolicy + Hubble |
| A handful of services on one cluster | No | Ingress/Gateway plus app-level libraries |
| Compliance requiring cryptographic workload identity | Yes | SPIFFE-based mesh (Istio/Linkerd) |

Default posture: run a mesh when you have more than roughly a dozen services or a hard mTLS requirement; otherwise the operational overhead outweighs the benefit. Avoid running two meshes or a mesh plus per-app service discovery libraries with overlapping responsibilities.

## Data plane models

| Model | How traffic is intercepted | Cost | Fits |
|---|---|---|---|
| Sidecar proxy (Envoy per pod) | iptables redirect per pod | Per-pod memory/CPU; restarts per upgrade | Maximum features and maturity; existing Istio fleets |
| Ambient (ztunnel per node + waypoint per namespace/service) | eBPF plus node-level proxy for L4; optional L7 waypoints | Lower overhead; no pod restarts for L4 | New Istio installs; teams wanting mTLS without sidecar tax |
| eBPF mesh (Cilium) | Kernel-level, no user-space proxy for L4 | Lowest overhead | Teams already on Cilium wanting policy plus L4 identity |
| Lightweight Rust/proxy (Linkerd) | Sidecar with micro-proxy | Low per-pod overhead | Simplicity-focused teams; stable L7 feature set |

Istio ambient mode is GA in recent releases (verify upstream) and is the recommended greenfield Istio mode; sidecar mode remains fully supported and is still the choice when you need L7 features on every pod without waypoint management.

## Istio

- Components: `istiod` (control plane), ztunnel (ambient L4), waypoints (ambient L7), gateways (north-south). Use the `istioctl` CLI for install, analyze, and proxy debugging.
- Installation: prefer the official Helm charts or the operator in a dedicated `istio-system` namespace; pin the minor version and use revision-based upgrades (install new revision, migrate, remove old).
- `PeerAuthentication` sets mTLS mode per mesh/namespace/workload; set `STRICT` mesh-wide only after non-mesh traffic is handled, or use `PERMISSIVE` during migration. `DestinationRule` with `ISTIO_MUTUAL` is needed on the client side for sidecar mode.
- Authorization: `AuthorizationPolicy` works on identity (service account) and L7 attributes in sidecar mode and at waypoints. Default-deny plus explicit allows mirrors NetworkPolicy design.
- Ingress/egress: use one Gateway implementation (Istio Gateway or Gateway API) per cluster. Duplicated ingress paths across istio-ingressgateway and a second ingress controller are a top source of 502s and stale DNS.
- Traffic shifting: `VirtualService` weights or Gateway API `HTTPRoute` weights; see the snippet below. Prefer Gateway API for new north-south routes, VirtualService for sidecar-era east-west routing.

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata: { name: default, namespace: prod }
spec:
  mtls: { mode: STRICT }
```

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: api, namespace: prod }
spec:
  parentRefs: [{ name: prod-gateway }]
  hostnames: ["api.example.com"]
  rules:
    - backendRefs:
        - { name: api-v1, port: 80, weight: 90 }
        - { name: api-v2, port: 80, weight: 10 }
```

## Linkerd

- Choose Linkerd for a small operational surface: a Rust micro-proxy, automatic mTLS on by default, and a stable feature set. It does not attempt to replace your gateway or provide Envoy extensibility.
- Install via the CLI/Helm; inject by namespace annotation or per-workload annotation. Verify with `linkerd check` and watch success rate via `linkerd viz`.
- Linkerd supports Gateway API `HTTPRoute` for traffic splitting when configured with its gateway; otherwise use HTTPRoute attached to your existing gateway and let Linkerd handle identity and observability.
- Multicluster: gateway-based linking between clusters; services remain addressable across clusters with mTLS.
- Tradeoff: no WASM filters or EnvoyFilter escape hatch. If you need deep L7 customization, that is an Istio/Envoy argument, not a Linkerd one.

## Cilium

- eBPF dataplane provides NetworkPolicy (including L7 via Envoy where needed), transparent encryption (WireGuard/IPsec), and Hubble flow visibility.
- Cilium service mesh features cover L4 identity-based policy and, with `CiliumEnvoyConfig`, L7 routing. This is not a drop-in replacement for a full L7 mesh; it is the right answer when you want policy plus encryption plus observability with minimum latency.
- Use Hubble for flow-level debugging: `hubble observe --namespace prod --verdict DROPPED` answers "why can't A reach B" faster than most mesh tooling.
- Gateway API support exists for ingress; verify feature maturity for your version upstream.

## Gateway API

- Core resources: `GatewayClass` (infrastructure), `Gateway` (listener + TLS), `HTTPRoute`/`GRPCRoute` (routing rules). Stable channel covers the core; experimental channel adds TCP/UDP/TLS routes and more.
- One Gateway per cluster or per tenant; routes attach via `parentRefs` with optional section names. This separation lets platform teams own listeners and app teams own routes.
- Migration from Ingress: map host/path rules to HTTPRoute, annotations to policy attachments or implementation-specific resources. Keep both only during a bounded migration window.
- GAMMA (Gateway API for Mesh) is the emerging east-west standard; adoption varies by mesh. Verify support upstream before standardizing on it.
- TLS: terminate at the gateway with cert-manager or cloud certificates; for passthrough, use TLSRoute with SNI. Redirect HTTP to HTTPS at the gateway, not in every app.

## Traffic management and resilience

- Timeouts and retries belong at one layer. If the mesh retries and the app retries and the client retries, you get retry storms. Set mesh retries small (1-2) with budget, and disable app-level retries on idempotent-safe paths.
- Circuit breaking: Envoy `outlierDetection` (sidecar) or route-level policies; eject unhealthy hosts and let them recover. Without outlier detection, one bad pod absorbs traffic until a human notices.
- Load balancing: default round-robin is fine for most; locality-aware routing (`localityLbSetting`) reduces cross-zone cost and latency. See `./09-cost-platform-engineering.md` for the cost angle.
- Rate limiting: apply at the gateway for external traffic and in the mesh for internal abuse; a shared Redis-backed limiter beats per-pod limits that multiply with replicas.
- Health checks and retries must agree: a mesh retry after the app has already timed out doubles load on a struggling dependency.

## Multi-cluster

- Options: single mesh across clusters (Istio multicluster primary-remote, Linkerd multicluster links), or gateway-to-gateway federation (east-west gateways), or no mesh with cloud private networking.
- Requirements before multi-cluster traffic: shared trust (same root CA or federated trust bundles), unique cluster/network identities, non-overlapping pod/service CIDRs, and DNS resolution across clusters.
- Failure modes: partial connectivity partitions, trust-bundle rotation breaking links silently, and version skew between clusters. Test link failure and trust rotation deliberately.
- Keep the blast radius explicit: multi-cluster east-west is usually for a small set of services, not the whole mesh.

## Gateway operations

- TLS: terminate with cert-manager (ACME for public certs, internal CA for private) or cloud certificate services. Rotate certificates automatically; monitor expiry as an SLI because an expired gateway cert takes down everything behind it.
- Listeners: one Gateway per environment is usually enough. Separate listeners by port/protocol; use `allowedRoutes` to control which namespaces may attach routes (Same vs All).
- Timeouts belong on the route or listener where the client behavior is defined; keep backend timeouts longer than gateway timeouts so the gateway gives up first and returns a clean 504 instead of a hanging connection.
- Header and path rewrites: do them at the gateway, not in every application. Keep one canonical scheme-to-host mapping documented; shadow routes (duplicate hostnames across gateways/ingress) are a leading cause of intermittent 404s.
- External DNS and health checks: automate DNS records from Gateway/Service annotations where your platform supports it; health-check the gateway from outside the cluster so a bad listener is detected before users report it.
- Rate limiting and WAF: apply coarse protection at the edge (CDN/WAF) and identity-aware limits at the gateway. A mesh is not a WAF.

## Mesh upgrade and operations

- Control plane upgrades: install the new revision alongside the old, migrate namespaces by relabeling, verify, then remove the old revision. Never upgrade the control plane and data plane in one uncontrolled step.
- Sidecar-mode upgrades restart pods; schedule them with PDBs and surge capacity the same way you would a deployment rollout.
- Ambient upgrades touch ztunnel (node-level) and waypoints; node drains rolling ztunnels cause brief L4 reconnection for pods on that node — plan for it.
- Configuration hygiene: run `istioctl analyze` (or the Linkerd equivalent) in CI against rendered manifests; catch misapplied AuthorizationPolicies before they lock out a namespace.
- Keep a known-good rollback revision and the previous chart values in Git so a failed upgrade is one revert away. See `./02-gitops.md`.

## Observability

| Layer | Istio | Linkerd | Cilium |
|---|---|---|---|
| Metrics | Prometheus, Kiali | Prometheus, `linkerd viz` | Prometheus, Hubble |
| Traces | Envoy/OpenTelemetry integration | OpenTelemetry integration | Hubble plus OTel |
| Flow logs | Access logs per proxy | `linkerd viz tap` | `hubble observe` |
| Topology | Kiali graph | `linkerd viz` graph | Hubble UI |

Instrument at the mesh for service-to-service RED metrics, but keep application-level traces for business context. See the sibling observability pack for metric and alert design.

## Traffic capture and debugging

- Start with identity: `istioctl proxy-config` (clusters, listeners, routes) for sidecars and waypoints; `linkerd viz tap` and `hubble observe` for live flows.
- To answer "is mTLS actually on?", check the peer identity in proxy stats/metrics rather than trusting configuration; configuration can be accepted but not enforced due to mesh/namespace scope or revision mismatch.
- Packet-level debugging is a last resort: capture inside the proxy/netns (`kubectl debug` plus `tcpdump`) rather than on the host, and remember encrypted traffic shows nothing useful.
- The three most common mesh incidents: a route attached to the wrong gateway/listener; an AuthorizationPolicy applied to the wrong workload selectors; and a control plane/data plane version mismatch after a partial upgrade.
- Keep a synthetic canary (one client calling one server every minute) whose result is exported to your monitoring; it distinguishes "mesh broken" from "app broken" within seconds.
- Log levels: raise proxy logging only for the namespace under investigation, with a time limit and a cleanup commit; global debug logging in Envoy can generate gigabytes per hour.

## Anti-patterns

- Enabling a mesh before a single team understands its failure modes and debugging commands.
- STRICT mTLS flipped before every client is injected; the resulting connection failures get misdiagnosed as app bugs.
- Layering mesh retries, gateway retries, and application retries on the same call path.
- Running two ingress controllers for the same hostnames.
- Sidecar injection on Jobs and batch workloads where overhead and restart semantics hurt.
- Using a mesh as a substitute for NetworkPolicy in clusters where enforcement is already available natively.
- Ignoring control plane version skew during mesh upgrades.

## Checklist

- [ ] Mesh justified against the decision table above.
- [ ] One data plane model chosen (ambient, sidecar, or eBPF); no mixed-mode without a migration plan.
- [ ] mTLS rollout staged with visibility before enforcement.
- [ ] Authorization default-deny with explicit allows per service.
- [ ] Gateway API (or one gateway implementation) owns north-south; no overlapping hostnames.
- [ ] Retry/timeout policy assigned to exactly one layer.
- [ ] Outlier detection or equivalent ejection configured for critical paths.
- [ ] Upgrade procedure tested in a non-production cluster, including trust-bundle rotation.
- [ ] Debugging runbook exists (`istioctl analyze`, `linkerd check`, `hubble observe`).
