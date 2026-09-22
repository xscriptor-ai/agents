# Instrumentation Patterns

Scope: library versus application instrumentation, per-language conventions, span naming, testing telemetry, and a review checklist.

## Library vs Application Responsibilities

| Concern | Library | Application |
|---|---|---|
| API usage | Instrument with the OTel API only | Configure SDK and providers once |
| Provider setup | Never install a global provider | Install at startup, before serving |
| Exporters | Never configure | Choose OTLP or Prometheus path |
| Resource | Do not set service identity | Set `service.name`, version, environment |
| Sampler | Do not force sampling | Set sampler; respect parent context |
| Logging | Emit structured records via the bridge | Configure handlers, redaction, sampling |
| Attribute values | Semantic conventions; no PII | Add domain attributes at boundaries |
| Cost controls | Keep cardinality bounded | Enforce budgets and limits |

- A library that installs a global provider breaks every application that also instruments. Use the API; if no SDK is configured, calls must be no-ops.
- Instrumentation for a library belongs in the library or in a contributed instrumentation package, not copy-pasted into each application.
- Version compatibility: instrumentations track framework versions. Pin the instrumentation package and test after framework upgrades.
- Configuration surface for a library: a feature flag to disable instrumentation is acceptable; defaults must not require application changes.

## Instrumentation Points

| Boundary | Traces | Metrics | Logs |
|---|---|---|---|
| Inbound HTTP/RPC handler | Server span, `http.route`, status | Request counter, duration histogram, in-flight gauge | Structured request log with trace ID |
| Outbound HTTP/RPC call | Client span, target address | Client request counter, duration histogram | Error logs with dependency context |
| Database call | Client span with `db.*` attributes | Query counter, latency histogram | Slow-query logs, no literals |
| Message publish | Producer span plus trace context in headers | Publish counter, size histogram | Event published/consumed |
| Message consume | Consumer span linked to producer | Consume counter, lag gauge, process duration | Poison-message error logs |
| Cache | Client span, hit/miss attribute | Hit/miss counter, latency histogram | Optional |
| Background job | Root span or linked span | Job run counter, duration histogram | Start/finish with outcome |
| Key business action | Internal span | Domain counter (orders placed) | Business event log |

- Instrument at the edges of the process and at expensive internal steps. Over-instrumentation adds overhead and noise; under-instrumentation leaves blind spots at the exact boundary where incidents live.
- The rule of one: one inbound server span per request, one client span per outbound call. Duplicate spans from layered interceptors create confusing trees.
- Business metrics belong on the same dashboard as technical metrics: orders per second next to error rate.

## Span Naming and Attributes

| Element | Convention | Example |
|---|---|---|
| HTTP server span | `{method} {route}` | `GET /orders/{id}` |
| HTTP client span | `{method}` or `{method} {host}` | `POST payments-api` |
| Database span | `{operation} {table}` or `db.query {summary}` | `SELECT orders` |
| Messaging producer | `{destination} publish` | `orders publish` |
| Messaging consumer | `{destination} process` | `orders process` |
| Internal | Lowercase domain verb | `validate.cart`, `pricing.calculate` |
| Job | `job {name}` | `job nightly-reconcile` |

- Low cardinality is mandatory: no IDs, no raw paths, no SQL text, no user input in span names. High-cardinality names explode span metrics and search indexes.
- Attributes: use semantic conventions first, namespace custom attributes (`app.*`, `tenant.id`), and keep value sizes bounded. Long free-text belongs in logs.
- Error handling: set span status `ERROR` only for failed operations; record one exception event with type, message, and stack trace at the layer that handles it.
- Sensitive data: never put tokens, credentials, request bodies, or PII in span attributes or baggage.

## Metric Instrument Selection

