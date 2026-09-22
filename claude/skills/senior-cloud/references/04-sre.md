# Site Reliability Engineering

> Scope: reliability targets, error budgets, toil reduction, incident response, chaos engineering, and capacity planning.

## SLI, SLO, SLA

| Term | Definition | Example |
|---|---|---|
| SLI | A measured aspect of service behavior | Fraction of requests served < 300ms |
| SLO | Target for an SLI over a window | 99.9% over 28 days |
| SLA | Contractual commitment with consequences | 99.9% or service credits |
| Error budget | Allowed failure implied by the SLO | 0.1% of requests |

Rules of thumb:

- Pick a small number of SLIs per user journey: availability, latency, and for pipelines freshness/throughput. Correctness and durability are SLIs too where data matters.
- Express SLIs as good-events / valid-events so the math is a ratio, not an average of averages.
- Start with 99.9% for user-facing services; reserve 99.99% for services whose failure directly blocks revenue or safety. Every nine costs money and slows delivery.
- Window: rolling 28 days (four weeks) balances responsiveness and stability; some teams use calendar months for reporting. Pick one and stay consistent.
- Make SLOs of dependencies stricter than dependents: if your SLO is 99.9%, dependencies should target 99.95%+.
- Do not promise 100% - user devices and networks are outside your control.

## Error budget policy

Write it down before the first breach and get it signed by product and engineering:

1. Budget intact (> 25% remaining): ship features normally.
2. Budget low (< 25%): prioritize reliability work; freeze risky launches.
3. Budget exhausted: freeze all changes except reliability fixes and security patches until the budget recovers.
4. Every freeze has an owner, an exit criterion, and a review date.
5. Budget spend is a signal, not a failure: teams that never spend the budget are under-shipping.

Escalation path must be explicit. A policy that nobody enforces is worse than no policy because it teaches the organization that SLOs are theater.

## Burn-rate alerting

Burn rate = rate of budget consumption relative to the SLO. A burn rate of 1 exhausts the budget exactly at the end of the window; 14.4x exhausts a 28-day budget in about two days.

Multi-window, multi-burn-rate alerts catch both fast outages and slow bleeds without paging on every blip:

| Severity | Burn rate | Long window | Short window | Budget consumed |
|---|---|---|---|---|
| Page | 14.4 | 1h | 5m | ~2% in 1h |
| Page | 6 | 6h | 30m | ~5% in 6h |
| Ticket | 1 | 3d | 6h | ~10% in 3d |

```promql
# Page: 14.4x burn over 1h, confirmed by 5m window
(
  sum(rate(http_requests_total{code=~"5.."}[1h])) / sum(rate(http_requests_total[1h])) > (14.4 * 0.001)
)
and
(
  sum(rate(http_requests_total{code=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > (14.4 * 0.001)
)
```

- Alert on symptoms users feel (error ratio, latency), never on causes (CPU, disk) except where a cause has no symptom proxy yet.
- Every alert links a runbook and a dashboard. If a page has no action, delete it.
- Review alert quality monthly: pages per shift, false-positive rate, time to acknowledge. Target fewer than two pages per on-call shift outside real incidents.

## Toil

Toil is manual, repetitive, automatable, tactical work that scales with service growth and produces no enduring value.

How to find it: track work in half-hour granularity for two weeks; interview on-call. Common sources: manual deploys, certificate and secret rotation, access grants, capacity tickets, data restores, false-positive alert triage, one-off dashboards.

How to kill it:

- Automate the top five recurring tasks per quarter; require a runbook to be executed twice before automation (the second execution is the spec).
- Self-service replaces ticket queues (see `./09-cost-platform-engineering.md` for internal developer platforms).
- Cap toil per SRE at 50% of time; the rest goes to engineering and reliability projects.
- Watch automation rot: scripts with no owner become new toil. Every automation has an owner and a test.

## Incident management

### Severity model

| Severity | Impact | Response | Comms |
|---|---|---|---|
| SEV1 | Major outage, data loss risk, safety | Page immediately, all hands | Status page + exec update every 30m |
| SEV2 | Degraded for many users or a key customer | Page on-call, incident channel | Internal updates hourly |
| SEV3 | Minor degradation, workaround exists | Ticket or next business day | Channel only |
| SEV4 | Cosmetic, no user impact | Backlog | None |

### Roles

