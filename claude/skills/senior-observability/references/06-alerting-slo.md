# Alerting and SLOs

Scope: SLIs/SLOs, error budgets, burn-rate alerts, symptom versus cause alerts, routing, on-call ergonomics, and runbooks.

## Definitions

| Term | Definition | Example |
|---|---|---|
| SLI | Measured service attribute from the user's point of view | Fraction of requests served under 300 ms |
| SLO | Target for an SLI over a window | 99.9% of requests under 300 ms over 28 days |
| SLA | Contractual commitment with consequences | 99.9% availability, service credits below |
| Error budget | Allowed failure: `1 - SLO` | 0.1% of requests, about 43 minutes per 30 days |
| Burn rate | Speed of budget consumption relative to the SLO window | 1x exhausts in exactly one window |

- SLIs are ratios of good events to valid events. Define all three: what counts as good, what counts as valid, and what is excluded (health checks, bot traffic, client aborts).
- Measure at the closest point to the user: load balancer or ingress for availability and latency; service-side when the load balancer cannot see semantics. State the choice in the SLO document.
- Choose windows by decision horizon: rolling 28 or 30 days for the headline SLO, 1 to 7 days for fast feedback, and calendar months when the business reports monthly.
- Few SLOs, high value: start with availability and latency per user-facing service. Add correctness, freshness, durability, or throughput only where they drive user decisions.

## SLI Menu

| SLI type | Good event | Valid event | Watch out for |
|---|---|---|---|
| Availability | Response not 5xx and completed | All requests | Exclude client errors you do not own, but document it |
| Latency | Response under threshold | All successful requests | Pick a threshold users feel, not the current p99 |
| Throughput | Work completed on time | Submitted work | Useful for batch and streaming |
| Correctness | Result validated | Results produced | Hard to measure; use sampled validation |
| Freshness | Data age under threshold | Data reads | ETL and cache-based systems |
| Durability | Data retrievable | Data written | Backups and replication health |
| Saturation proxy | Queue wait under threshold | Requests | Leading indicator, not an SLI replacement |

```promql
# Availability SLI as a ratio over a 28-day window (recording rule input)
sum(rate(http_requests_total{status!~"5.."}[5m]))
  / clamp_min(sum(rate(http_requests_total[28d])), 1)
```

- Prefer request-based SLIs for request/response services; time-based "uptime" SLIs hide partial failures and are hard to alert on.
- Synthetic probes are valid SLIs for critical entry points when traffic is low; combine with real traffic and label the source.
- Keep the SLI implementation in a recording rule so dashboards, alerts, and reports share one definition. Multiple implementations of the same SLI is a defect.

## Error Budget Policy

- Write the policy before the first breach: what happens at 50%, 75%, and 100% budget consumption, who decides, and how the team returns to feature work.
- Typical policy: under 50% consumed, ship normally; 50-75%, focus on reliability work; over 75%, feature freeze except reliability and security; exhausted, mandatory freeze plus a postmortem.
- Exhaustion is not a punishment; it is a signal that reliability work now has higher priority than features. This only works if leadership agrees in advance.
- Track budget by service and by tenant where multi-tenant, and review at a fixed cadence. A budget nobody looks at changes nothing.
- Freeze exceptions must be explicit and time-boxed, recorded in the incident or change log.

## Burn-Rate Alerts

Multi-window, multi-burn-rate is the default pattern for SLO alerting. Burn rate `B` means the budget is consumed `B` times faster than the SLO window allows; `B = 1` exhausts exactly at the end of the window.

| Budget consumed | Long window | Short window | Burn rate | Severity |
|---|---|---|---|---|
| 2% | 1 h | 5 m | 14.4x | Page |
| 5% | 6 h | 30 m | 6x | Page |
| 10% | 1 d | 2 h | 3x | Ticket |
| 10% | 3 d | 6 h | 1x | Ticket |

- The long window detects, the short window confirms, and both must be above threshold before firing. This kills flapping and long tails without losing fast burns.
- Formula shape: `error_ratio > (1 - SLO) * burn_rate` over the window, with the long and short conditions ANDed.
- Page only on burns that consume budget fast enough to matter within a shift. Slow burns become tickets.
- Add a "watchdog" always-firing alert that routes to a dead-man's-switch receiver. If alert evaluation or routing breaks, silence is ambiguous; the watchdog makes it explicit.
- For each alert, define the expected consumer action: roll back, scale, fail over, or investigate. No action means no page.

## Symptom vs Cause

| Alert type | Example | Route to | Why |
|---|---|---|---|
| Symptom | p99 latency SLO burn, error rate SLO burn | Page | Directly user-visible |
| Saturation | Queue age growing, connection pool near limit | Page or ticket | Leading indicator of symptom |
| Cause | CPU high, disk 90%, one pod crash-looping | Dashboard or ticket | Often self-healing or covered by the symptom |
| Capacity | Forecasted exhaustion in 30 days | Ticket | Not urgent at 3 a.m. |
| Informational | Deploy completed, autoscaler scaled | Chat | No human action |

- Alert on what the user experiences, not on what you think causes it. "CPU is high" is only page-worthy when it is the direct cause of a user symptom and no symptom alert covers it.
- For each page, the question is "what would the on-call do now?" If the answer is "watch it", it is not a page.
- Dependencies: alert on your own SLIs, not on a dependency's internal metrics. If the dependency's failure harms users, your symptom alert fires; their causes are their problem.

## Alert Design Rules

