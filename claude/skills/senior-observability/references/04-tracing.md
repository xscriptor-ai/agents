# Tracing

Scope: spans and trace structure, context propagation, head versus tail sampling, span links and events, cost control, and debugging with traces.

## Span Model

| Field | Meaning | Rules |
|---|---|---|
| Trace ID | 16-byte identifier shared by all spans in a trace | Generated once at the root; propagated everywhere |
| Span ID | 8-byte identifier for one operation | Unique within the trace |
| Parent span ID | Causal parent | Empty for the root; sets the tree shape |
| Name | Operation label | Low cardinality: `GET /orders/{id}`, `db.query orders`, not raw values |
| Kind | `server`, `client`, `producer`, `consumer`, `internal` | Determines conventions and topology reconstruction |
| Start/end time | Duration | Clock skew across hosts is expected; do not over-trust absolute order |
| Attributes | Key/value metadata | Semantic conventions first; bounded values |
| Status | `UNSET`, `OK`, `ERROR` | `ERROR` means the operation failed, not that an HTTP 4xx happened |
| Events | Timestamped annotations on a span | Exceptions, retries, state transitions |
| Links | Causality to other spans/traces | Batch fan-in, async handoffs, retries |

```text
trace 4bf92f3577b34da6a3ce929d0e0e4736
├─ server GET /checkout              [frontend]        210 ms  OK
│  ├─ client POST /payments          [frontend]        120 ms  OK
│  │  └─ server POST /payments       [payments-api]    118 ms  OK
│  │     ├─ client INSERT payments   [payments-api]     34 ms  OK
│  │     └─ event payment.captured   [payments-api]        0 s OK (link -> settlement)
│  └─ client GET /cart               [frontend]         40 ms  ERROR
└─ internal cache.warm               [frontend]          5 ms  OK
```

- One trace per user-visible transaction. A trace that spans an async queue boundary is fine; a trace that spans unrelated requests is not.
- Prefer attributes over span names for detail. Renaming spans because an ID changed breaks dashboards and alert queries.
- Span events are cheaper than child spans for instantaneous facts; child spans are correct when the work has duration and its own causality.
- Span links express "related to" without parenting: batch consumers linking to producer traces, fan-in aggregations, and retried attempts. Use them whenever time order does not equal causality.
- Exception handling: record the exception event once at the deepest layer that understands it, set the span status to `ERROR` at the boundary that owns the failure, and avoid duplicate stack traces across every span in the path.

## Context Propagation

| Transport | Mechanism | Notes |
|---|---|---|
| HTTP | W3C `traceparent` and `tracestate` headers | Default; verify proxies and CDNs forward them |
| gRPC | Metadata key `traceparent` | Interceptors inject/extract |
| Messaging | Attributes on the message (headers) | Producer injects, consumer extracts; trace continues or links |
| Database | Not standard | Do not try to propagate through SQL; link instead |
| Async runtimes | Context propagation across await/task boundaries | The instrumented library must carry context; lost context creates orphan spans |
| Thread pools | Explicit context capture and restore | Always capture the context object before submitting work |

- W3C Trace Context is the interoperable baseline. Keep B3 or vendor formats only for legacy interop, and configure multi-format propagation during migration.
- Baggage carries small, cross-cutting values (tenant, release channel) to all downstream services. It is a bandwidth and privacy risk: keep it small, redact secrets, and never put PII in it.
- The three propagation failures to hunt: broken header forwarding at a proxy or gateway, an uninstrumented async hop (queue, cron, worker), and a client library that creates a new root instead of using ambient context.
- Testing propagation: send one request through the full path and assert that every hop shares one trace ID. "Spans exist" is not the test; "one trace exists" is.
- For background jobs, start a root span (or link to the triggering trace) so batch and scheduled work is observable rather than invisible.

## Head Sampling

| Sampler | Behavior | Use when |
|---|---|---|
| `always_on` | Keep everything | Dev, low-volume, or tail sampling downstream |
| `always_off` | Drop everything | Temporarily muting a noisy producer |
| `traceidratio` | Deterministic ratio by trace ID | Uniform baseline; stable across instances |
| `parentbased_*` | Respect the upstream decision | Default in service meshes; avoids broken traces |
| Rate-limited | Adaptive target traces/sec | Unpredictable volume with a hard cap |

- Head sampling decides before the trace is complete, so it cannot keep "all errors". It is the cheap, predictable layer.
- Determinism matters: `traceidratio` keeps a trace consistent across all services, which `random` samplers may not. Prefer trace-ID-based sampling.
- Set the sampler once, at the SDK or collector entry, and preserve the decision downstream (`parentbased`). Mixing samplers mid-trace produces incomplete traces that look like bugs.
- For baseline volume, start with a small ratio (single-digit percent) plus tail sampling at the collector to recover errors and slow requests.

## Tail Sampling

- Tail sampling buffers complete (or nearly complete) traces and decides based on outcome: errors, latency, attribute values, rates, or probabilistic fallback.
- Policies compose: keep all errors, keep latency above a threshold, keep a percentage of the rest, and cap volume with a rate limit. Order matters; the first matching keep-policy usually wins by configuration.
- Decision wait: the collector must hold spans for a window (`decision_wait`) that covers the slowest expected trace. Too short produces partial traces; too long costs memory and delays visibility.
- Sticky routing is mandatory at scale: all spans of a trace must reach the same collector instance, or each instance decides on a fragment. Use a load-balancing exporter keyed by trace ID between an agent tier and a tail-sampling gateway tier.
- Memory is proportional to spans per second times wait window. Size the gateway, set `num_traces` limits, and monitor dropped spans.
- Correlate with logs: if logs are sampled independently, kept traces may have no logs. Align log sampling with trace outcomes where incidents demand full narratives.
- Tail sampling belongs in the collector, not in the SDK, unless a single-instance deployment makes in-process buffering safe.

