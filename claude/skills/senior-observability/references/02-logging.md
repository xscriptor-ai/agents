# Logging

Scope: structured logging, correlation IDs, level policy, sampling, PII redaction, log pipelines, and the OTel logs model versus legacy agents.

## Logs as Data, Not Prose

| Property | Good | Bad |
|---|---|---|
| Format | One JSON object per line, newline-delimited | Multi-line stack traces as separate events |
| Timestamp | RFC3339 with offset, UTC | Local time without offset |
| Severity | Explicit `level`/`severity_text` field | `"ERROR:"` buried in a message string |
| Message | Stable, event-like (`order created`) | Interpolated prose (`Order 123 for bob created in 45ms`) |
| Detail | Structured fields (`order_id`, `duration_ms`) | Values only embedded in the message |
| Identity | `service.name`, `service.version`, environment | Missing or inconsistent |
| Correlation | `trace_id`, `span_id`, request ID | None |

```json
{"timestamp":"2026-04-02T10:30:00.412Z","severity_text":"INFO","severity_number":9,
 "service.name":"order-api","service.version":"2f9c1ab","deployment.environment.name":"prod",
 "trace_id":"4bf92f3577b34da6a3ce929d0e0e4736","span_id":"00f067aa0ba902b7",
 "http.request.method":"POST","http.route":"/orders","order_id":"ord_789","duration_ms":45}
```

- Prefer event-style messages that are stable across releases; every variable belongs in a field. Then a log line is queryable and a dashboard never breaks because a message was reworded.
- Use the OpenTelemetry log data model as the target shape: timestamp, observed timestamp, severity number and text, body, attributes, resource, trace ID, span ID. OTLP log exporters map native logging libraries into this model.
- Do not log an object's `repr`, `String()`, or `toString()` blindly: it leaks secrets, creates unstable schemas, and bloats volume. Log selected fields.

## Correlation IDs

| Layer | Identifier | Propagation |
|---|---|---|
| Edge / ingress | Request ID | Header (`X-Request-ID` or W3C `traceparent`) |
| Service calls | `trace_id` / `span_id` | W3C Trace Context headers |
| Async / queues | `trace_id` plus message attributes | Producer injects, consumer extracts |
| Batch jobs | Job run ID | Job context, carried into every log |
| User journey | Session or correlation ID | Low-trust identifier; treat as PII |

- The best correlation ID is the trace ID. Bridge your logging library to the OTel context so every log record during a span automatically carries `trace_id` and `span_id`.
- If a request has no incoming trace context and tracing is enabled, start a span at the edge rather than inventing a parallel correlation scheme. If tracing is not enabled, generate a request ID once at ingress, store it in request-scoped context, and include it on every log and outbound call.
- Log the identifiers, not the payloads. Correlation IDs unlock the raw data in other signals; they are not a reason to copy request bodies into logs.
- Downstream services should log the upstream request ID only if it is needed for causality; the trace ID already provides end-to-end linkage.

## Severity Policy

| Level | Meaning | Production default | Examples |
|---|---|---|---|
| FATAL | Process cannot continue | Always on; page | Data corruption detected, failed to bind |
| ERROR | Operation failed, not self-healed | Always on; page or ticket by SLO | Payment charge failed, handler returned 5xx |
| WARN | Unexpected but handled | On | Retry succeeded, queue backlog high |
| INFO | State change or business event | On, low volume | Service started, order shipped, config reloaded |
| DEBUG | Diagnostic detail for development | Off by default | Cache miss reason, branch selection |
| TRACE | Per-step internals | Off | Loop iterations, wire-level detail |

- Severity must be policy, not taste. Write it down: what pages, what tickets, what is noise. Review the policy every time an on-call rotation changes.
- No sensitive data at any level. `WARN` and `ERROR` are often shipped at higher retention, which makes leaks permanent.
- Use structured severity numbers where OTLP requires them; map native levels carefully (`WARN` often maps to 13, `ERROR` to 17) and verify the SDK mapping upstream.
- Errors belong at the boundary that owns recovery. A retry that succeeds at layer 2 should not also be logged as `ERROR` at layers 3 and 4; that is duplicate noise.

