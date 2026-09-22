# Dashboards

Scope: Grafana, golden signals, RED/USE methods, dashboard UX, exemplar-to-trace drilldown, and dashboards as code.

## Purpose and Audience

| Audience | Question | Time range | Depth |
|---|---|---|---|
| On-call | Is the service healthy right now? | Minutes to hours | RED/golden signals, SLO burn |
| Incident responder | Where is the problem? | Minutes to hours | Traces, logs, dependency health |
| Service owner | How is this release behaving? | Days to weeks | Trend by version, budget, saturation |
| Capacity planning | What runs out first? | Weeks to quarters | Growth, headroom, forecasts |
| Business | Are users getting value? | Days to months | Funnels, transactions, revenue |

- One dashboard, one question. If a panel does not help answer the title question, it belongs on another dashboard.
- Order panels top-down by urgency: health and SLO first, then failure modes, then dependencies, then capacity.
- Time ranges and refresh intervals are part of the design. A 5-second auto-refresh on a 90-day panel is a query-cost anti-pattern.

## Methods

| Method | For | Signals |
|---|---|---|
| Golden signals | User-facing services | Latency, traffic, errors, saturation |
| RED | Request-driven services | Rate, errors, duration |
| USE | Resources (CPU, memory, disk, network) | Utilization, saturation, errors |
| Four golden signals plus dependency health | Distributed systems | Golden signals plus queue age and pool state |
| Event/cost views | Platform and FinOps | Deploys, incidents, telemetry spend |

- RED answers "is the service well?"; USE answers "is the resource well?". Most service dashboards need RED plus the saturation signals that predict RED failures.
- Latency panels should show a distribution shape (p50/p90/p99 or a heatmap), not just one number. The mean hides everything that matters.
- Traffic panels should show the unit users care about (requests, jobs, messages), and be labeled with the unit. "Ops" is meaningless.
- Errors: show error ratio, not just counts, and split client versus server errors. A count spike can be traffic growth.
- Saturation: queue depth, queue age, connection pool usage, thread/goroutine pools, memory pressure. Queue age is often the earliest warning of overload.

## Grafana Building Blocks

| Concept | Use |
|---|---|
| Datasources | Prometheus-compatible, Loki, Tempo, Pyroscope, ClickHouse, cloud stores |
| Variables | `service`, `environment`, `region`, `cluster`, `version`; cascade when possible |
| Transformations | Join, reduce, rename, calculate; keep logic in queries if the datasource can do it |
| Annotations | Deploys, incidents, feature flags, batch windows |
| Referencing | Data links, dashboard links, panel links, trace/log drilldown |
| Thresholds and units | Set explicit units and color thresholds tied to SLOs |
| Rows and repeats | Repeat by variable to scale without duplicating panels |

- Variables should default to something useful (`$service` with a sensible default, `$env=prod`) so the dashboard opens with data.
- Service and environment labels must exactly match the resource attributes defined in `./01-opentelemetry.md`; drift between the datasource label and the variable is the most common broken dashboard.
- Color thresholds must come from SLOs: green inside budget, yellow approaching, red burning. Green/red that does not map to an objective is decoration.
- Statistics panels for single numbers (current error budget, deploy version), timeseries for trends, heatmaps for latency distributions, tables for top-N and per-instance detail.
- Keep one dashboard "entrypoint" per service with links to detail dashboards, runbooks, logs, and traces.

## Drilldown Paths

```text
dashboard panel (p99 latency spike)
  -> exemplar (trace_id on the bucket)
    -> trace view (critical path, slow span)
      -> span profile (function consuming time)      [./05-profiling.md]
      -> logs filtered by trace_id                    [./02-logging.md]
      -> RED metrics for the downstream service       [./03-metrics.md]
```

- Exemplars only work when the SDK, scrape/OTLP path, backend, and datasource all carry them. Verify one known-slow request makes the full jump before declaring the drilldown done.
- Trace-to-logs needs the trace ID in the log backend and a consistent field name. Trace-to-metrics needs span-metrics or service-graph data.
- Data links should open in the same time range and with the same service variable. Passing the wrong range is a silent source of confusion.
- For incidents, provide one "triage board" that pulls the golden signals of the affected service and its critical dependencies side by side, plus deploy annotations.
- Avoid dead ends: every panel that can indicate a problem should link somewhere actionable.

## Dashboards as Code

| Approach | Fit | Notes |
|---|---|---|
| Grafana provisioning with JSON | Small teams, stable dashboards | Files in git, applied by Grafana or a sidecar |
| Grafonnet / Jsonnet | Many similar dashboards | Programmatic generation; reviewable diffs |
| Terraform provider | Platform teams managing many resources | Dashboards alongside alerts and datasources |
| Dashboard API in CI | Custom workflows | Validate JSON and apply on merge |