| You want to record | Instrument | Example name |
|---|---|---|
| Number of events | Counter | `orders_created_total` |
| Current value | Gauge / UpDownCounter | `queue_depth` |
| Size or duration | Histogram | `http_request_duration_seconds` |
| In-flight operations | UpDownCounter | `http_requests_in_flight` |
| Background job outcome | Counter with `outcome` label | `jobs_completed_total` |
| Cache effectiveness | Two counters or one with `result` | `cache_requests_total{result="hit"}` |

- Prefer adding a bounded `result`/`outcome` label over multiple metric names. Keep label cardinality under control (`./03-metrics.md`).
- Set units in instrument metadata and encode them in the name where the ecosystem expects it (`_seconds`, `_bytes`, `_total`).
- Do not emit a metric per request from a high-traffic path without a histogram/counter design; cardinality is the usual failure.
- Runtime metrics (GC, heap, event loop lag, thread pools) come from auto-instrumentation or exporters; enable them, do not reimplement them.

## Telemetry Testing

```text
unit test            -> in-memory span exporter, assert span names/attributes/status
integration test     -> collector container, assert exported payload (OTLP file or debug exporter)
contract test        -> assert required resource attributes and metric names exist
CI pipeline          -> telemetry lint (attribute allowlist, naming, no PII patterns)
```

- Use an in-memory exporter (`InMemorySpanExporter`, `SimpleSpanProcessor`) to assert spans in unit tests. Assert names, key attributes, status, and parent-child structure, not every field.
- Assert metrics with a test reader: instrument a code path, collect, and check the value, labels, and type. Histograms: assert bucket boundaries and counts.
- Integration tests run the collector with the debug or file exporter and inspect the emitted payload; this catches pipeline misconfiguration that unit tests cannot.
- Golden tests for log schemas: snapshot a structured log record and fail when fields are added, removed, or renamed unintentionally.
- Test redaction explicitly: pass a payload containing a fake token or email and assert it never appears in exported telemetry.
- Assert resource identity (`service.name`, version) in at least one contract test; missing identity is invisible until an incident.
- Verify shutdown flushing in a test where feasible; telemetry lost on exit is a silent defect.
- Telemetry linting in CI: forbidden attribute names, PII patterns, missing units, span-name cardinality (regex for IDs and URLs).

## Per-Language Conventions

| Language | API/SDK | Structured logs | Typical pitfalls |
|---|---|---|---|
| Python | `opentelemetry-api` / `-sdk`, `opentelemetry-instrument` | `structlog` or stdlib logging bridge | WSGI/ASGI context loss; blocking exporter threads |
| Node.js | `@opentelemetry/api` / `-sdk-node`, preload for auto | `pino` | AsyncLocalStorage context; ESM loader requirements |
| Go | `go.opentelemetry.io/otel` | `log/slog` plus trace handler | Context must be passed explicitly; goroutine leaks |
| Java/Kotlin | OTel Java API/agent; Micrometer for metrics | Logback/Log4j2 JSON encoders | MDC context vs OTel context; agent ordering |
| Rust | `tracing` plus `tracing-opentelemetry` | `tracing` JSON layer | No global subscriber in libraries; async span guards |
| .NET | OTel .NET API/SDK, auto-instrumentation hook | `Microsoft.Extensions.Logging` JSON | Activity vs span naming; HttpClient instrumentation |
| Ruby/PHP | OTel gems/extension | Framework loggers | Short-lived processes; per-request overhead |

- Match your language's context mechanism (contextvars, AsyncLocalStorage, `context.Context`, MDC/thread-local, tracing spans) and verify propagation through the framework's async primitives.
- Framework integrations should be preferred over hand-rolled middleware; they handle header extraction, route templating, and error status correctly.
- Keep one instrumentation style per codebase. Mixing vendor SDKs and OTel APIs in the same path produces duplicate or conflicting telemetry.

## Code Review Checklist

