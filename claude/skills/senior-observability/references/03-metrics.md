# Metrics

Scope: Prometheus/OpenMetrics data model, instrument types, exemplars, cardinality control, recording rules, native histograms, and PromQL patterns.

## Data Model

- A metric family has a name, type, unit, and help text; it is identified by name plus label set. One unique label set is one time series.
- Samples are `(timestamp, value)` pairs. Counters are cumulative; gauges float; histograms carry bucket counts and a sum; summaries carry quantiles computed in-process.
- Exposition is pull over HTTP (`/metrics`), with push gateways and remote write for special cases. OTLP is the push-native alternative and is also accepted by Prometheus-compatible systems (verify upstream support and feature flags).
- Naming: `namespace_subsystem_name_unit_suffix`. Units are base units: `_seconds`, `_bytes`, `_total` for counters, `_info` for metadata, `_ratio` for dimensionless. `http_requests_total`, `http_request_duration_seconds`, `node_memory_used_bytes`.
- Label names are `snake_case`; label values are low-cardinality and bounded. Every label you add multiplies series count.
- Label values must never be unbounded: no user IDs, order IDs, raw paths, UUIDs, error strings, or timestamps.

## Instrument Types

| Type | Semantics | Use for | Do not use for |
|---|---|---|---|
| Counter | Monotonic, resettable on restart | Requests, errors, bytes, events | Values that can decrease |
| Gauge | Current value, up or down | Queue depth, connections, temperature, memory | Event counts |
| Histogram | Distribution with configurable buckets | Latency, request size, payload size | Values that need exact quantiles per instance |
| GaugeHistogram | Histogram of a current distribution | Snapshot distributions | Cumulative events |
| Summary | Client-side quantiles | Legacy or single-process p99 | Aggregating across instances (quantiles are not aggregatable) |
| Info | Constant metadata as a series | Build info, config version | Anything changing often |

- Histograms are aggregatable; summaries are not. For fleet-wide p99, use histograms and `histogram_quantile`, or native histograms. Never average quantiles.
- Instrument selection checklist: does it only go up (counter), does it go up and down (gauge), does the shape matter (histogram/gauge histogram)?
- Bucket boundaries are a compatibility surface. Changing buckets changes query results; version them and document the change. Choose buckets around SLO thresholds so the ratio of good to total is directly computable.
- OpenTelemetry instruments map onto this model: `Counter` to counter, `UpDownCounter` to gauge, `Histogram` to histogram, `Gauge` to gauge. Decide temporality (cumulative vs delta) once and keep it consistent; the collector can convert but conversion has edge cases.

## Cardinality Control

Series count is approximately the product of label cardinalities. It is the main driver of memory, query time, and cost.

| Source | Typical explosion | Control |
|---|---|---|
| Raw URL path | One series per ID | Use templated routes (`/orders/{id}`) |
| User/tenant ID | Millions | Aggregate; move to traces/logs |
| Error message | One per unique string | Normalize to an error class |
| Status code grouping | Acceptable (`2xx`, `5xx`) | Keep raw codes when bounded |
| Pod/host identity | Churns on every deploy | Drop from metrics used in aggregation; keep only where needed |
| UUIDs, request IDs | Unbounded | Never a label |
| Build metadata | Churns per release | Use a single `_info` series with a version label |

- Enforce at three layers: instrumentation review, collector limits (`metric_relabel_configs`, `keep`/`drop` actions, cardinality guards), and backend limits (per-tenant series limits). One layer will be bypassed eventually.
- Audit cardinality continuously: report top series counts by metric name and label set. The `scrape_series_added` metric and backend cardinality dashboards are the usual starting points.
- When a label is useful for debugging but not for aggregation, push it to traces or logs. Explore there, aggregate here.
- Relabeling can drop labels, replace values, hash, or keep only matching series. Do it centrally so every team benefits and no one has to rebuild dashboards.
- Avoid `le` collisions when creating histograms with custom buckets; duplicate bucket bounds corrupt the quantile calculation.

## Exemplars

