# Multi-Cloud

> Scope: running across two or more clouds — networking, identity federation, data gravity, portability tradeoffs, and exit strategy.

## Why multi-cloud at all?

| Motivation | Genuine multi-cloud? | Better alternative |
|---|---|---|
| Regulatory requirement for a second provider | Yes | Region/sovereign-cloud variants of one provider may satisfy this |
| Resilience against provider-wide failure | Sometimes | Multi-region within one provider covers most realistic failures at lower cost |
| Best-of-breed services per domain | Yes, at integration cost | One cloud plus SaaS usually wins on total cost |
| Negotiation leverage | Rarely worth it alone | Real, but rarely justifies the engineering bill |
| M&A brought another cloud | Yes, temporarily | Set a consolidation deadline or a clear boundary |
| Avoiding lock-in for its own sake | No | Design exit options without operating two stacks |

The honest default: multi-cloud is a cost, not a feature. Adopt it for a decision that survives a five-year horizon, and write down which of the rows above is the real driver.

## Portability layers

| Layer | Portable option | Lock-in risk |
|---|---|---|
| Compute | Kubernetes, OCI containers, serverless containers | Managed add-ons (IAM, LB, autoscaling) differ |
| Networking | Gateway API, mesh, overlays | Load balancers, DNS, private connectivity are cloud-specific |
| Data | PostgreSQL/MySQL, Kafka-compatible, S3-compatible APIs | Managed extensions, replicas, and IAM bindings |
| Identity | OIDC, SPIFFE/SPIRE, OPA | IAM policy languages and role models |
| Observability | OpenTelemetry, Prometheus remote write | Vendor agents and query languages |
| IaC | OpenTofu/Terraform providers, Pulumi | Provider feature lag and defaults |
| Delivery | GitOps controllers | Managed GitOps services |

Standardize on the portable layer only where the abstraction cost is low. For data and identity, the abstraction usually leaks; accepting a per-cloud adapter is often cheaper than forcing uniformity.

## Networking

- Topology: hub-and-spoke per cloud, connected by a cross-cloud path. Keep the number of VPCs/VNets small; each one is a firewall policy, DNS zone, and quota surface.
- Connectivity options: provider interconnects (Direct Connect, ExpressRoute, Cloud Interconnect) for production, site-to-site VPN for low volume or backup, and SD-WAN/overlay vendors when you need a uniform policy plane. Cross-cloud traffic egresses; model the cost.
- DNS: own the public zones in one registrar/DNS provider with health-checked failover; keep private zones per cloud with clear forwarding rules. Avoid split-brain private DNS across clouds.
- CIDR planning is a first-class constraint: allocate non-overlapping supernets from a global IPAM before the second cloud exists. Retrofitting non-overlap after peering is painful.
- Service-to-service across clouds: prefer mesh/gateway federation or an API gateway as the boundary; never extend one cluster's pod network across clouds without a deliberate design.
- Egress and NAT: static egress IPs per cloud, private endpoints for cloud services, and a documented data path for every cross-cloud flow.

Reference architecture sketch:

```
Cloud A (primary)             Cloud B (secondary)
  hub VPC  <-> interconnect <->  hub VNet
    |                                |
  spokes (prod, nonprod)         spokes (DR, analytics)
    |                                |
  DNS zone A  <-> conditional forwarders / replicated zone  <-> DNS zone B
```

## Identity federation

- Human identity: one IdP (Okta, Entra ID, Google Workspace) federated to every cloud via SAML/OIDC and SCIM. No local cloud users except break-glass, which is monitored and rotated.
- Workload identity: each cloud's workload identity (IAM roles for service accounts, managed identities, service account impersonation) wins locally. Across clouds, federate:
  - OIDC trust between CI and each cloud (short-lived credentials, no static keys).
  - Workload identity federation so a workload in cloud A can assume a role in cloud B without a key.
  - SPIFFE/SPIRE when you need one cryptographic identity across clusters and clouds.
