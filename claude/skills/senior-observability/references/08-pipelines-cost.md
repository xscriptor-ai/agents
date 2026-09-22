# Pipelines and Cost

Scope: collector pipelines, filtering and transforms, retention tiers, sampling strategy, and telemetry cost governance.

## Pipeline Anatomy

```text
receivers -> processors -> exporters        (per signal pipeline)
              |                            connectors bridge pipelines
              +-> alternatives: fan out, route, sample, aggregate

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, k8sattributes, filter, tail_sampling, batch]
      exporters: [otlp/backend]
```

- One pipeline per signal and per destination. Use the `routing` connector for multi-tenant or multi-region fan-out instead of duplicating processors.
- Processor order is functional: limit memory first, enrich early, filter/transform before sampling, batch last.
- `memory_limiter` must be first and configured with a hard/soft limit and a check interval; it is the difference between backpressure and OOM.
- `batch` tuning: larger batches reduce network calls but add latency and memory. For traces, batch by span count and size; for metrics, keep scrape-aligned timing.
- Queueing and retry belong on exporters (`sending_queue`, `retry_on_failure`). Enable persistent queues only when durable delivery matters more than disk and throughput.
- Self-telemetry: export collector metrics (accepted, refused, dropped, queue length, batch size) and alert on refusals and queue saturation.

## Filtering and Transforms

| Processor | Purpose | Typical use |
|---|---|---|
| `filter` | Drop spans/logs/metrics by condition | Drop `/healthz`, readiness, static assets |
| `transform` (OTTL) | Rename, set, delete, parse attributes | Normalize schemas, redact, add routing keys |
| `attributes` | Add/update/delete attributes | Add environment, delete internal fields |
| `resource` | Modify resource attributes | Force `deployment.environment.name` |
| `redaction` | Mask sensitive values by pattern | Strip tokens, emails, card-like numbers |
| `k8sattributes` | Attach pod/namespace/deployment metadata | Agent tier enrichment |
| `resourcedetection` | Detect cloud/host metadata | Enrich once at the gateway |
| `probabilistic_sampler` | Sample by trace ID ratio | Baseline volume control for traces/logs |
| `tail_sampling` | Outcome-based trace sampling | Keep errors and slow traces |
| `metricstransform` | Aggregate/rename metrics | Cardinality reduction, unit normalization |
| `delta`/`cumulative` | Temporality conversion | Match backend expectations |

- OTTL is the expression language for filtering and transforms. Write conditions against attributes and resource, and test with the collector's dry-run or validation mode before rollout.
- Filter as early and as cheaply as possible: at the agent for per-request noise, at the gateway for policy. Filtering after storage is a cost, not a saving.
- Never drop errors or security events with broad filters; scope filters to known-noise routes and require a comment plus an owner for each rule.
- Transformations are an interface: renaming a metric or attribute breaks dashboards, alerts, and saved queries. Treat changes as breaking and version them.
- Validation: reject unknown attributes, enforce enum values, truncate long strings, and drop payload-like fields (request/response bodies) unless explicitly allowlisted.
- Keep one owner per pipeline. Shared processors with per-tenant branches grow into unmaintainable configuration; use `routing` plus separate config files.

## Sampling Strategy by Signal

| Signal | Baseline mechanism | Outcome-based layer | Hard cap |
|---|---|---|---|
| Traces | Head ratio (deterministic by trace ID) | Tail sampling: errors, latency, attributes | Per-tenant rate limit |
| Logs | Level filtering, per-template rate limit | Align with kept traces for incidents | Max bytes per second |
| Metrics | Aggregation and relabeling; nothing to sample | N/A | Series limits per metric |
| Profiles | Lower sampling frequency | Higher fidelity on demand | Egress rate limit |

- Decide the sampling budget per signal and per tenant, not once globally. One noisy tenant should not exhaust everyone else's budget.
- Tail sampling requires sticky routing (`./04-tracing.md`); metrics cannot be tail-sampled, they are reduced through aggregation and label dropping.
- Log volume reduction order: remove DEBUG, rate-limit templates, drop duplicate storms, then sample INFO. Keep ERROR/security complete.
- Document what sampling preserves: "all errors, all requests over 1 s, 5% of the rest". That sentence is what on-call needs to interpret dashboards.

## Retention Tiers

| Tier | Resolution/Completeness | Typical retention | Storage |
|---|---|---|---|
| Hot | Full resolution, fast queries | Hours to days | Local SSD, memory-cached stores |
| Warm | Downsampled or aggregated | Weeks | Object storage with query cache |
| Cold | Rollups, compliance copies | Months to years | Object storage, cheapest class |

- Retention follows value, not signal type. Audit and security logs may need a year; debug logs hours; raw traces days; SLO rollups quarters.
- Downsample deliberately: keep the SLO-relevant aggregates at full fidelity, and let high-cardinality detail expire first.
- Object storage is the cost floor for logs, traces, and metrics blocks (Mimir, Thanos, Loki, Tempo, and similar). Query cost then depends on index design and cache hit rate.
- Egress and cross-region replication are frequently larger than storage costs. Keep queries and storage in the same region; replicate only what compliance requires.
- Document retention per signal and data class; if a regulator or customer asks, the answer must be findable in one place.

## Cost Governance

| Cost driver | Where it hits | Lever |
|---|---|---|
| Active metric series | Memory and query load | Cardinality limits, relabeling, aggregation |
| Trace volume | Ingest and storage per span | Head plus tail sampling, drop noise spans |
| Log bytes | Ingest, index, storage | Level filtering, rate limits, compress, drop duplicates |
| Query load | Backend CPU, concurrency | Recording rules, dashboard hygiene, query limits |
| Retention | Storage class and replication | Tiered retention, lifecycle policies |
| Network egress | Cross-AZ/region transfer | Co-locate collectors and storage; batch |
| Profiles | Egress and storage per sample | Frequency tuning, shorter retention for correlated data |

