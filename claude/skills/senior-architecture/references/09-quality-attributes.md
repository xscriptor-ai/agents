# Quality Attributes and Tradeoffs

Quality attribute scenarios, lightweight ATAM, CAP/PACELC, consistency/latency/availability
tradeoffs, and risk registers.

## Quality Attribute Scenarios

A quality attribute is not reviewable until it is a scenario with a measurable response. Use the
six-part form: source, stimulus, artifact, environment, response, response measure.

| Attribute | Scenario (abbreviated) | Response measure |
|---|---|---|
| Availability | A zone fails during peak traffic | Checkout stays available; error rate < 0.1% for 10 minutes |
| Performance | 95th percentile user submits an order | p95 < 400 ms, p99 < 1 s server-side |
| Scalability | Marketing campaign multiplies traffic 10x for 2 hours | No manual action; p95 within budget; cost cap held |
| Consistency | Customer updates address on mobile, checks desktop | Read-your-writes within 2 s |
| Durability | Disk/database node loss | Zero acknowledged writes lost; RPO 0, RTO 15 min |
| Security | Credential stuffing burst at 100x normal login rate | Rate limit and lockout; no account takeover; p95 login < 1 s |
| Operability | Deploy a routine change during business hours | Zero-downtime, automatic rollback under 5 min |
| Cost | Steady-state month at current traffic | Cost per 1k orders under target; no more than planned growth |
| Compliance | Erasure request for one user | All copies removed within 30 days; audit record kept |
| Modifiability | Add a payment provider | First provider plugin takes < 2 weeks; no core changes |

Guidance:

- Write 10-20 candidate scenarios with stakeholders, then rank; only the top 3-5 become
  architecture drivers.
- The measure must be observable in production (SLO, business metric) or a test fixture.
- "Fast", "highly available", and "scalable" without numbers are aspirations, not attributes.
- Attach each driver to the decisions it constrains; if no decision changes, it is not a driver.

## Elicitation and Prioritization

Lightweight process that fits a half-day workshop:

1. Gather stakeholders: product, operations/on-call, security, one or two senior engineers.
2. Brainstorm scenarios per attribute category (the table above is a prompt list).
3. Rank by business impact and difficulty; force a top 3-5, explicitly parking the rest.
4. Build a utility tree: root = "utility", children = top attributes, leaves = scenarios with
   (business value, technical difficulty) ratings H/M/L.
5. Walk each high-value/high-difficulty leaf through the architecture: can the current design
   satisfy it? What would have to change?
6. Record the drivers, decisions, and gaps; feed them into ADRs and the risk register.

| Business value \ Technical difficulty | Low | Medium | High |
|---|---|---|---|
| High | Do now; likely cheap | Plan and design now | Spike, then decide; top risk |
| Medium | Backlog | Schedule | Consider simpler target |
| Low | Ignore | Ignore unless free | Do not gold-plate |

## Lightweight ATAM

Architecture Tradeoff Analysis Method, scaled to a few hours rather than a multi-day audit.

| Step | Activity | Time | Output |
|---|---|---|---|
| 1 | Present business goals and drivers | 30 min | Prioritized attribute list |
| 2 | Present the architecture (C4 context/container) | 30-45 min | Shared understanding |
| 3 | Map scenarios onto the architecture | 60 min | Sensitive points, tradeoff points |
| 4 | Identify risks, non-risks, and assumptions | 45 min | Draft risk register |
| 5 | Prioritize scenarios with stakeholders | 30 min | Top drivers confirmed |
| 6 | Re-analyze against prioritized scenarios | 45 min | Updated risks and decisions |
| 7 | Report and assign owners | 30 min | ADRs, action items, review date |

Vocabulary:

- **Sensitive point** — a design choice that strongly affects one attribute (connection pool
  size, sync versus async, replica reads).
- **Tradeoff point** — a choice that helps one attribute and hurts another (consistency versus
  availability, caching versus freshness).
- **Risk** — an unresolved threat to a driver; **non-risk** — a driver that is clearly satisfied.
- **Architectural runway** — planned work that keeps near-term delivery possible.

Rules for credibility: the architecture must be presented honestly (current, not aspirational),
at least one stakeholder from outside the team participates, and outputs have owners and dates.

## CAP and PACELC

CAP: under a network **partition**, a distributed system can preserve **consistency** (linearizable
operations) or **availability** (every request gets a non-error response), not both. Partition
tolerance is not optional in a real network, so the choice is what to sacrifice during a
partition.

PACELC extends this: even when there is no partition (**E**lse), the system still chooses between
**L**atency and **C**onsistency. This is the daily tradeoff: synchronous replication costs
latency; asynchronous replication accepts staleness.

| System posture | During partition | Normal operation | Typical choice |
|---|---|---|---|
| CP | Refuse writes / stay linearizable | May be slower | Money movement, inventory reservation |
| AP | Accept writes, converge later | Fast, may read stale | Feeds, presence, catalogs, analytics |
| Tuned per operation | Mixed | Mixed | Most real systems: strong for writes, stale reads for feeds |