- Every alert needs an owner, a severity, a runbook link, and a clear action. Encode owner and runbook in labels so routing is automatic.
- Use `for:` to require persistence; set it from the detection profile, not habit. A 5-second spike should not page.
- Prefer ratios over absolute counts, and rates over totals. "Error ratio above 5% for 10 minutes" beats "500 errors".
- Group by the dimension that determines action (`service`, `region`, `tenant`), never by pod or instance, to avoid a page per replica.
- Inhibition: suppress downstream alerts when an upstream cause is already paging. Silences are time-boxed and require a reason.
- Test alerts: unit-test rules in CI, and deliberately break a canary in staging to confirm routing, payload, and runbook accuracy.
- Alert payload must include: service, environment, window, current value, threshold, dashboard link, runbook link, and the SLO/budget context.
- Alert on absence: if a service stops reporting, a "no data" alert should fire. Silent producers are worse than noisy ones.

## Routing and On-Call

| Route | Criteria | Channel | Response |
|---|---|---|---|
| Critical | Page-worthy SLO burn, data loss | Pager with escalation | Immediate ack, incident process |
| High | Degradation users notice | Pager during business-critical windows | Ack within minutes |
| Medium | Risk of future degradation | Chat channel plus ticket | Same business day |
| Low | Cleanup, forecast | Ticket queue | Scheduled |

- Route by team ownership labels, not by service name lists maintained by hand. Ownership data belongs in a service catalog and must feed routing.
- Escalation policies: primary, secondary, then engineering manager; define ack timeouts and repeat notifications. Test the escalation path after every rotation change.
- On-call ergonomics: cap pages per shift, ban pages for non-actionable conditions, protect sleep, and rotate consistently. A noisy rotation produces ack-and-ignore behavior.
- Track alert quality: pages per shift, percentage acked, percentage actioned, false-positive rate, mean time to acknowledge, and top noisy alerts. Review monthly and delete or fix the worst offenders.
- Handovers should include ongoing incidents, silences, and burn status; silences that outlive the event are a recurring source of blindness.
- Runbooks: symptom, impact, first three commands, dashboards to open, escalation path, rollback steps. Keep them in version control and link from the alert payload. A runbook nobody tested is a wish.

## Example Burn-Rate Rule

```yaml
groups:
  - name: slo-burn
    rules:
      - record: slo:availability:error_ratio5m
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m]))
            / clamp_min(sum(rate(http_requests_total[5m])), 1)
      - alert: AvailabilityBudgetBurnFast
        expr: |
          slo:availability:error_ratio5m > (14.4 * 0.001)
          and
          (sum(rate(http_requests_total{status=~"5.."}[1h]))
            / clamp_min(sum(rate(http_requests_total[1h])), 1)) > (14.4 * 0.001)
        for: 2m
        labels: { severity: critical, team: order-api }
        annotations:
          summary: "Order API burning error budget 14.4x over 1h"
          runbook_url: "https://runbooks/order-api/availability-burn"
```

- Threshold `(1 - SLO) * burn_rate` with `(1 - SLO) = 0.001` for a 99.9% SLO gives 1.44% error ratio for the 14.4x page. Keep the arithmetic visible in the rule.
- Record the error ratio once and reuse it; the long and short windows are the only difference.
- Add `severity`, `team`, `service`, `environment`, and `runbook_url` labels so routing and payload generation need no per-alert special cases.
- Test the rule with a time series that simulates a burn and assert the alert fires with the expected labels.

## SLO Document Template

```text
Service:        order-api
Owner:          payments platform team
User journey:   customers place and view orders
SLI:            proportion of valid HTTP requests that succeed and complete under 300 ms
Good event:     status < 500 and duration <= 300 ms
Valid event:    all requests to /orders routes, excluding health checks and bot traffic
Measurement:    ingress proxy metrics, 28-day rolling window
SLO:            99.9% availability, 99.5% latency
Error budget:   0.1% (approx. 40 minutes of full outage per 28 days)
Policy:         <50% ship normally; 50-75% reliability priority; >75% freeze; 100% mandatory review
Alerts:         14.4x/1h page, 6x/6h page, 3x/1d ticket
Dashboards:     Order API / SLO
Runbook:        runbooks/order-api/availability-burn
Review cadence: monthly budget review, quarterly target review
```

- One page per service. The document is the contract; if the SLI implementation and the document disagree, the document wins and the code is fixed.
- Exclusions must be justified and measurable; "excluding weird traffic" is not a definition.

## Anti-Patterns

- Alerting on every metric with a static threshold; the team learns to ignore the pager.
- SLOs invented at the end of the quarter to match current performance rather than user expectations.
- Error budgets with no policy, so exhaustion has no consequence.
- Pages that only say "CPU high" without impact or action.
- One alert per pod or per instance instead of per service.
- Runbooks describing a system that no longer exists.
- Silencing alerts permanently instead of fixing root causes.
- Using burn-rate alerts without the fast/slow window pair, causing flapping or missed fast burns.
- No dead-man's-switch alert, so broken alerting looks like a healthy system.

## Checklist

- [ ] SLI definition documented: good event, valid event, exclusions, measurement point.
- [ ] SLO target, window, and error budget agreed with stakeholders.
- [ ] Error budget policy written and signed off, including freeze behavior.
- [ ] Multi-window burn-rate alerts for page and ticket thresholds.
- [ ] Symptom-first alerting; cause metrics on dashboards.
- [ ] Every alert has owner, severity, runbook link, and runbook content.
- [ ] Routing from a service catalog with tested escalation policies.
- [ ] Watchdog/dead-man's-switch alert active.
- [ ] Alert-quality metrics reviewed monthly; noisy alerts fixed or deleted.
- [ ] Alert rules tested in CI and validated with a staging break test.
