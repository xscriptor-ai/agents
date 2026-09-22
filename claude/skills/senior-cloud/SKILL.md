---
name: senior-cloud
description: Cloud-native platform reference pack covering Kubernetes, GitOps, service
  mesh, SRE, serverless, infrastructure as code, multi-cloud, supply-chain security,
  and cost/platform engineering. Covers workloads, scheduling, networking, autoscaling,
  policy, upgrades, and debugging; Argo CD and Flux promotion flows; Istio ambient
  and Linkerd; SLI/SLO error budgets and incident practice; function and container
  serverless plus edge; OpenTofu, Terraform, Pulumi, and Crossplane; identity federation
  and data gravity; SLSA, sigstore, SBOMs, and admission control; and FinOps with
  internal developer platforms. Use when designing, reviewing, debugging, or operating
  cloud infrastructure; when choosing, migrating, or standardizing Kubernetes, GitOps,
  mesh, serverless, IaC, security, or cost tooling; or when defining promotion, reliability,
  hardening, or cost standards.
---

# Cloud

Read-only reference pack for cloud-native platform work in 2026: Kubernetes, GitOps, service mesh, SRE, serverless, infrastructure as code, multi-cloud, supply-chain security, and cost/platform engineering. Use it for decisions, review criteria, and operating procedures. Depth lives in `references/`; this file is the map.

The pack targets a fast-moving ecosystem, so it states floors and ranges instead of exact releases and marks uncertain items with "verify upstream". Nothing here is installation-specific: paths, ports, and tool names are examples, not mandates.

## How to use this pack

1. Match the task to a reference scope in the index below. Most tasks touch one or two references; design reviews often touch three or more.
2. Load references on demand. Never paste the whole pack into context.
3. Treat all versions as floors or ranges. The pack intentionally avoids exact patch versions; verify the current release upstream before pinning anything.
4. When a decision is cross-cutting (for example GitOps plus supply-chain security), load both references and reconcile their checklists instead of merging them mentally.

## Non-negotiable core rules

These hold regardless of cloud, tool, or team size. Violating one requires a written, time-boxed exception.

1. **Declarative and reconciled.** Desired state lives in version control; controllers converge reality. No imperative `kubectl`/console changes to production outside a break-glass procedure.
2. **Git is the source of truth for delivery.** If it is not in Git, it does not exist. Emergency changes are reverted into Git within one business day.
3. **Every workload declares requests, limits, and probes.** No bare pods in production. Pods without resource requests cause noisy-neighbor incidents and broken scheduling.
4. **Least privilege by default.** Workload identity, not static keys. Namespaced RBAC, no cluster-admin for applications, no long-lived cloud credentials in CI.
5. **Immutable, pinned artifacts.** Deploy by digest, not by floating tag. Never patch a running container or VM in place.
6. **Progressive delivery over big-bang.** Canary or blue/green for user-facing changes; automatic rollback on SLO regression.
7. **Layered policy and admission.** Prefer prevention at admission over detection after the fact. Policies are versioned and tested like code.
8. **Observability before scale.** Metrics, logs, and traces exist before a service takes production traffic; alerts page on symptoms, not causes.
9. **Backups and restores are tested.** An untested backup is not a backup. Restore drills are scheduled, not aspirational.
10. **Cost is a first-class requirement.** Every resource carries allocation labels; unit economics are reviewed alongside reliability.

## Decision tables

### Where should this workload run?

| Workload shape | Default | Consider instead | Avoid |
|---|---|---|---|
| Long-running HTTP/gRPC services, many services | Managed Kubernetes | Serverless containers for low ops | Functions for chatty internal APIs |
| Spiky, request-driven, per-request billing | Functions | Serverless containers if runtime limits bind | K8s for a single small API |
| Batch/queue consumers, minutes-scale | Serverless containers or Functions | K8s Jobs when GPU or long runtime needed | Long-lived VMs |
| Ultra-low-latency edge | Edge platform | Regional serverless containers + CDN | Functions with heavy cold starts |
| Stateful databases | Managed DB service | K8s operators only with deep expertise | Self-managed DB on shared nodes |

### Delivery tooling

