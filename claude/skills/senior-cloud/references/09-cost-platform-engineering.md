# Cost and Platform Engineering

> Scope: FinOps practice, cost visibility and allocation, rightsizing, and internal developer platforms with golden paths.

## FinOps operating model

Three phases, run continuously rather than as a project:

| Phase | Question | Activities | Artifacts |
|---|---|---|---|
| Inform | What are we spending and why? | Tagging, allocation, showback, unit economics | Dashboards, reports by team/service |
| Optimize | Where can we spend less for the same outcome? | Rightsizing, commitments, storage lifecycle, waste removal | Savings backlog |
| Operate | How do we keep it that way? | Budgets, anomaly detection, policy, reviews, incentives | Guardrails, reviews, targets |

Personas: engineering owns usage decisions, finance owns accounting and forecast, product owns unit economics targets, platform owns tooling and guardrails. No single team "does FinOps" alone.

Rules that make the program real:

- Cost is discussed in engineering terms: per service, per environment, per customer, per request.
- Every optimization has an owner and an SLO impact check before and after.
- Savings targets are set as a percentage of addressable spend, not a round number invented by finance.
- Cost anomalies page or ticket the owning team, not the platform team.

## Visibility and allocation

- Native sources of truth: AWS Cost and Usage Report (CUR) or Cost Explorer, GCP billing export to BigQuery, Azure Cost Management exports. Build one normalized table with account/subscription/project, service, region, and your label dimensions.
- Kubernetes: OpenCost and Kubecost translate pod usage into cost by namespace, workload, and label using cloud pricing plus overhead split. Run one of them per cluster and federate to the central report.
- Label schema (enforce with policy; see `./06-iac.md`):

| Label | Example values | Required |
|---|---|---|
| `app` / `service` | checkout, search | Yes |
| `owner` or `team` | team-payments | Yes |
| `env` | dev, staging, prod | Yes |
| `cost-center` | cc-1234 | Yes |
| `component` | api, worker, cache | Recommended |
| `managed-by` | gitops, tofu | Recommended |

- Showback first: publish accurate per-team cost for one quarter before charging anyone. Chargeback without trust produces arguments, not savings.
- Shared costs (ingress, DNS, observability, CI, control planes) have a written allocation rule: proportional to usage where measurable, equal split otherwise, reviewed quarterly.
- Unit economics: `cost per order`, `cost per active tenant`, `cost per 1k requests`. Track the ratio month over month; absolute spend growth means little without the denominator.
- Budgets and forecasts: per team and per environment, with alerts at 80%/100% of monthly budget and a forecast that flags end-of-month overruns by mid-month.
- Anomaly detection: daily cost-change alerts above a threshold against the trailing baseline, routed to the owner label.

## Rightsizing

- The core problem: requests are set once at launch and never revisited, so the scheduler reserves capacity nobody uses. Target 60-80% average utilization on the reserved footprint for stateless services.
- Process: collect 2-4 weeks of usage, set requests near p95 (plus margin), set limits to protect the node, re-measure monthly. Do it service by service; batch it with active owners.
- Tools: VPA in recommendation mode (never auto in production until proven), Goldilocks dashboards, cloud native rightsizing recommendations, and `kubectl top` for spot checks.
- Honor the QoS consequence: moving from Guaranteed to Burstable saves capacity but changes eviction order; critical services keep Guaranteed or explicit priorities.
- Instance and architecture mix: latest generation and arm64 often give 20-40% better price/performance; validate with the same load test before switching. See `./04-sre.md` for the load-test discipline.
- Spot/preemptible for stateless, fault-tolerant work: workers, batch, CI, some ingress. Never for stateful or single-replica critical services. Handle interruption notices and diversify instance types.
- Storage lifecycle: tier to infrequent/cold/archive by access pattern, snapshot before delete, set retention policies, and delete orphaned volumes and snapshots monthly.
- Commitments (savings plans, reserved instances, committed use discounts): cover the stable baseline, not the peaks. Model before buying; unused commitments are worse than on-demand.

Waste checklist to sweep monthly:

- Idle load balancers, NAT gateways in unused AZs, unattached IPs and volumes.
- Non-production environments running 24/7 and oversized dev databases.
- Orphaned snapshots, old AMIs/images, log buckets without lifecycle rules.
- Kubernetes namespaces with zero traffic but running replicas.
- Duplicated observability data (high-cardinality metrics nobody queries) and verbose logs shipped twice.
- Container registries, CI caches, and artifact stores growing without retention policies.
- Cross-AZ and cross-region data transfer from chatty designs (`./03-mesh-networking.md` locality routing helps).

## Internal developer platforms (IDPs)

An IDP is a product, not a portal. Its job: reduce cognitive load and make the paved path the fastest path.

| Component | Examples | Purpose |
|---|---|---|
| Service catalog | Backstage, Port, OpsLevel | Inventory, ownership, scorecards |
| Golden paths / templates | Scaffolding with CI, CD, observability pre-wired | New service to production in hours, not weeks |
| Self-service infra | Crossplane, platform APIs, Terraform modules, environment requests | No tickets for routine provisioning |
| Delivery | GitOps controllers, pipelines | Consistent promotion (see `./02-gitops.md`) |
| Guardrails | Policy engines, quotas, admission | Safe defaults and enforcement |
| Docs | Reference + how-to by task | Reduce tribal knowledge |

Design principles:

- Treat developers as customers: interview them, measure time-to-first-deploy, adoption, and satisfaction.
- Golden paths are opinionated and maintained; they are not the only path, but leaving them must cost something explicit.
- Every template ships production-ready: health endpoints, metrics, structured logs, tracing, dashboards, alerts, security baseline, ownership metadata.
- Self-service with guardrails beats approvals. Approvals are reserved for irreversible or expensive actions.
- Measure adoption and outcome: percentage of services on the path, deployment frequency, change failure rate, MTTR, and time from commit to production (the DORA set).
- Deprecate templates explicitly with migration guides; unmaintained scaffolding is worse than none.
- Scorecards drive hygiene (has SLO, has owner, has on-call, no critical CVEs, uses golden CI) with visibility rather than punishment first.

## Platform team operating rhythm

| Cadence | Activity | Output |
|---|---|---|
| Weekly | Cost anomaly review, savings backlog grooming | Assigned actions |
| Monthly | Rightsizing sweep, waste sweep, adoption review | Changes applied, metrics |
| Quarterly | Commitments review, allocation rule review, roadmap with users | Forecasts, priorities |
| Quarterly | DR/restore and exit-path checks (`./07-multicloud.md`) | Tested procedures |

## Cost-aware architecture patterns

- Prefer scale-to-zero for non-production and bursty workloads; a staging environment that sleeps outside business hours is often the single largest quick win.
- Locality: keep chatty services in one zone, use topology-aware routing, and avoid cross-region synchronous calls. Cross-AZ traffic is cheap relative to latency and failure risk; cross-region is neither.
- Caching and CDN change the unit economics more than instance tuning: a well-cached read path can cut origin compute by an order of magnitude. Always measure hit ratio as a cost metric.
- Data: compress at rest, choose the right storage class, partition to prune scans, and avoid duplicating datasets across layers (raw, staged, curated) without lifecycle rules.
- Async where the user does not wait: queues absorb bursts and let workers run on cheaper interruptible capacity.
- Batching beats per-request overhead for analytics and ML jobs; a nightly batch on spot can cost a fraction of a real-time cluster.
- Serverless vs Kubernetes crossover: model break-even at sustained utilization; below it, serverless usually wins once you price the platform team. See `./05-serverless.md` and `./04-sre.md` for headroom costs.

## Platform metrics that matter

- **Adoption**: share of services created from golden paths; share of services with complete ownership metadata.
- **Flow**: time to first deploy for a new service; lead time from merge to production; deployment frequency; change failure rate; MTTR. Publish per team where it helps, never as a leaderboard for blame.
- **Reliability of the platform itself**: internal SLOs for CI, artifact registry, GitOps reconciliation, and self-service APIs. When the platform breaks, every product team stops.
- **Cost of the platform**: platform spend per developer or per service, reported like any other unit cost.
- **Support load**: tickets per 100 developers; recurring tickets are missing golden-path features, not user error.

## Procurement and commitment hygiene

- Own a rolling 12-month view: current on-demand baseline, current commitment coverage, expiring commitments, and forecast growth. Review monthly with finance, not yearly.
- Commitment levers: compute savings plans / committed use discounts for steady baseline, storage reservations for stable capacity, and negotiated private pricing at meaningful spend. Each has different flexibility when the architecture changes.
- Coverage target: commit to roughly 60-80% of the stable baseline. Higher coverage maximizes discount but removes the ability to absorb architecture changes; lower coverage leaves money on the table.
- Term length: shorter terms (1 year) preserve flexibility for fast-moving workloads; longer terms (3 years) only for capacity you are confident about, such as core networking and data platforms.
- Spot strategy: diversify instance families and zones, handle interruption notices, and keep a small on-demand floor so interruption does not cascade. Treat spot savings as a bonus that funds reliability.
- Marketplace and private offers can beat list prices for committed spend, but read the true-up and minimum-spend terms; an over-committed private deal can cost more than on-demand.
- Serverless and managed services often do not benefit from commitments; check the pricing model before including them in a coverage model.
- Track realized savings from every optimization and commitment in the same report; projected savings that never appear in the billing data are fiction.

## Anti-patterns

- Chargeback before showback, or allocation by spreadsheet politics.
- Chasing a percentage cost cut by degrading reliability without checking SLO impact.
- Every workload at Guaranteed QoS "to be safe", locking 3x the capacity needed.
- Buying commitments for peak usage, then paying for idle reservation.
- Building a portal no developer asked for; measuring success by click counts.
- Golden paths that stop at "service created" without day-2 operations.
- Cost tooling only visible to finance, never to the engineers who choose instance sizes.
- Treating the platform team as a ticket queue instead of a product team.

## Checklist

- [ ] One normalized cost dataset across clouds, refreshed daily.
- [ ] Required labels enforced by policy; untagged spend is < 5% and tracked.
- [ ] Showback published monthly per team/service with shared-cost rules documented.
- [ ] Unit economics tracked for top revenue or usage paths.
- [ ] Budgets and 80%/100% alerts per team and environment; anomalies routed to owners.
- [ ] Rightsizing sweep monthly; VPA recommendations reviewed.
- [ ] Spot/arm64/latest-gen adoption evaluated with load tests.
- [ ] Storage lifecycle and orphan cleanup automated.
- [ ] Commitments cover the stable baseline with a review cadence.
- [ ] Golden path exists, is adopted, and reports DORA metrics.
- [ ] Self-service provisioning with guardrails; approvals only for irreversible actions.