## Log Sampling

| Technique | Where | Effect |
|---|---|---|
| Drop DEBUG/TRACE in production | Logging config | Removes the largest, lowest-value volume |
| Per-level ratio sampling | App or collector | Bounds volume while preserving counters |
| Rate-limit per message template | App | Kills log storms from one broken path |
| Deduplicate repeated messages | Collector | Collapses "retrying and failing" floods |
| Tail sampling by trace | Collector | Keeps all logs for errors/slow traces, drops healthy verbose traces |
| Sampling logs only, keep metrics | Metrics-first design | Preserves detection while cutting text volume |

- Sample by severity, never uniformly: dropping 90 percent of random lines destroys the ability to reconstruct an incident but keeps the cost. Drop DEBUG first, then sample INFO per template, and keep errors complete.
- Log storms are an availability risk: a failing dependency can generate gigabytes per minute and saturate disk or the collector. Rate limits per logger and per template are mandatory in production.
- When tail sampling traces, correlate log sampling to the same policy so a kept trace also has its logs. Independent sampling creates traces with missing narratives.
- Count what you drop. Export a counter for dropped/sampled-out log records so "no logs" is distinguishable from "logs dropped".

## PII and Secret Redaction

| Data class | Examples | Handling |
|---|---|---|
| Authentication secrets | Passwords, tokens, API keys, cookies, `Authorization` headers | Never log; redact at source and in collector |
| Direct PII | Email, phone, address, national ID, precise location | Drop or tokenize; avoid hash-only if reversible lookup is required |
| Indirect PII | User agent, IP address, device IDs, free-text support notes | Treat as PII; consider truncation or hashing per privacy policy |
| Payment data | PAN, CVV, bank accounts | Prohibited; never enters logs |
| Request/response bodies | JSON payloads, form fields | Do not log by default; allowlist fields if needed |
| Internal identifiers | Account IDs, order IDs | Safe in logs, unsafe as metric labels |

- Redact at the source first (the code knows field semantics), then again in the collector as defense in depth. A collector-only strategy leaks the moment someone ships a new service or bypasses the gateway.
- Prefer allowlisting known-safe fields over denylisting known-bad patterns. Denylists miss `user_email`, `emailAddress`, `contact.mail`, and the next synonym.
- Redaction must survive encoding: parse structured logs before redacting, and test nested, array, and URL-encoded fields. A regex over a JSON string misses `%40` and JSON escapes.
- Secrets in exception messages are a classic leak. Wrap errors so driver/DSN strings are not rendered; rotate anything that may have been logged.
- Keep a documented data classification and a test that fails when a new field is classified PII but appears unredacted.

## Log Pipelines

| Stage | Options | Notes |
|---|---|---|
| Emit | stdout JSON, OTLP logs from SDK | Prefer stdout for containers; OTLP when the SDK owns correlation |
| Collect | Collector `filelog`/`otlp`, Fluent Bit, Vector, node agents | One log agent per node is enough; avoid stacking two |
| Process | Collector `transform` (OTTL), `filter`, `attributes`, `redaction` | Parse, normalize, redact, enrich, drop |
| Route | Collector `routing` connector | Split security logs, audit logs, and app logs |
| Store | Loki, OpenSearch/Elasticsearch, ClickHouse-based, cloud logging | Choose by query style, retention, and cost |
| Query | LogQL, KQL, Lucene, SQL | Correlate to traces via IDs |

- Normalize to one schema at the pipeline boundary: same field names, same severity vocabulary, same timestamp precision. Divergent schemas make cross-service queries impossible.
- Enrich centrally (k8s metadata, environment, service version) in the collector rather than in every application.
- Parse multiline stack traces before storage (`multiline` in the agent, or a collector operator) so one exception is one record. Otherwise every line is a separate, useless event.
- Keep label/index cardinality low. In Loki-like systems the index fields must be low-cardinality (`service.name`, environment, level); high-cardinality values belong in the body or structured metadata.
- Budget retention per stream: audit and security logs may need a year, debug logs hours. Tiered retention is the main cost lever after volume reduction.

## OTel Logs vs Legacy Agents

