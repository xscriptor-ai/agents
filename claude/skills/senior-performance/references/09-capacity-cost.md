# Capacity and Cost

Scope: capacity planning, autoscaling signals, SLO-aware scaling, cost-per-request optimization, and the tradeoff checklist.

## Capacity Planning Basics

- Define the unit of capacity: requests per second per instance for stateless services, messages per second per consumer, queries per second per database, or concurrent connections per gateway.
- Capacity planning is a demand forecast plus a headroom policy. Without both, it is either guesswork or over-provisioning.
- Plan to the peak, not the average. Peak factors of 2-5x daily average are common for consumer services; seasonal and campaign peaks can be far higher.
- Plan for failure, not just demand: losing one zone, one region, or one large dependency should not breach the SLO. Determine the required redundancy level explicitly.
- Re-verify capacity after every architecture change, runtime upgrade, dependency change, or major data growth. Capacity plans expire.

## Building a Capacity Model

1. Measure the per-instance ceiling with a load test at the target latency: the load level at the knee, not the maximum observed. See `./08-load-testing.md`.
2. Identify the bottleneck order: what saturates first (CPU, memory, DB, connections, network, locks), second, and third.
3. Model demand: `instances = peak_rps / per_instance_capacity * safety_factor`, then round up and add failure headroom.
4. Include startup time: an instance that takes minutes to become useful does not help with a spike unless pre-warmed or over-provisioned.
5. Validate the model against production saturation metrics; adjust the per-instance capacity to observed reality.
6. Stress-test the model by removing capacity (kill a zone in staging or during an exercise) and confirming the SLO holds.

```text
required_instances = ceil( peak_rps / per_instance_rps * (1 + safety_margin) )
required_instances += failure_headroom   # e.g. one zone worth of capacity

cost_per_1k_requests = hourly_cost_per_instance * instances / (rps * 3600) * 1000
```

- Keep the model in the repository next to the service, with its assumptions and measurement dates.
- Track the model's error: predicted versus actual saturation after each peak. A persistent overestimate wastes money; an underestimate pages people.
- Databases and caches rarely autoscale horizontally like stateless services; plan their capacity separately with explicit upgrade steps.

## Planning Inputs

| Input | Source | Use |
|---|---|---|
| Traffic history | Metrics by endpoint and tenant | Baseline and growth rate |
| Seasonality and campaigns | Product and marketing calendar | Peak windows and multipliers |
| Growth rate | Month-over-month trend | When new capacity is needed |
| Launch events | Roadmap | Step changes in load |
| Failure scenarios | SLO and dependency map | Redundancy headroom |
| Cost ceiling | Finance and unit economics | Bound on instance class and count |
| Lead times | Procurement and quota | When to start scaling work |

- Keep a rolling forecast at least one quarter ahead and update it monthly.
- For campaigns, pre-scale and pre-warm; autoscaling reacts after the spike has already arrived.
- Capacity review should be a scheduled activity, not a reaction to an incident.

## Autoscaling Signals

| Signal | Responds to | Notes |
|---|---|---|
| CPU utilization | Compute-bound services | Lagging; use as a coarse fallback |
| Memory utilization | Memory-heavy services | Poor for leak-prone services; scale on load instead |
| Requests per second per target | Stateless request services | Simple, but ignores latency and request cost variance |
| Concurrent connections or in-flight requests | Connection-heavy services | Closer to queueing reality; pairs with Little's Law |
| Queue depth or age | Worker and async pipelines | Best leading signal for consumers; the queue is the backlog |
| Custom metric (for example, active jobs, tenant count) | Specialized workloads | Requires a reliable metric pipeline and scaling policy |
| Scheduled or predictive | Known diurnal and campaign patterns | Pre-warms before the peak; combine with reactive signals |

- Scale on a leading signal. CPU lags because it rises only after requests are already queued; concurrency and queue depth lead.
- Set targets with headroom: scaling to 70 percent utilization keeps queueing near linear and absorbs bursts while new capacity arrives. See `./01-methodology.md`.
- Configure scale-up aggressively and scale-down cautiously: fast add, slow remove, with stabilization windows long enough to avoid oscillation (flapping).
- Scale-down must respect in-flight work and connection draining; a pod that dies mid-request turns a cost optimization into an error budget burn.
- Beware metrics with low resolution or delayed ingestion; autoscaling decisions based on stale data overshoot and thrash.
- Verify that the scaling policy cannot exceed quotas and that hitting a quota produces an alert, not a silent cap.
- Combine autoscaling with load shedding: capacity arrives in tens of seconds at best, shedding works immediately. See `./06-concurrency-backpressure.md`.

## SLO-Aware Scaling

- Translate the latency SLO into a concurrency target: `max_in_flight = target_rps * latency_budget`. Scale when measured in-flight concurrency exceeds a fraction of that, before latency degrades.
- Watch the saturation metric that correlates with the SLO. If p95 latency is your SLO, scale on the resource that queues first, not on the one that is easiest to measure.
- Prefer scaling on latency-adjacent signals (queue wait, pool wait, concurrency) over raw CPU; they move before user-visible degradation.
- During incidents, override autoscaling if the signal is misleading (for example, low CPU because of a lock or downstream wait). Manual floors and ceilings are valuable.
- For predictable peaks, use scheduled scaling to reach target capacity before the demand arrives, then let reactive policies handle the variance.
- Test scaling policies with spike tests and confirm containers reach ready state and receive traffic before the spike passes.

## Cost per Request and Unit Economics