- **Incident Commander (IC)**: owns the response, not the fix. Decides mitigation, delegates, calls severity.
- **Operations lead**: coordinates technical work, owns the timeline.
- **Communications lead**: updates stakeholders and status page; shields responders from inbound questions.
- **Scribe**: records decisions and timestamps for the postmortem.

For small teams one person may hold multiple roles, but the IC must not be debugging. Rotate and practice.

### Response principles

1. Mitigate before root cause: rollback, scale up, fail over, rate limit. Customers do not care why yet.
2. Declare early and downgrade later. Under-declaring is the normal failure.
3. One channel, one source of truth for status.
4. Change one thing at a time and record it.
5. Handover explicitly at shift change with current state and next hypothesis.

### Postmortems

- Blameless and written within five business days; published internally by default.
- Cover: impact in user terms, timeline, contributing factors (not "human error"), what went well, what was lucky, and action items.
- Action items have owners and dates; no more than three per incident so they actually get done.
- Track action-item completion as a reliability metric. Recurring causes mean the items were too shallow.
- Review patterns quarterly across incidents; fix systemic causes, not just the last one.

## Chaos engineering

Principles:

- Define steady state as measurable output (SLO burn, throughput), not internal counters.
- Hypothesize the system will stay in steady state, then inject a realistic fault.
- Run in staging before production; start with a low-blast-radius production experiment only when staging has proven the tooling and the safety valves.
- Automate experiments and put them in CI where possible.
- Minimize blast radius: kill one pod, one zone, one dependency; never "all at once" until the program is mature.

Tooling: LitmusChaos and Chaos Mesh for Kubernetes-native experiments; cloud provider fault injection services (AWS FIS and equivalents) for infrastructure-level faults; load generators plus failure injection to test degradation paths.

Starter experiment catalog:

1. Kill a random pod of a critical deployment; verify PDB and restart budget.
2. Inject 500ms latency on the database dependency; verify timeouts and degraded responses.
3. Fail one availability zone; verify capacity headroom and failover.
4. Exhaust a dependency (DNS, auth); verify circuit breakers and cached behavior.
5. Roll a bad config; verify rollout abort and alerting.

Game days: schedule them, invite the whole team, and record what surprised you. The debrief is the product, not the experiment.

## Capacity and load

- Model capacity as peak-arrival-rate -> resource need -> fail-over headroom. Two numbers matter: normal peak, and peak during failure of one zone or one node group.
- Maintain headroom to survive N-1 infrastructure failure plus traffic growth between provisioning cycles. Stateless services: target 40-60% utilization at peak; databases need more.
- Queueing reality: latency rises non-linearly as utilization approaches 100%. The knee usually appears above 60-70% for shared resources. Autoscaling reacts after the knee; provision for the knee, do not chase the cliff.
- Little's law: `concurrency = arrival rate x latency`. Use it to translate throughput targets into worker/connection requirements and to sanity-check load-test numbers.
- Load testing: k6, Locust, Gatling, or vegeta for HTTP; use production-shaped data and think time; ramp until the SLO breaks and record that point as the safe ceiling with margin.
- Run a load test after every architectural change and before every major event (launch, sale, migration).
- Database and third-party quotas are capacity too: connection pools, API rate limits, and NAT ports exhaust before CPU does.
- Review capacity monthly: forecast 3-6 months out based on growth, not just current usage.

## Anti-patterns

- SLOs with no error budget policy or budget that is never enforced.
- Paging on every individual failure instead of on burn rate.
- Incident response with no IC, causing parallel heroes and no decisions.
- Postmortem action items that are all "be more careful" or "add a test" with no owner.
- Chaos experiments without steady-state measurement or a kill switch.
- Capacity planning from average utilization instead of peaks and failure headroom.
- Reliability owned by one team while product changes ship freely.

## Checklist

- [ ] Every user-facing service has 1-3 SLIs with defined sources and windows.
- [ ] SLOs published; error budget policy signed and enforced.
- [ ] Burn-rate alerts in place for page and ticket severities.
- [ ] On-call rotation exists with escalation and handover procedure.
- [ ] Incident severity matrix and roles documented; IC trained.
- [ ] Postmortems blameless, timely, and action items tracked.
- [ ] At least one chaos experiment per quarter against a critical path.
- [ ] Capacity headroom tested for N-1 zone failure.
- [ ] Load-test baseline recorded and re-run before major launches.
