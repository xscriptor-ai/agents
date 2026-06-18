---
description: "Observability patterns — structured logging, distributed tracing (OpenTelemetry), metrics (Prometheus, Grafana), alerting, dashboards, SLO/SLI definitions"
---

# Observability

## Three Pillars

| Pillar | What | Tooling |
|--------|------|---------|
| Logs | Discrete event records | Structured JSON logging, Loki, ELK |
| Metrics | Aggregated numeric measurements | Prometheus, Grafana, Datadog |
| Traces | Request lifecycle across services | OpenTelemetry, Jaeger, Tempo |

## Structured Logging

### Format

```json
{
  "timestamp": "2026-06-18T10:30:00Z",
  "level": "INFO",
  "logger": "order-service",
  "request_id": "req_abc123",
  "user_id": "usr_456",
  "message": "Order created",
  "order_id": "ord_789",
  "total": 49.99,
  "duration_ms": 45
}
```

### Rules

- Always JSON. No unstructured text logs.
- Always include: timestamp (RFC3339), level, request_id, service name.
- Add correlation IDs at ingress, propagate through context.
- Never log PII (emails, phone, addresses) — mask or omit.

### Log Levels

| Level | Use |
|-------|-----|
| ERROR | Someone must fix this now |
| WARN | Something unexpected but handled |
| INFO | Business-relevant events (order placed, user registered) |
| DEBUG | Development troubleshooting only (off in production) |
| TRACE | Very detailed flow (off in production) |

## Distributed Tracing with OpenTelemetry

### Setup

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider

provider = TracerProvider()
provider.add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(
        endpoint="http://otel-collector:4318/v1/traces"
    ))
)
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)
```

### Key Concepts

- **Spans**: Units of work with start/end time, attributes, status.
- **Trace**: Tree of spans linked by trace_id.
- **Context Propagation**: Pass trace/span IDs via HTTP headers (W3C Trace-Context).
- **Sampling**: Head-based (at root) or tail-based (after collection).

### Manual Instrumentation

```python
with tracer.start_as_current_span("process_payment") as span:
    span.set_attribute("payment.method", "credit_card")
    span.set_attribute("payment.amount", 49.99)
    result = payment_gateway.charge(order)
    if result.error:
        span.set_status(Status(StatusCode.ERROR, result.error))
```

## Metrics (Prometheus)

### Metric Types

| Type | Use Case | Example |
|------|----------|---------|
| Counter | Only increases | total_requests, errors_total |
| Gauge | Up and down | queue_depth, memory_usage |
| Histogram | Distribution of values | request_duration_seconds |
| Summary | Quantile estimation | p50/p95/p99 latency |

### Naming Convention

```
namespace_subsystem_unit_suffix
http_requests_duration_seconds_bucket
```

## Alerting

| Severity | Response Time | Channel | Example |
|----------|---------------|---------|---------|
| P0 (Critical) | <15 min | PagerDuty call + Slack | Site down, data loss |
| P1 (High) | <30 min | Slack @team | Latency > 5x baseline |
| P2 (Medium) | <4 hours | Slack channel | Error rate > 1% |
| P3 (Low) | <48 hours | Jira ticket | Deprecation warnings |

### Alert Rules

- Alert on symptom (latency, error rate), not cause (CPU high).
- Use `for` duration to avoid flapping.
- Route alerts to the on-call rotation.
- Every alert must have a runbook link.
- Burn rate alerts (5x over SLO window) for early warning.

## Dashboards (Grafana)

- **Service Overview**: requests, errors, latency (RED metrics) for each service.
- **Topology**: service dependency graph with health status.
- **Database**: query throughput, slow queries, connections, replication lag.
- **Infrastructure**: CPU, memory, disk, network per host.
- **Business**: DAU, transactions, revenue, sign-ups.

## SLO / SLI Definitions

| Term | Definition | Example |
|------|------------|---------|
| SLI | Measured service attribute | Request latency at p99 |
| SLO | Target value for SLI | p99 < 500ms over 30 days |
| SLA | Contractual commitment to SLO | 99.9% uptime, otherwise credit |

### SLO Calculation Window

- Rolling window (30 days) for steady-state view.
- Burn rate alerts when error budget depletes faster than expected.
- Quarterly SLO review and adjustment.

### Error Budget

```
Budget = 1 - SLO (e.g., 0.1% for 99.9% SLO)
Budget consumed = (failed_requests / total_requests) * window
```