- Track cost per meaningful unit: per 1,000 requests, per active user, per job, or per GB processed. A falling bill with faster-growing traffic is not efficiency if cost per request rose.
- Build the cost model from components:

| Component | Drivers | Typical levers |
|---|---|---|
| Compute | Instance hours, vCPU, memory | Rightsizing, ARM instances, spot/preemptible, autoscaling targets |
| Database | Instance class, storage, IOPS, replicas | Query tuning, index fixes, pooling, read replicas, tiering |
| Cache | Memory GB-hours, bandwidth | Hit ratio, TTL design, value sizes. See `./02-caching.md` |
| Storage | GB stored, operations, retrieval | Lifecycle tiering, compression, retention policy |
| Network egress | Cross-zone, cross-region, internet bytes | Caching, compression, locality, CDN |
| Third-party APIs | Calls, tokens | Batching, caching, contract review |
| Observability | Ingested bytes, retained samples | Sampling, filtering, retention tiers |

- Attribute cost to features and tenants where possible; shared-cost allocation is approximate, but directionally useful for prioritization.
- Compare cost per request across releases: a performance regression often shows up as a cost regression before a latency regression.
- Set a cost budget per service with an alert, the same way latency has a budget.

## Efficiency Levers

| Lever | Typical effect | Risk / caveat |
|---|---|---|
| Rightsizing instances | 10-40% compute savings | Needs real utilization data, not averages |
| Raising autoscaling utilization target | Fewer idle instances | Tails grow; validate against SLO |
| Cache hit ratio improvement | Large downstream savings | Correctness and invalidation risk. See `./02-caching.md` |
| Query and index tuning | Large DB savings | Requires plan analysis and maintenance |
| Batching and compression | Fewer calls, fewer bytes | Latency tradeoff; batch caps |
| Storage tiering and lifecycle | Large storage savings | Retrieval latency and cost; legal holds |
| ARM-based instances | Often meaningful price/performance gain | Build compatibility; test performance, do not assume |
| Spot / preemptible capacity | Deep discounts | Interruption handling; fit for batch and stateless tiers |
| Reserved or committed capacity | Discount for steady baseline | Lock-in; forecast must be sound |
| Serverless pay-per-use | Zero idle cost | Cold starts, per-request pricing cliffs at high volume |
| Removing unused resources | Immediate savings | Orphaned volumes, old snapshots, idle environments |

- Apply levers in order of value and reversibility: rightsizing and query fixes first, commitments last.
- Re-measure after every efficiency change; savings that cost latency usually get reverted, and it is better to know before rollout.
- Consolidate environments (preview, staging, dev) with schedules and quotas; idle non-production is a common hidden cost.

## Tradeoff Checklist

| Decision | Cost side | Risk side | Question to ask |
|---|---|---|---|
| Longer cache TTL | Cheaper origin | Staler data | What is the maximum acceptable staleness? |
| Higher utilization target | Fewer instances | Tail latency | Which percentile does the SLO protect? |
| More replicas | Higher DB cost | Lag and complexity | Is the read budget actually the bottleneck? |
| Bigger instances vs more small | Simpler ops vs elasticity | Blast radius, scaling granularity | Which scales with traffic shape? |
| Spot capacity | Cheaper compute | Interruptions | Can work be checkpointed or drained? |
| More observability retention | Better investigations | Ingest and storage cost | Which signals are queried after 30 days? |
| Aggressive load shedding | Protects core users | Some rejected traffic | Are rejections visible and budgeted? |
| Denormalized or precomputed data | Faster reads, cheaper joins | Consistency and write cost | Who owns reconciliation? |

- Record tradeoff decisions with their context; the same choice may be wrong under a different SLO or traffic mix.
- Revisit decisions when the input changes (new SLO, new traffic pattern, price change), not on a fixed calendar alone.

## Review Cadence

- Monthly: unit cost review (cost per request or active user) and saturation trend against the capacity model.
- Per release: performance and cost regression check on canary; scale settings unchanged unless evidence says otherwise.
- Quarterly: capacity and failure-mode test (load test, zone-loss exercise), model refresh, and commitment review.
- Before major launches: forecast update, pre-scaling plan, load test at the projected peak, and a rollback plan.

## Anti-Patterns

- Planning on averages and discovering the peak in production.
- Scaling on CPU for a service whose bottleneck is database connections or queue depth.
- Autoscaling without load shedding and assuming capacity arrives instantly.
- Cutting headroom to hit a cost target, then blaming the collector, the database, or "unexpected" spikes.
- Optimizing the bill without tracking cost per request; total cost can fall while unit cost rises.
- Buying commitments before rightsizing and query tuning.
- Copying instance classes and scaling policies between services with different profiles.
- Ignoring egress, third-party, and observability costs in unit economics.
- Stale capacity plans from a previous architecture.

## Checklist

- [ ] Capacity model exists with per-instance ceiling, peak factor, and failure headroom.
- [ ] Bottleneck order documented and validated by load test at the knee.
- [ ] Autoscaling uses leading signals with headroom targets and anti-flapping windows.
- [ ] SLO translated into concurrency and saturation targets; shedding covers the scale-up gap.
- [ ] Cost per request (or per active user) tracked over time with an owner.
- [ ] Cost model covers compute, database, cache, storage, egress, third parties, and telemetry.
- [ ] Efficiency levers applied in value/reversibility order; each change re-measured.
- [ ] Tradeoff decisions recorded with context, including caching and utilization choices.
- [ ] Forecast updated monthly; capacity and failure reviewed quarterly.
- [ ] Quotas and limits monitored with alerts, not discovered via silent caps.