| Aspect | OTel logs | Legacy/agent-based logging |
|---|---|---|
| Schema | OTel log data model, resource attributes | Vendor-specific tags and attributes |
| Correlation | Native `trace_id`/`span_id` on records | Often manual or partial |
| Transport | OTLP plus collector processing | Proprietary protocol and agents |
| Vendor lock-in | Low; swap exporter or backend | High; retool dashboards and queries |
| Coverage | SDK bridges for mainstream logging libraries | Mature, framework-specific integrations |
| Processing | Collector processors, OTTL | Agent pipelines with vendor DSLs |

- Migrate by bridging the existing logging library into OTel, not by replacing the library. Keep structured logging in the app; let the SDK/bridge attach context and export.
- Dual-ship during migration: legacy backend plus OTLP. Compare record counts, severity distribution, and a few known incidents before cutting over.
- Watch out for duplicated logs when both stdout collection and OTLP export are enabled for the same process. Pick one path per service.
- Legacy agents often add host metadata automatically; in OTLP you must supply it via resource attributes or collector enrichment.

## Example Collector Pipeline

```yaml
receivers:
  filelog:
    include: [/var/log/pods/*/*/*.log]
    operators:
      - type: json_parser
      - type: multiline
        firstline: '^\d{4}-\d{2}-\d{2}'
  otlp:
    protocols: { grpc: {}, http: {} }
processors:
  memory_limiter: { check_interval: 1s, limit_percentage: 80 }
  k8sattributes: {}
  transform:
    log_statements:
      - context: log
        statements:
          - set(attributes["env"], resource.attributes["deployment.environment.name"])
  batch: {}
exporters:
  otlphttp/loki: { endpoint: "http://loki:3100/otlp" }
service:
  pipelines:
    logs:
      receivers: [filelog, otlp]
      processors: [memory_limiter, k8sattributes, transform, batch]
      exporters: [otlphttp/loki]
```

- Parse, enrich, and normalize at the collector so applications stay simple and the schema is uniform across languages.
- Keep one collection path per workload. Running a node log agent and OTLP log export for the same service doubles volume and confuses operators.
- Validate pipeline changes with the collector's config validation and a staging run; a malformed `transform` statement can silently drop fields or records.

## Schema and Query Hygiene

- Keep a versioned schema document: field name, type, meaning, sensitivity class, and example. New fields are reviewed against it, and renaming is a breaking change.
- Use a small set of common fields across services (`service.name`, level, message, trace_id, span_id, request_id, error.type) and namespace service-specific fields (`orders.order_id`).
- Query by field, not by message text. Text search is the fallback for unexplored data, not the primary interface.
- Avoid scanning unbounded time ranges in log queries. Constrain by label, then field, then text, and set limits on result size.
- Keep error messages stable enough to group: normalize variable values out of the message and into fields so identical failures cluster.
- Retain a small "canary" query set per service (errors, slow requests, security events) and run it after schema or pipeline changes to catch regressions.

## Anti-Patterns

- Unstructured `printf` logging in production code paths.
- Logging inside tight loops or per row of a batch job; log once per batch with counts.
- Copying full request/response bodies "for debugging" into production logs.
- Different field names for the same concept across services (`user_id`, `userId`, `uid`).
- Alerting on log text patterns as the primary detection path when metrics would be cheaper and more stable.
- Indexing high-cardinality fields (trace ID, user ID) as log labels.
- Logging secrets or tokens during error handling and never rotating them.
- Retaining DEBUG at production volume because "storage is cheap" — it is not, and it hides signal.

## Checklist

- [ ] Newline-delimited structured logs with stable field names and a documented schema.
- [ ] `trace_id` and `span_id` automatically attached through the logging bridge.
- [ ] Severity policy documented: what pages, what tickets, what is noise.
- [ ] Per-template rate limits and level-based sampling in production.
- [ ] Source-level redaction plus collector-level redaction, with tests for nested and encoded fields.
- [ ] Multiline stack traces parsed before storage.
- [ ] One collection path per service (stdout or OTLP), no duplicates.
- [ ] Low-cardinality index fields; high-cardinality values in body or structured metadata.
- [ ] Retention tiers by log class; dropped-record counters exported.