Practical rules:

- Do not apply CAP to a single-node database; it is a distributed-systems property.
- Name the specific operation and store: "orders primary: CP for writes; search index: AP."
- CAP does not cover latency — use PACELC and SLOs for that.
- Partition behavior needs a tested failure mode: what does the UI do when the store refuses
  writes? Decide before the incident.

## Consistency, Latency, Availability, Cost

| Decision | Favors | Costs |
|---|---|---|
| Synchronous replication / strong consistency | Correctness, RPO 0 | Latency, availability during partition |
| Asynchronous replication / eventual consistency | Latency, availability | Staleness, conflict handling |
| Read replicas and caches | Latency, read scale | Staleness, invalidation complexity |
| Multi-region active-active | Availability, latency for users | Consistency conflicts, cost, complexity |
| Single-region | Consistency, cost, simplicity | Availability during region outage |
| Retries and queues | Availability perception, load leveling | Duplicates, ordering, DLQ operations |
| Denormalized read models | Read latency | Rebuild tooling, storage, staleness |
| Managed services | Operability, time to market | Lock-in, cost curve, less control |

Method: state the driver ranking first, then choose. A decision that cannot name what it
sacrifices is untested. Record the tradeoff in the ADR; revisit when the ranking changes.

## Availability and Latency Budgets

Availability arithmetic (composed dependencies multiply):

| Availability per dependency | Two in series | Five in series |
|---|---|---|
| 99% (3.65 d/yr down) | 98.01% | 95.1% |
| 99.9% (8.77 h/yr) | 99.8% | 99.5% |
| 99.99% (52.6 min/yr) | 99.98% | 99.95% |
| 99.999% (5.26 min/yr) | 99.998% | 99.995% |

Implications:

- Every synchronous hop lowers composite availability; async decoupling removes a hop from the
  critical path.
- Redundancy and graceful degradation (cached/stale responses, read-only mode) buy availability
  where replication does not.
- Nines are per user journey, not per component; define the journey.
- SLOs: choose a service level objective, an error budget, and an alert burn-rate policy
  (fast burn pages, slow burn tickets). Review budgets monthly; freeze feature work if burned.
- Latency should be expressed as percentiles (p50/p95/p99), never averages, and measured where
  the user is, not only server-side.

## Risk Register

Keep a living, short register; it is the ATAM's main durable output.

| ID | Risk | Likelihood | Impact | Attribute affected | Mitigation / owner | Review date |
|---|---|---|---|---|---|---|
| R-01 | Outbox relay lag grows under peak | Medium | High (stale reads) | Consistency, availability | Load test; lag SLO; fallback read path — owner: orders team | 2026-06 |
| R-02 | Single-region database outage | Low | Critical | Availability | DR rehearsal quarterly; RTO 15 min — owner: platform | 2026-05 |
| R-03 | Vendor SDK lock-in blocks multi-cloud | Medium | Medium | Portability, cost | Adapter boundary plus conformance tests — owner: architecture | 2026-09 |
| R-04 | Team lacks Kafka operational experience | High | Medium | Operability | Managed service plus training; runbook — owner: platform | 2026-04 |

Rules: one owner and one review date per risk; update likelihood/impact at review; convert
accepted risks into ADR consequences; never keep a register longer than a page or two — if it
grows, prioritize and close.

## Anti-Patterns

- **Attribute-free architecture** — decisions justified by "best practice" with no driver.
- **Everything critical** — no ranking, so nothing guides tradeoffs.
- **ATAM as audit** — multi-day ceremony producing a document nobody uses; keep it timeboxed.
- **CAP as slogan** — citing CAP without naming the operation and store.
- **Average latency** — hides the tail that users feel; use percentiles.
- **Risk register as archive** — entries never closed or reviewed.
- **Ignoring cost** — treating cost as non-architectural; it is an attribute with a budget.
- **Aspirational diagrams in review** — analyzing a design that does not exist.

## Checklist

- [ ] Top 3-5 quality attributes ranked and written as measurable scenarios.
- [ ] Each driver maps to concrete decisions (ADRs) and enforcement (tests/SLOs).
- [ ] Failure modes designed and tested per dependency (partition, timeout, overload).
- [ ] CAP/PACELC choices named per store and operation.
- [ ] Tradeoffs stated: what is sacrificed for what, and where it is recorded.
- [ ] SLOs and error budgets exist for critical user journeys.
- [ ] Risk register has owners and review dates; risks updated, not accumulated.
- [ ] Review outputs (ADRs, actions) tracked to closure.

## Related

- Recording the decisions that satisfy drivers: [./01-adr.md](./01-adr.md)
- Style-level attribute comparisons: [./03-styles.md](./03-styles.md)
- Consistency mechanisms behind the tradeoffs: [./06-data-architecture.md](./06-data-architecture.md)
- Publishing review outcomes: [./10-documentation-governance.md](./10-documentation-governance.md)