- Version dashboards in the same repository as alerts and collector config. An alert without its dashboard is half a system.
- Review dashboard diffs like code: query changes are behavior changes, especially for SLO panels and thresholds.
- Lint for common defects: missing units, missing datasource variable, hardcoded service names, unbounded `.*` regexes, missing `$__rate_interval`.
- Never edit production dashboards by hand without exporting them back to git; drift is guaranteed otherwise.
- Name dashboards with a consistent scheme (`Service / Overview`, `Service / Dependencies`, `Platform / Cluster`) so search works.

## Query Cost and Performance

- Every panel runs queries on every refresh. A dashboard with 40 panels and 30-second refresh can generate more load than production traffic.
- Prefer recording rules for expensive aggregations (`./03-metrics.md`) and query those. Panels should rarely do heavy `sum by` over raw high-cardinality metrics.
- Use `$__rate_interval` or a fixed range larger than the scrape interval; too-short ranges produce artifacts and gaps.
- Cap lookback windows on top-N tables and logs panels; unbounded time ranges are the classic cause of query timeouts during incidents.
- Set per-datasource and per-panel timeouts, and design the dashboard to degrade (fewer panels, longer intervals) under load.
- High-cardinality log queries (`{} |= "..."`) can be expensive; constrain by label first, then text.

## Reference Layout: Service Overview

| Row | Panels | Query shape |
|---|---|---|
| Health | SLO budget remaining, burn rate, current version | Recording rules from `./06-alerting-slo.md` |
| Traffic | Requests/sec by route, active connections | `sum by (route) (rate(http_requests_total[5m]))` |
| Errors | Error ratio, errors by class, top failing routes | `sum by (route) (rate(...{status=~"5.."}[5m]))` |
| Latency | p50/p95/p99, latency heatmap, slowest routes | `histogram_quantile` over `_bucket` or native |
| Saturation | In-flight, queue depth, queue age, pool usage | Gauges and `rate` over wait counters |
| Dependencies | Per-dependency latency and error ratio, service graph | Client span metrics or `servicegraph` connector |
| Runtime | Memory, GC pauses, goroutines/threads, event-loop lag | Auto-instrumentation runtime metrics |
| Deploys | Versions over time, deploy annotations, error ratio by version | `_info` series and annotations |

- Latency and error panels must share the same route breakdown so a spike in one is immediately comparable in the other.
- Version panels expose regressions that averages hide: plot error ratio and latency by `service.version` after every deploy.
- Dependencies row is what turns "our service is slow" into "our service waits on payments"; keep it adjacent to latency.
- For batch and queue systems, replace the traffic row with throughput, backlog, and oldest-message-age panels.

## Provisioning and Linting

```yaml
# Grafana provisioning: dashboards loaded from version control
apiVersion: 1
providers:
  - name: observability
    orgId: 1
    folder: services
    type: file
    disableDeletion: true
    updateIntervalSeconds: 30
    options:
      path: /etc/grafana/dashboards
```

```json
{
  "title": "Order API / Overview",
  "uid": "order-api-overview",
  "tags": ["service", "red"],
  "templating": {"list": [{"name": "env", "type": "custom", "query": "prod,staging"}]},
  "panels": [{"type": "timeseries", "datasource": {"type": "prometheus", "uid": "${DS}"}}]
}
```

- `uid` is the stable identity used in links; never auto-generate it, and keep it unique across environments.
- Provision read-only dashboards in production and export any ad-hoc edits back to code; use folders and tags for discoverability.
- CI lint checklist: valid JSON, resolvable datasource UIDs, explicit units, no hardcoded service names, `$__rate_interval` used for rates, and thresholds aligned with SLOs.
- Validate queries in CI against a test datasource where possible; a dashboard whose queries error is worse than no dashboard because it hides real data.
- Generate repetitive dashboards (one per service) from a template so an onboarding change is one pull request, not a copy-paste across dozens of files.
- Record a screenshot or rendered snapshot in the pull request for UX changes; dashboard review is visual and diff review alone misses layout regressions.

## Anti-Patterns

- Wallpaper dashboards: dozens of panels, no ordering, no owner, no question answered.
- Panels without units or with misleading units (`seconds` showing milliseconds).
- Averages for latency; percentiles without a distribution view.
- Hardcoded service or environment filters instead of variables.
- Auto-refresh faster than the data resolution.
- SLO panels that do not match the SLO definition used for alerting.
- Exemplar drilldown configured but broken at one hop.
- Dashboards owned by nobody and updated only during incidents.
- Hand-edited production dashboards never committed to git.

## Checklist

- [ ] Each dashboard has a stated question, an owner, and a consistent name.
- [ ] Golden signals / RED at the top; saturation and dependencies below.
- [ ] Units, thresholds, and colors tied to SLOs and documented.
- [ ] Variables for service, environment, and cluster; useful defaults.
- [ ] Deploy and incident annotations enabled.
- [ ] Exemplar-to-trace and trace-to-logs drilldowns verified end to end.
- [ ] Expensive panels backed by recording rules; query ranges bounded.
- [ ] Dashboards provisioned from code and reviewed via pull requests.
- [ ] Triage board exists for incidents and links to runbooks.