- Make cost visible per service, per tenant, and per team. Chargeback or showback changes behavior faster than any policy memo.
- Budget per signal and per tenant, and alert on budget consumption before the invoice arrives. Cardinality is a leading indicator; bill is a lagging one.
- Define unit economics: cost per million spans, per GB of logs, per million series, per active service. Track trends over releases and traffic growth.
- Guardrails: per-tenant series limits, ingest rate limits, max attribute sizes, and a review gate for new high-volume telemetry.
- Data-quality gate: before optimizing storage, delete telemetry nobody queries. Unused dashboards, stale exporters, and orphaned pipelines are pure cost.
- Ownership: each service owns its telemetry volume and cost. Central platform teams provide the pipeline, limits, and reporting, not unlimited capacity.
- Procurement: negotiate on ingest plus query plus egress; vendors discount differently for each. Bring real usage data to renewals and test portability with OTLP.

## Capacity and Reliability

- Size collectors by throughput per core, not guesswork: measure spans/logs/bytes per second per instance under peak, then leave headroom for retries and bursts.
- Horizontal scaling: agent tier scales with nodes; gateway tier scales with throughput and needs sticky routing for tail sampling.
- Graceful degradation order: refuse new data with clear metrics, drop low-priority signals first, and never fail the application because telemetry is down. The SDK must be non-blocking.
- Backend outage behavior: bounded queues with retries and disk fallback where supported; on sustained outage, drop and count rather than exhaust disk and take down the node.
- Test failure modes: kill the backend, saturate the collector, corrupt a pipeline config; verify alarms fire and applications are unaffected.
- Version pin collector and agents; upgrade staging first. Config schemas change across minor releases, and components can be deprecated or moved between core and contrib.

## Cost Estimation Worksheet

| Input | Value | How to measure |
|---|---|---|
| Request rate | req/s | Ingress metrics |
| Spans per request | spans/req | Sampling of production traces |
| Average span size | bytes | Export payload size / span count |
| Log lines per request | lines/req | Log backend ingest counters |
| Average log line size | bytes | Collector or backend ingest |
| Active series per service | series | `scrape_series_added`, backend cardinality API |
| Retention hot/warm/cold | days | Storage configuration |
| Egress per GB | price | Vendor contract |

```text
span GB/day   = req/s * spans/req * bytes/span * 86400 / 1e9
log GB/day    = req/s * lines/req * bytes/line * 86400 / 1e9
series cost   = active_series * price_per_series_month
monthly total = (span + log + profile GB/day * 30 * ingest+storage price)
              + series cost + egress + query cost
```

- Do the estimate before onboarding a new service or raising sampling. It takes ten minutes and prevents the quarterly surprise.
- Measure bytes/span and bytes/line with real payloads, not guesses; semantic-convention attributes and long stack traces dominate.
- Cost per million requests is the KPI to track quarter over quarter. Volume growth is fine if unit cost falls; flat unit cost with exploding volume is not.
- Include query cost: a dashboard refresh every 30 seconds on a 40-panel board can exceed the ingest cost in a busy backend.

## Collector Config Examples

```yaml
# Drop health checks and static assets before export
processors:
  filter/denoise:
    error_mode: ignore
    traces:
      span:
        - 'attributes["http.route"] == "/healthz"'
        - 'attributes["http.route"] == "/readyz"'
        - 'attributes["url.path"] matches "^/static/.*"'

# Truncate long attribute values and drop payload-like fields
  transform/limits:
    trace_statements:
      - context: span
        statements:
          - truncate_all(attributes, 256)
          - truncate_all(resource.attributes, 256)
          - delete_key(attributes, "http.request.body")
          - delete_key(attributes, "http.response.body")
```

- Test filter conditions against exported sample data before rollout; a wrong OTTL condition can erase a whole signal class silently.
- Keep filter and transform rules close together and commented with owner and reason, because nobody remembers why a rule exists six months later.
- Apply limits at the agent tier for volume reduction and at the gateway for policy; duplicate rules are acceptable when they serve different owners.
- Export dropped-data counters so filtering is measurable rather than folkloric.

## Anti-Patterns

- A single huge pipeline for every signal and tenant with no filtering.
- Memory limiter missing or configured as the last processor.
- Filtering after export "for simplicity", paying for data you then discard.
- Sampling metrics; reducing them only through aggregation and label discipline.
- Keeping raw traces and debug logs at the same retention as SLO rollups.
- One collector replica with no PDB, so an upgrade is an observability outage.
- Tail-sampling gateway without sticky routing, producing partial traces.
- No cost attribution, so the platform team absorbs every team's telemetry growth.
- Committing to a vendor's ingest discount without structuring data for portability via OTLP.

## Checklist

- [ ] Pipeline per signal with `memory_limiter` first and `batch` last.
- [ ] Enrichment centralized; redaction applied at source and in the pipeline.
- [ ] Filters are specific, owned, and reviewed; errors and security events preserved.
- [ ] Sampling documented per signal and per tenant, with hard caps.
- [ ] Retention tiers mapped to data value and compliance needs.
- [ ] Cost visible per service/tenant with budgets and alerts.
- [ ] Collector self-telemetry exported; refusal and queue metrics alerted.
- [ ] Capacity measured under peak; gateway tier scales horizontally with sticky routing.
- [ ] Backend-outage behavior tested; applications unaffected by telemetry failure.
- [ ] Collector/config versions pinned and upgraded via staging first.