- Exemplars attach a trace ID (and often a span ID) to a specific bucket or counter observation. They are the bridge from an aggregate spike to a concrete request.
- Enable exemplars in the histogram instrument and in the scrape path (OpenMetrics exposes them; Prometheus needs exemplar storage enabled and OTLP carries them natively).
- Use them for latency histograms and error counters. When a p99 alert fires, the exemplar links straight to a slow trace instead of a log hunt.
- Keep exemplar volume bounded; they are sampled, but they still travel. Redact anything sensitive in the trace ID itself.
- Grafana-style exemplar-to-trace drilldown depends on the datasource supporting exemplar queries and the trace backend sharing the trace ID. Verify the full path in staging.

## Recording Rules and Aggregation

- Recording rules precompute expensive or high-cardinality aggregations into stable series. Rules should produce series that dashboards and alerts consume directly; that is why rule names and labels are an interface.
- Rule hygiene: one logical aggregation per rule, descriptive names (`job:http_requests:rate5m`), labels only for dimensions users filter on (`job`, `service`, `cluster`), and a versioned file in git.
- Pre-aggregate high-cardinality raw metrics (per-route, per-instance) before storing long retention. The expensive detail can stay short-lived.
- Rule evaluation cost is real: wide `by (...)` clauses with high-cardinality labels re-create the cardinality you were avoiding. Cap `group_left`/`group_right` joins and prefer `sum by` over `sum`.
- Test rules with `promtool test rules` (or the Prometheus-compatible equivalent) in CI; rule errors are outages in alerting.
- `for:` durations, `keep_firing_for`, and staleness handling belong in alerting rules, not recording rules.

## Query Patterns

```promql
# Request rate by service over 5 minutes
sum by (service) (rate(http_requests_total[5m]))

# Error ratio against total, guarding against division by zero
sum(rate(http_requests_total{status=~"5.."}[5m]))
  / clamp_min(sum(rate(http_requests_total[5m])), 1)

# p99 from classic histogram buckets
histogram_quantile(0.99,
  sum by (le, service) (rate(http_request_duration_seconds_bucket[5m])))

# p99 from native histograms
histogram_quantile(0.99, sum by (service) (rate(http_request_duration_seconds[5m])))

# Saturation: queue wait time
rate(queue_wait_seconds_total[5m]) / clamp_min(rate(queue_items_total[5m]), 1)

# Absence detection
absent(up{job="order-api"} == 1)
```

- Use `rate` on counters (it handles resets), never on gauges. `increase` answers "how many in this window" but is extrapolation-sensitive; prefer `rate * window_seconds` for consistent math.
- `$__rate_interval` (Grafana) or a fixed `[5m]` larger than the scrape interval prevents gaps and counter reset artifacts.
- Use subqueries and `@` modifiers when you must align windows; keep them rare and documented, because they are expensive.
- `topk`, `bottomk`, and `quantile` operate per evaluation step and can flap; use them in dashboards with `max_over_time` or `last_over_time` where stability matters.
- Prefer `sum by` over `sum` only for the dims you need; every extra `by` dimension multiplies output series.
- `absent()` and `up == 0` are the two ways to detect missing telemetry; a dashboard that cannot distinguish "zero" from "no data" is lying.

## Push, Pull, and Storage

| Path | Mechanism | Use when |
|---|---|---|
| Scrape | Prometheus pulls `/metrics` | Kubernetes and VM fleets; standard for infrastructure |
| Pushgateway | Short-lived jobs push finals | Batch jobs; never for long-running services |
| Remote write | Prometheus forwards to a store | Long-term retention, multi-cluster aggregation |
| OTLP | SDK pushes to collector/backend | OTel-native stacks and push-only networks |
| Agent mode | Prometheus scrapes and remote-writes | Large fleets needing local aggregation |

- Retention tiers: high-resolution raw data hot (days), downsampled or recording-rule aggregates warm (weeks), rollups cold (quarters). Choose per signal value, not per default.
- Long-term stores (Mimir, Thanos, VictoriaMetrics, cloud-managed) add multi-tenancy, object storage, and global query. Costs track active series and query load more than raw bytes; measure both.
- Prometheus 3.x era notes: UTF-8 metric name support, OTLP ingestion improvements, native histogram maturity across the ecosystem — verify feature flags and backend support upstream before standardizing.
- Native histograms remove the bucket-boundary problem and reduce series count for high-cardinality distributions, but tooling, federation, and query ergonomics are still catching up. Run them alongside classic histograms during transition.
- Exporters: node exporter for hosts, kube-state-metrics for object state, language-specific exporters for runtime metrics, and application `/metrics` for domain metrics. One exporter per concern; avoid duplicate scrape targets.