- [ ] Resource identity set once at startup; consistent with other signals and other services.
- [ ] Libraries use API only; provider configured by the application.
- [ ] Span names low-cardinality and follow conventions; one span per operation.
- [ ] Attributes use semantic conventions; no PII, no payloads, sizes bounded.
- [ ] Errors recorded once; status set only when the operation failed.
- [ ] Metrics use the right instrument; units in name and metadata; no unbounded labels.
- [ ] Logs structured with severity and trace context; no secrets or PII.
- [ ] Propagation verified across HTTP, gRPC, and queue boundaries.
- [ ] Sampling configured and consistent with the parent decision.
- [ ] Span/metric/log limits set to guard against runaway instrumentation.
- [ ] Telemetry tests present and passing; redaction test included.
- [ ] Collector pipeline accepts the new telemetry; cardinality and volume estimated.
- [ ] Shutdown flushes telemetry with a deadline.
- [ ] Dashboards or alerts updated when metric names or labels change.

## Minimal Instrumentation Example

```python
from opentelemetry import trace, metrics
from opentelemetry.trace import Status, StatusCode

tracer = trace.get_tracer(__name__)
meter = metrics.get_meter(__name__)

requests = meter.create_counter(
    "orders_created_total", unit="{order}", description="Orders created")
latency = meter.create_histogram(
    "order_create_duration_seconds", unit="s", description="Order creation latency")

def create_order(ctx, req):
    with tracer.start_as_current_span("create_order") as span:
        span.set_attribute("app.order.channel", req.channel)
        requests.add(1, {"result": "attempt"})
        start = time.perf_counter()
        try:
            order = persist(ctx, req)
        except Exception as exc:
            span.record_exception(exc)
            span.set_status(Status(StatusCode.ERROR, "persist failed"))
            requests.add(1, {"result": "error"})
            raise
        finally:
            latency.record(time.perf_counter() - start)
        span.set_attribute("app.order.id", order.id)
        requests.add(1, {"result": "success"})
        logger.info("order created", extra={"order_id": order.id, "channel": req.channel})
        return order
```

- Labels are bounded (`result` is an enum); the order ID is a span attribute, not a metric label; the log carries the order ID in a field, not the message.
- Record the histogram on every path, including errors, or latency panels will lie about failure latency.
- The span name is stable and low-cardinality; the route and method belong in attributes for HTTP handlers (`http.request.method`, `http.route`).

## Framework and Library Boundaries

- Prefer the official instrumentation package for your framework (HTTP servers, ORMs, queue clients, gRPC). It handles context extraction, route templating, and status mapping correctly.
- When no package exists, write a thin adapter that follows semantic conventions rather than a bespoke span shape. Contribute it upstream if it is generic.
- Avoid layered instrumentation that creates duplicate spans: one server span per request, not one per middleware, unless the middleware does real work worth a span.
- For shared internal libraries (clients, repositories), instrument with spans and metrics using the API, and let the application decide the exporter and sampler.
- Watch dependency initialization order: SDK setup must run before the first instrumented client is constructed, or early calls become orphan spans.
- For serverless and short-lived processes, flush telemetry before the handler returns; batch processors may not flush automatically.

## Anti-Patterns

- Installing global providers inside libraries or twice at startup.
- Creating a new span per loop iteration or per item in a batch.
- Putting identifiers, SQL, or URLs into span names.
- Recording exceptions at every layer, producing ten copies of one stack trace.
- Metrics with user IDs, tenant-supplied strings, or error messages as labels.
- Logging and tracing the same detail twice at different levels "just in case".
- Testing only that instrumentation does not crash, never that it emits correct data.
- Copying telemetry configuration between services without adapting resource identity.
- Treating instrumentation as a one-time task instead of reviewed, tested code.

## Summary

- Instrument at boundaries, with semantic conventions, and keep identity consistent across signals.
- Libraries emit via the API; applications own SDK, sampling, redaction, and budgets.
- Telemetry is tested and reviewed like any other code path.
- Every signal has an owner, a limit, and a reason to exist; anything else is cost and noise.