| Need | Default | Alternative | Notes |
|---|---|---|---|
| Kubernetes delivery with UI and approvals | Argo CD | Flux | See `references/02-gitops.md` |
| Fully automated reconcile, minimal footprint | Flux | Argo CD | Both are CNCF-graduated |
| Progressive delivery | Argo Rollouts | Flagger | Works with either controller |
| Image promotion with policy gates | GitOps + supply chain | CI-only deploys | Never mix push deploys with pull reconcile |

### Networking

| Need | Default | Alternative | Notes |
|---|---|---|---|
| North-south HTTP routing | Gateway API | Ingress (legacy) | Gateway API is the forward path |
| mTLS and L7 policy across services | Linkerd or Istio ambient | Istio sidecar, Cilium | Match complexity to team capacity |
| Network policy and observability | Cilium | Calico | eBPF unlocks ambient-style modes |
| Multi-cluster east-west | Mesh multicluster | Cloud-native private networking | See `references/03-mesh-networking.md` |

### Infrastructure as code

| Need | Default | Alternative | Notes |
|---|---|---|---|
| Multi-cloud, mature ecosystem | OpenTofu | Terraform (BSL terms) | Verify license and registry paths upstream |
| General-purpose languages and rich testing | Pulumi | CDK | Best when app teams own infra |
| In-cluster self-service, Kubernetes-native | Crossplane | Terraform operators | Control plane owns provisioning |
| Regulated, plan-review-heavy workflow | HCL-based | Pulumi with policy | Plan artifacts must be reviewable |

## Reference index

| File | Scope | Load when |
|---|---|---|
| `references/01-kubernetes.md` | Workloads, scheduling, networking, autoscaling, resource and admission policy, upgrades, debugging | You deploy, size, expose, or diagnose anything on Kubernetes |
| `references/02-gitops.md` | Argo CD vs Flux, repo structures, promotion, drift, secrets in GitOps | You design or fix delivery pipelines and environment promotion |
| `references/03-mesh-networking.md` | Istio ambient vs sidecar, Linkerd, Gateway API, traffic shifting, mTLS, multi-cluster | You need service-to-service security, traffic control, or gateway design |
| `references/04-sre.md` | SLI/SLO/error budgets, toil, incident management, chaos, capacity | You define reliability targets, run incidents, or plan capacity |
| `references/05-serverless.md` | Function platforms, serverless containers, edge, cold starts, events, local dev, limits | You build or migrate event-driven or request-driven workloads without servers |
| `references/06-iac.md` | OpenTofu/Terraform/Pulumi/Crossplane, modules, state, policy, tests | You author, review, or migrate infrastructure definitions |
| `references/07-multicloud.md` | Networking, identity federation, data gravity, portability, exit strategy | You span two or more clouds or are planning an exit |
| `references/08-supply-chain-security.md` | SLSA, sigstore/cosign, SBOM, scanning, admission verification, hardening, secrets | You harden build and deploy pipelines or verify artifacts |
| `references/09-cost-platform-engineering.md` | FinOps, visibility and allocation, rightsizing, IDPs, golden paths | You reduce spend, allocate cost, or build a platform team offering |

## Cross-cutting review checklists

Before approving any platform change, confirm:

- [ ] Rollback path exists and was exercised in staging.
- [ ] Blast radius is understood: one namespace, one cluster, one region, or global.
- [ ] Requests/limits, PDBs, and probes are set for new workloads.
- [ ] Secrets are referenced, not embedded; rotation is documented.
- [ ] Artifacts are signed and admission policy accepts the signature.
- [ ] Observability: new metrics, dashboards, and alerts shipped with the change.
- [ ] Cost delta is estimated and labeled.
- [ ] Runbook updated for the failure modes the change introduces.

## Port

- **Port id** — `skill://senior/cloud` (version in `metadata.port-version`).
- **Kind** — read-only reference pack; no side effects, no tools required, no executables.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "cloud" })` in OpenCode; Claude Code reads `<skills-dir>/cloud/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers reference it as `load skill senior-cloud (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major. Content updates that do not change the interface bump minor or patch.
- **Degraded mode** — without the pack, agents fall back to their embedded platform guidance, state that the pack was unavailable, and must not invent version numbers, defaults, or APIs that only the pack would provide.