## Scrape Configuration and Relabeling

```yaml
scrape_configs:
  - job_name: order-api
    kubernetes_sd_configs: [{ role: pod }]
    metrics_path: /metrics
    scrape_interval: 15s
    scrape_timeout: 10s
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
      - source_labels: [__meta_kubernetes_pod_label_app]
        target_label: service
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
        action: replace
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: "(go_gc_duration_seconds|process_open_fds)"
        action: drop
```

- Scrape intervals follow detection needs: 10-15 s for user-facing services, 30-60 s for infrastructure fleets, and longer for slow-moving capacity metrics. Align the `for:` durations in alerts with the interval.
- `scrape_timeout` must be lower than `scrape_interval`, or scrapes overlap and pile up. A timeout is a data-quality incident, not a retry opportunity.
- Target limits: set sample and series limits per scrape; a single target with millions of series can take down the server.
- Use `honor_labels` deliberately, and avoid labelless collisions when merging multiple exporters. Two targets producing the same series are silently deduplicated or rejected.
- Prefer ServiceMonitor/PodMonitor or annotation-based discovery for Kubernetes so onboarding is declarative and reviewable.
- Scrape via the collector or an agent (agent mode, remote write) when you need local filtering or many clusters; scrape directly for small, trusted fleets.

## Native Histogram Migration

| Step | Action | Check |
|---|---|---|
| 1 | Measure classic bucket fit for key services | Are SLO thresholds inside existing buckets? |
| 2 | Enable native histograms on a subset of exporters | Backend and remote-write support confirmed |
| 3 | Dual-emit classic plus native during transition | Both query paths return consistent results |
| 4 | Update recording rules and dashboards to native queries | `histogram_quantile` without `le` grouping |
| 5 | Retire classic buckets when no downstream depends on them | Alerts and dashboards audited |

- Native histograms shrink series count dramatically for high-dimension latency metrics: one series instead of `le` times the labels.
- They support higher resolution and cheaper quantile queries, but federation, downsampling, and some managed services lag. Verify every hop in your path upstream.
- Mixed deployments are normal: some exporters and remote-write receivers support them, others do not. Dual-emit until the whole path is native.
- Query differences are subtle: native quantile functions do not use the `le` label, and rate semantics differ. Test against classic results before migrating alerts.
- Keep buckets for SLO thresholds even in a native world: converting a ratio of counts to a direct good/total computation is often simpler and easier to reason about than quantiles.

## Anti-Patterns

- Averaging quantiles or averages across instances instead of aggregating histograms.
- One histogram per route with 30 custom buckets per route per instance per status code.
- Using a summary because it is easy, then discovering it cannot be aggregated fleet-wide.
- Adding a `user_id` or `request_id` label "temporarily".
- Recording rules that do not correspond to a dashboard or alert, burning CPU for nothing.
- Alerting on raw `rate()` thresholds when an SLO burn-rate alert is the correct abstraction.
- Scraping every instance every 5 seconds by default; pick intervals from detection needs.
- Leaving `up` and scrape error metrics unmonitored, so missing data looks like health.

## Checklist

- [ ] Naming follows `namespace_subsystem_name_unit_suffix`; units are base units.
- [ ] Counters only increase; gauges used for fluctuating values; histograms for distributions.
- [ ] No unbounded labels; cardinality budget documented per service.
- [ ] Histogram buckets chosen around SLO thresholds; changes versioned.
- [ ] Exemplars enabled on latency histograms and drilldown verified end to end.
- [ ] Recording rules named, versioned, tested in CI, and consumed by dashboards/alerts.
- [ ] Alerting and dashboards distinguish zero from no data (`absent`/`up`).
- [ ] Retention tiers and long-term storage path defined before volume grows.
- [ ] Cardinality dashboards reviewed regularly by service owners.
