---
name: senior-observability
description: 'Observability reference pack for production systems: OpenTelemetry architecture
  and semantic conventions, structured logging and correlation IDs, Prometheus-compatible
  metrics and cardinality control, distributed tracing and sampling, continuous profiling,
  SLOs and burn-rate alerting, dashboards, collector pipelines, telemetry cost governance,
  and per-language instrumentation patterns. Use when instrumenting a service or library,
  designing OpenTelemetry Collector pipelines, migrating from vendor APM agents, defining
  SLIs/SLOs and alerts, building dashboards or runbooks, taming metric cardinality
  or telemetry spend, correlating logs/metrics/traces/profiles during an incident,
  testing telemetry, or reviewing instrumentation quality.'
---

# Observability

Reference pack for senior observability work: OpenTelemetry, logs, metrics, traces, profiles, alerting and SLOs, dashboards, pipelines and cost, and instrumentation patterns. Depth lives in `references/`; this file is the map.

## Baseline (2026)

- OpenTelemetry is the default vendor-neutral instrumentation layer. Traces, metrics, logs, and baggage are stable; the profiles signal is still stabilizing in parts of the ecosystem — verify upstream before depending on it.
- The OTel Collector (core plus contrib) is the standard pipeline component: receivers, processors, connectors, exporters, extensions. Distributions and the Kubernetes Operator are common packaging.
- Prometheus-compatible metrics remain the default for infrastructure and platform telemetry; OTLP ingestion and native histograms have matured across the Prometheus ecosystem — verify feature-flag and storage support upstream.
- Logs converge on OTLP plus JSON; log backends increasingly accept OTLP natively rather than through proprietary agents.
- eBPF-based zero-code instrumentation and continuous profiling are mainstream for services that cannot justify per-language agents.
- Version claims in this pack are floors, ranges, or "verify upstream"; never treat them as pinned exact versions.

## Non-Negotiable Core Rules

1. Instrument once with OpenTelemetry APIs; keep SDK configuration (exporters, sampler, resource) in the application entrypoint, never in shared libraries. See `./references/09-instrumentation-patterns.md`.
2. Every log line is structured and carries `service.name`, severity, timestamp, and the active `trace_id`/`span_id` when a span exists. No unfiltered unstructured text in production. See `./references/02-logging.md`.
3. Logs, traces, and metrics share one resource identity (`service.name`, `service.namespace`, `service.version`, deployment environment). Mismatched identity is a review blocker.
4. Cardinality is a budget: no unbounded values (user IDs, raw URLs, error strings, UUIDs) in metric labels. Enforce limits at instrumentation, collector, and backend. See `./references/03-metrics.md`.
5. Tracing costs money: sample deliberately (head ratio for baseline, tail policies for errors/latency), and drop health checks, readiness probes, and static asset spans before export. See `./references/04-tracing.md`.
6. Alerts page on symptoms (latency, error rate, saturation) with a runbook link and a defined owner; cause-based alerts go to dashboards or tickets. Every page must be actionable. See `./references/06-alerting-slo.md`.
7. SLOs drive alerting: define SLIs from the user's point of view, attach error budgets, and alert on burn rate rather than raw thresholds where an SLO exists.
8. PII and secrets never enter telemetry. Redact at the source, then again in the collector; assume anything not redacted will end up in a queryable backend. See `./references/02-logging.md` and `./references/08-pipelines-cost.md`.
9. Telemetry has a budget: filter, sample, and tier retention by value. A pipeline without limits is an outage and a bill waiting to happen.
10. Instrumentation is code: it is reviewed, tested with in-memory exporters or a collector in CI, and versioned alongside the service. See `./references/09-instrumentation-patterns.md`.

## Decision Tables

### Signal Selection

| Question | Use | Reference |
|---|---|---|
| Is something slow or broken right now? | Metrics (RED/USE) for detection, traces for localization | `./references/03-metrics.md`, `./references/04-tracing.md` |
| Why did this specific request fail? | Traces plus correlated logs | `./references/04-tracing.md`, `./references/02-logging.md` |
| Which line of code consumes CPU or allocates? | Continuous profiles | `./references/05-profiling.md` |
| Is the system healthy against its obligations? | SLOs and error budgets | `./references/06-alerting-slo.md` |
| Who is affected and how do we show it? | Dashboards with drilldown | `./references/07-dashboards.md` |
| What is this costing us? | Pipeline and retention analysis | `./references/08-pipelines-cost.md` |

### Collector Topology

| Scale / constraint | Topology | Rationale |
|---|---|---|
| Single cluster, simple needs | Gateway Deployment | Central policy, one config, easy upgrades |
| Node-level enrichment needed | DaemonSet agent plus gateway | Local k8s metadata, host metrics, then export |
| High trace volume with tail sampling | Agent forward tier plus gateway with load-balancing exporter | Sticky trace routing before tail sampling |
| Strict network isolation | Sidecar per workload | Per-pod isolation; higher resource overhead |
| Serverless / managed | Direct OTLP export or managed collector | No cluster to run a collector in |

### Log Backend

| Need | Option | Notes |
|---|---|---|
| Lowest cost, Prometheus-adjacent | Loki | Label-based, cheap object storage; keep labels low-cardinality |
| Full-text search and analytics | OpenSearch / Elasticsearch | Richer queries, higher storage cost |
| SQL-style analytics on logs | ClickHouse-based stores | Strong compression and aggregation |
| OTLP-native, Grafana stack | Loki with OTLP ingest | Trace-to-logs correlation is first-class |
| Existing cloud platform | Cloud-native logging plus OTLP export | Watch egress and per-ingest pricing |