- Authorization: keep a single source of truth for group membership (the IdP) and map groups to per-cloud roles. Do not maintain parallel user lists.
- Break-glass: sealed, monitored, tested. Two-person rule for its use.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "accounts.google.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "accounts.google.com:aud": "REPLACE_CLIENT_ID" },
      "StringLike": { "accounts.google.com:sub": "system:serviceaccount:prod:api" }
    }
  }]
}
```

Sketch only: tighten `sub` matching, add `azp`/issuer conditions, and verify the current provider docs upstream.

## Data gravity

- Data is the heaviest asset: once terabytes and dependent analytics live in one cloud, compute follows the data, not the reverse.
- Costs of moving: egress fees, transfer time, dual-running during migration, and application rewrites. Estimate all four before promising a migration.
- Placement rules: keep data in the cloud where the majority of readers and writers run; replicate only derived or read-mostly datasets.
- Residency and sovereignty: map data classes to regions and clouds; some data must never leave a jurisdiction regardless of architecture elegance.
- Shared data services: a cross-cloud Kafka or object store can centralize data but adds a network dependency for every consumer. Choose it deliberately, not by default.
- Backups across clouds: cross-cloud backup copies are a strong ransomware and provider-failure control; verify restore times, encryption, and who can delete them.

## Operating model and fleet management

- Treat each cloud as a region of one platform: same golden paths, same pipelines, same policy, different adapters.
- Fleet inventory: one system of record for clusters, accounts/subscriptions/projects, owners, and criticality. Without it, multi-cloud becomes ungovernable.
- Configuration consistency: reconcile the same baseline (logging, policy agents, baseline network rules) everywhere via GitOps or IaC, with per-cloud exceptions explicit.
- Observability: one pane of glass with OpenTelemetry and a shared metrics backend; per-cloud exporters normalized to common labels (cloud, region, account, service).
- Cost: one allocation model across clouds with consistent labels and unit economics; see `./09-cost-platform-engineering.md`.
- On-call: one rotation that can operate every cloud. If nobody on-call can debug the secondary cloud, it is not a resilience asset; it is a liability.

## Exit strategy

Exit is a design property, not a project. Maintain it continuously:

1. **Classify workloads** by portability: portable (containers, standard protocols), adaptable (managed service with an open equivalent), and sticky (deep provider-specific integration). Keep sticky surface area intentional and small.
2. **Two-way doors**: prefer services with credible open equivalents (PostgreSQL, Kafka, S3 API, Kubernetes). Price the migration before adopting the sticky version.
3. **Data exportability**: verify you can extract data in a standard format at a known throughput and cost. Test a sample export yearly.
4. **Infrastructure parity**: keep the OpenTofu/Terraform layer capable of targeting a second provider for tier-1 services; even an untested plan surfaces hidden assumptions.
5. **DNS and traffic control**: own your DNS and TLS material so cutover does not require the incumbent's cooperation.
6. **People**: cross-train at least two engineers per cloud; a cloud only one person understands is a single point of failure.
7. **Decision triggers**: define what would trigger an exit (price change, reliability, compliance) and the pre-agreed first steps so the decision is not made in a crisis.

Portability budget rule: spend abstraction effort only up to the expected savings of the exit option it preserves. Perfect portability is a fantasy; credible exit in weeks for tier-1 services is a reasonable target.

## Common topologies

| Topology | Shape | Use when | Main risk |
|---|---|---|---|
| Primary + DR | One active cloud, one warm/cold standby | Provider-failure or regulatory resilience | DR rots untested; data replication lag |
| Cloud-per-domain | Each cloud owns distinct capabilities (for example analytics vs serving) | Best-of-breed with clear boundaries | Cross-cloud traffic and identity sprawl |
| Cloud-per-BU | Business units choose independently | Acquisition or autonomy | Duplicated platforms and skills |
| Active-active across clouds | Both serve production traffic | Extreme availability requirements | Data consistency and latency usually kill it |
| Cloud-per-environment | Non-prod in one, prod in another | Rare; cost arbitrage or sandboxing | Environment parity breaks in subtle ways |

Rules that apply to all of them:

- The data layer determines the real topology. Decide replication direction, consistency, and failover ownership before drawing compute.
- Failover must be exercised: run a documented drill at least twice a year with a measurable RTO/RPO result. A standby that has never taken traffic is a hypothesis, not a control.
- Keep the number of cross-cloud synchronous calls near zero; asynchronous replication and events travel better than request/response across providers.
- Define one system of record per data class. Two writable primaries for the same dataset is a conflict-resolution project disguised as an architecture.

## Migration playbook

When moving a workload between clouds:

1. Inventory dependencies: managed services, private endpoints, IAM bindings, DNS names, and license/contract constraints.
2. Classify each dependency as portable, adaptable, or sticky (see the exit-strategy section), then estimate migration cost per class.
3. Build the target with IaC from day one and deploy the same artifact by digest (`./08-supply-chain-security.md`).
4. Run dual-write or replica-based data migration with verification jobs comparing counts and checksums.
5. Shadow traffic to the target where feasible; compare responses before shifting any users.
6. Cut over with DNS plus a rollback window; keep the source writable-but-frozen long enough to revert.
7. Decommission deliberately: delete credentials, DNS, and network paths so the old path cannot silently attract traffic.
8. Update runbooks, on-call training, and cost allocation in the same change window as the cutover.

## Anti-patterns

- Multi-cloud for resume value or negotiation without a workload-level reason.
- Lowest-common-denominator services that lose the reliability and features that made each cloud useful.
- Separate tooling, pipelines, and identities per cloud with no shared golden path.
- Lifting a VM-based architecture unchanged and calling it multi-cloud.
- Assuming a second cloud gives active-active by default; the data layer usually remains single-cloud and defines the real availability.
- No CIDR plan, followed by overlapping networks that block peering.
- Cross-cloud keys in CI configs instead of federation.
- A secondary cloud that nobody tests; it silently rots until the day it is needed.

## Checklist

- [ ] Written driver for multi-cloud; cost and benefit signed off.
- [ ] Global CIDR/IPAM allocation before the second cloud is built.
- [ ] Cross-cloud connectivity with documented data paths and costs.
- [ ] Single human IdP with federation; break-glass monitored and tested.
- [ ] Workload identity federation everywhere; no static cross-cloud keys.
- [ ] Data classification, residency, and cross-cloud backup verified with restore tests.
- [ ] Common baseline applied by GitOps/IaC; exceptions documented.
- [ ] One observability stack and one on-call rotation covering all clouds.
- [ ] Portability classification per workload; exit plan and triggers documented.