## Cost Control

| Lever | Effect | Where |
|---|---|---|
| Head ratio | Linear volume reduction | SDK or agent collector |
| Tail policies | Keeps interesting traces, drops healthy volume | Gateway collector |
| Drop health checks/probes | Removes pure noise | Agent collector filter |
| Attribute truncation | Reduces bytes per span | Collector or SDK |
| Span limits | Caps attributes/events/links per span | SDK or collector |
| Drop static asset/client spans | Removes low-value spans | Collector |
| Route by service or tenant | Different budgets per tenant | Collector routing |
| Batch tuning | Fewer, larger exports | Exporter config |

- Span limits (max attributes, events, links, attribute value length) are guardrails against a single runaway instrumentation. Set them explicitly; defaults vary by SDK.
- Span name cardinality also costs: a span name with an ID creates a metric-like explosion downstream in span-metrics connectors. Templatize.
- Compute cost per service before and after sampling: spans/sec, bytes/sec, and backend retention. A trace budget per tenant is the sustainable model.
- Never drop all spans of a trace selectively at the tail; keep complete traces, or link the remaining spans so the story is still reconstructable.

## Debugging With Traces

1. Start from a symptom: a latency alert, an SLO burn, or a slow dashboard panel. Get a trace ID from an exemplar if available.
2. Read the critical path: the deepest branch on the slowest path, not the whole tree. Span duration plus self-time (duration minus child durations) finds where time is actually spent.
3. Check for missing spans: an uninstrumented hop or lost context often explains "the service is slow but no span shows it".
4. Read errors in context: status `ERROR`, exception events, and the attributes at the failing boundary. Compare a failing trace to a successful one of the same route.
5. Correlate outward: logs filtered by `trace_id`, profiles filtered by service and time, metrics by service and route.
6. Confirm with a controlled experiment: change one thing, reproduce, compare traces. Traces show causality, not proof; combine with metrics for impact.

| Symptom | Likely trace evidence |
|---|---|
| Tail latency spike | One slow child span, often a DB or external call |
| Errors without logs | Status `ERROR` set but exception not recorded; or 4xx confusion |
| Missing trace | Broken propagation at a hop or a new root span |
| Duplicated work | Repeated sibling spans (retries, fan-out without dedup) |
| Queue delay | Large gap between producer and consumer spans; link the traces |
| Clock anomalies | Child starts before parent; check NTP and host clocks |

## Propagation Code Pattern

```python
# Inbound: extract context from the carrier (framework integrations do this for you).
from opentelemetry import trace, propagate, context
carrier = {"traceparent": request.headers.get("traceparent", "")}
ctx = propagate.extract(carrier)
token = context.attach(ctx)
try:
    with tracer.start_as_current_span("handle request", kind=SpanKind.SERVER):
        response = handle(request)
finally:
    context.detach(token)

# Outbound: inject ambient context into the outgoing carrier.
headers = {}
propagate.inject(headers)
http_client.post(url, headers=headers)
```

- Do not attach and detach context across long-lived tasks; capture the context object at submit time and restore it inside the worker.
- Async hops that are easy to miss: thread pools, `setTimeout`-style callbacks, queue consumers, stream processors, and retry wrappers. Verify each one with a trace assertion.
- Test propagation with a two-service integration test: one root trace ID, correct parent-child across the boundary, and no orphan root spans.

## Tail Sampling Configuration Sketch

```yaml
processors:
  tail_sampling:
    decision_wait: 10s
    num_traces: 100000
    policies:
      - name: errors
        type: status_code
        status_code: { status_codes: [ERROR] }
      - name: slow
        type: latency
        latency: { threshold_ms: 1000 }
      - name: baseline
        type: probabilistic
        probabilistic: { sampling_percentage: 5 }
      - name: rate-cap
        type: rate_limiting
        rate_limiting: { spans_per_second: 5000 }
```

- Order matters and semantics vary across collector versions: verify whether the first matching policy decides the outcome or policies are evaluated as a set, and test with synthetic traffic.
- Keep a probabilistic policy so healthy traffic is still observable; an errors-and-latency-only policy makes baselines invisible.
- Monitor tail-sampling memory and eviction. Evicted traces are silently partial; export the eviction metric and alert on sustained eviction.
- Correlate sampled spans with log sampling so kept traces retain their logs (`./02-logging.md`).

## Anti-Patterns

- Span names containing raw URLs, IDs, or SQL text.
- High-cardinality attributes on every span, including request bodies and headers.
- Installing a new global tracer provider per library; only the application owns the provider.
- Sampling independently at every hop without `parentbased`, creating partial traces.
- Tail sampling across multiple instances without sticky routing.
- Treating traces as a complete audit log; sampling means they are a sample by design.
- Recording exceptions on every span as the error propagates.
- Ignoring orphan/root-span rates as a health metric for instrumentation coverage.

## Checklist

- [ ] One root span per user-visible transaction; span kinds set correctly.
- [ ] W3C Trace Context propagation verified end to end, including queues and cron.
- [ ] Span names low-cardinality; attributes follow semantic conventions and have bounded values.
- [ ] Head sampler deterministic and parent-based; baseline ratio documented.
- [ ] Tail sampling policies cover errors, latency, and a probabilistic remainder, with sticky routing.
- [ ] Span limits configured; health checks and static assets dropped.
- [ ] Trace-to-logs and trace-to-metrics drilldowns verified in the UI.
- [ ] Orphan-span rate and dropped-span counters monitored.
- [ ] Trace budget per service/tenant defined and reviewed with cost data.