### Sampling Strategy

| Goal | Mechanism | Where |
|---|---|---|
| Uniform baseline visibility | Head sampler with ratio | SDK or collector |
| Keep all errors and slow requests | Tail sampling policies | Collector (sticky by trace ID) |
| Bound cost of high-volume debug traces | Probabilistic sampler plus drop rules | SDK or collector |
| Per-tenant or per-route control | Sampling policy by attribute | Collector routing plus sampling |
| Guarantee rare-event capture | Tail sampling with always-keep policy | Collector |

### Migration Off Vendor Agents

| Step | Action | Exit criterion |
|---|---|---|
| 1 | Inventory agents, pipelines, dashboards, alerts | Complete dependency map |
| 2 | Add OTel instrumentation alongside existing agent | Both backends receive equivalent data |
| 3 | Dual-ship via collector | No gaps during parallel run |
| 4 | Rebuild dashboards and alerts on OTLP data | Feature parity signed off |
| 5 | Cut over and decommission agents | Cost and coverage verified |

## Reference Index

| File | Scope | Load when |
|---|---|---|
| `./references/01-opentelemetry.md` | OTel architecture, API/SDK split, semantic conventions, collector deployment patterns, auto-instrumentation per language, vendor-agent migration | Starting instrumentation, choosing collector topology, migrating APM agents, resolving semconv naming |
| `./references/02-logging.md` | Structured logging, correlation IDs, levels, sampling, PII redaction, log pipelines, OTel logs vs legacy agents | Designing log schema, adding correlation, redacting data, choosing a log pipeline or backend |
| `./references/03-metrics.md` | Prometheus/OpenMetrics model, instrument types, exemplars, cardinality control, recording rules, native histograms, PromQL patterns | Adding metrics, fixing cardinality, writing PromQL or recording rules, choosing histogram strategy |
| `./references/04-tracing.md` | Spans, context propagation, head vs tail sampling, span links and events, cost control, debugging with traces | Instrumenting request flows, fixing broken trace propagation, sampling decisions, trace-based debugging |
| `./references/05-profiling.md` | Continuous profiling, CPU/heap/goroutine profiles, pprof, eBPF profilers, correlating profiles with traces | Diagnosing CPU/memory hot spots in production, adding continuous profiling, linking profiles to traces |
| `./references/06-alerting-slo.md` | SLIs/SLOs, error budgets, burn-rate alerts, symptom vs cause alerts, routing, on-call ergonomics, runbooks | Defining SLOs, fixing noisy alerts, designing routing and escalation, writing runbooks |
| `./references/07-dashboards.md` | Grafana, golden signals, RED/USE, dashboard UX, exemplar-to-trace drilldown, dashboards as code | Building or reviewing dashboards, wiring drilldowns, provisioning dashboards in CI |
| `./references/08-pipelines-cost.md` | Collector pipelines, filtering and transforms, retention tiers, sampling strategy, telemetry cost governance | Designing collector configs, reducing telemetry volume or spend, setting cardinality and retention limits |
| `./references/09-instrumentation-patterns.md` | Library vs application instrumentation, per-language conventions, span naming, testing telemetry, review checklist | Writing library or app instrumentation, naming spans, testing telemetry, reviewing instrumentation PRs |

## Load Order

- New service, greenfield: `./references/01-opentelemetry.md` then `./references/09-instrumentation-patterns.md`, then the signal references you export.
- Incident or debugging session: `./references/03-metrics.md` to detect, `./references/04-tracing.md` to localize, `./references/02-logging.md` for detail, `./references/05-profiling.md` for code-level cause.
- Reliability program: `./references/06-alerting-slo.md` then `./references/07-dashboards.md`.
- Platform or cost work: `./references/08-pipelines-cost.md` with `./references/01-opentelemetry.md` for collector topology.
- Load only the references the task needs; do not inject the whole pack into context.

## Review Workflow

For a non-trivial observability change, this is the default pass order:

1. Confirm the resource identity and semantic conventions are consistent across signals (`./references/01-opentelemetry.md`).
2. Check instrumentation at boundaries: spans, metrics, and logs for each entry and exit point (`./references/09-instrumentation-patterns.md`).
3. Verify cardinality, sampling, and redaction before data leaves the process (`./references/03-metrics.md`, `./references/04-tracing.md`, `./references/02-logging.md`).
4. Validate collector pipelines with limits, batching, and retries (`./references/08-pipelines-cost.md`).
5. Confirm alerts are symptom-based, owned, and linked to runbooks (`./references/06-alerting-slo.md`).
6. Check that dashboards answer the intended question in one screen (`./references/07-dashboards.md`).
7. Ensure telemetry tests exist and pass in CI (`./references/09-instrumentation-patterns.md`).

## Port

- **Port id** — `skill://senior/observability` (version in `metadata.port-version`, currently `2.0.0`).
- **Kind** — read-only reference pack; no side effects, no tools required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "observability" })` in OpenCode; Claude Code reads `<skills-dir>/observability/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers reference it as `load skill senior-observability (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major.

## Contract

- References are numbered `01`-`09`; keep them mutually consistent and cross-linked with relative paths.
- Version claims are floors or qualified with "verify upstream"; never present invented exact versions as fact.
- Anti-patterns and checklists close every reference; treat unchecked boxes as review findings.
- No emojis, English only, and no tooling that mutates the user's systems.
