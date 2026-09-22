# OpenTelemetry

Scope: OTel architecture, the API/SDK split, semantic conventions, collector deployment patterns, auto-instrumentation per language, and migration off vendor agents.

## Architecture in One Picture

```text
app process                          collector (agent and/or gateway)        backend
+----------------------+            +-----------------------------+         +---------+
| OTel API (no-op safe)|            | receivers  (otlp, prometheus|         | traces  |
| OTel SDK             |--OTLP----->|   filelog, hostmetrics,     |--OTLP-->| metrics |
|  resource, sampler,  |            |   k8s_cluster, jaeger, ...) |         | logs    |
|  processors, exporter|            | processors (batch, memory,  |         | profiles|
+----------------------+            |   filter, transform, tail)  |         +---------+
                                    | connectors (spanmetrics,    |
                                    |   servicegraph, routing)    |
                                    | exporters (otlp, kafka, ...)|
                                    +-----------------------------+
```

- Signals: traces, metrics, logs, and profiles; baggage travels with traces. Traces, metrics, logs, and baggage are stable; the profiles signal is stabilizing — verify upstream for your SDK and backend.
- Components: the API you call, the SDK that implements it, OTLP as the wire protocol, the Collector for pipeline policy, semantic conventions for naming, and the Operator for Kubernetes packaging.
- The protocol is the contract. Instrument against OTel and OTLP so backends remain replaceable.

## API vs SDK Split

| Layer | Responsibility | Who configures it |
|---|---|---|
| API | Instrumentation calls: tracers, meters, loggers, propagators | Library authors; app code at boundaries |
| SDK | Sampling, processing, export, resource, limits | Application entrypoint or bootstrap |
| Exporter | Wire format and destination (OTLP, Prometheus, vendor) | Application or collector |
| Propagator | Trace context and baggage over the wire | Application or framework integration |
| Resource | Identity of the emitting entity | Application or auto-instrumentation |

- Libraries SHOULD depend only on the API (or the SDK-free facade), never install global providers or exporters. If no SDK is configured, the API must behave as a no-op with negligible cost.
- Applications own provider setup exactly once at startup, before serving traffic.
- Pin the semantic-convention version you emit; conventions rename attributes across minor releases. Use the SDK's stability opt-in (for example `OTEL_SEMCONV_STABILITY_OPT_IN`) during migrations and check the upstream compatibility notes.
- Environment variables are the portable configuration surface: `OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_PROTOCOL`, `OTEL_TRACES_SAMPLER`, `OTEL_SDK_DISABLED`. Prefer them over bespoke config so collector-side and SDK-side behavior stay aligned.

## OTLP Specifics

- OTLP/gRPC on port 4317 and OTLP/HTTP on 4318; HTTP supports protobuf and JSON. gRPC is the usual inside-cluster choice; HTTP/protobuf travels through HTTP-only proxies.
- Signal paths: `/v1/traces`, `/v1/metrics`, `/v1/logs`, and `/v1/profiles` where supported. Read endpoints from env vars, not from code defaults.
- Compression is per-exporter (`gzip` is common); enable it before increasing batch size to fix throughput.
- Partial success is a first-class response: the SDK must surface rejected spans/metrics rather than silently dropping them.
- Queueing and retry: exporters ship with bounded queues and backoff. Configure queue size and timeouts deliberately; a full queue drops data, and an unbounded queue eats memory.
- On shutdown, flush the SDK and shut down providers with a deadline. Container termination that skips this loses the last batch.

## Resource and Identity

| Attribute | Purpose | Notes |
|---|---|---|
| `service.name` | Primary service identity | Stable, match dashboards/alerts; set explicitly |
| `service.namespace` | Grouping for large orgs | Optional but useful for multi-tenant platforms |
| `service.version` | Deploy correlation | Commit SHA, semver, or build ID |
| `service.instance.id` | Unique instance | Pod UID or hostname; never reused across restarts |
| `deployment.environment.name` | Environment | Prefer this over the older `deployment.environment`; verify SDK support |
| `cloud.provider`, `cloud.region`, `cloud.availability_zone` | Cloud topology | Resource detection or collector enrichment |
| `k8s.cluster.name`, `k8s.namespace.name`, `k8s.pod.name`, `k8s.deployment.name` | Kubernetes topology | Added by the Operator, k8sattributes, or SDK resource detectors |
| `host.name`, `host.arch`, `os.type` | Host identity | Useful in bare-metal and VM fleets |
| `telemetry.sdk.language`, `telemetry.sdk.name`, `telemetry.sdk.version` | SDK provenance | Automatic; use for SDK-version inventories |

- Identity drift is the most common observability defect: traces, metrics, and logs from one process must carry the same `service.*` values. Assert it in review and in tests.
- Keep high-cardinality identity in resource attributes (one time series per process is still too many for some backends) and off metric labels. Put instance identity on spans/logs, not on counters.

## Semantic Conventions

| Domain | Representative attributes | Notes |
|---|---|---|
| HTTP server | `http.request.method`, `http.route`, `url.path`, `http.response.status_code` | `http.route` is the templated route, never the raw path |
| HTTP client | Same server attributes plus `server.address`, `server.port` | Old `net.peer.*` names are deprecated; migrate |
| RPC | `rpc.system`, `rpc.service`, `rpc.method`, `rpc.grpc.status_code` | gRPC status is not HTTP status |
| Database | `db.system`, `db.namespace`, `db.operation.name`, `db.query.summary` | Never record full statements with literals; use parameterized summaries |
| Messaging | `messaging.system`, `messaging.destination.name`, `messaging.operation.type`, `messaging.message.id` | Kafka/RabbitMQ/SQS/NATS conventions differ in detail |
| Kubernetes | `k8s.*` | Prefer collector or Operator enrichment over hand-set values |
| GenAI | `gen_ai.system`, `gen_ai.request.model`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`, `gen_ai.operation.name` | Rapidly evolving; pin the semconv version and verify upstream |
| Errors | `exception.type`, `exception.message`, `exception.stacktrace`, span status `ERROR` | Log the exception once, not at every layer |
| Identity | `enduser.id`, `user.id` | Treat as PII; high cardinality; never metric labels |

- Convention migrations are mechanical but wide-reaching: `net.peer.name` to `server.address`, `http.method` to `http.request.method`, `http.status_code` to `http.response.status_code`, `db.statement` usage tightened. Run a grep for deprecated names during upgrades.
- Stable conventions are the contract; stabilizing and development conventions may change without a major version. Check the stability badge before relying on an attribute in SLO queries.

## Collector Deployment Patterns

| Pattern | Shape | Use when | Watch out for |
|---|---|---|---|
| Gateway | Deployment, one or few replicas | Central policy, simple clusters | Single point of failure; scale and PDB required |
| Agent | DaemonSet per node | Host/k8s enrichment, local buffering | Config drift; per-node resource overhead |
| Agent plus gateway | DaemonSet forwards to Deployment | Production default at scale | Two configs to maintain; test both |
| Sidecar | Per-pod container | Hard isolation, per-tenant limits | Cost, pod churn, restart gaps |
| Direct export | App to backend/collector-less | Serverless, tiny fleets | No central filtering or redaction |

- Collector config has four sections: `receivers`, `processors`, `exporters`, and `service.pipelines`, plus `extensions` and `connectors`. Pipelines are per signal and explicitly listed.
- Standard order inside a pipeline: memory limiter first, then enrichment (resource, k8sattributes, attributes), then filtering/transform, then sampling, then batching, then export.
- The load-balancing exporter plus tail sampling requires sticky trace routing: hash by trace ID so all spans of a trace reach the same sampling instance. Scale tail-sampling collectors horizontally only with this pattern.
- Connectors turn a pipeline into an input: `spanmetrics` derives metrics from spans, `servicegraph` derives dependency graphs, `routing` fans out by attribute, `forward` links two pipelines.
- The Kubernetes Operator manages collectors, injects SDK env vars via annotations, and runs the target allocator for Prometheus-style scraping. It is the recommended packaging when you already run Operators.
- Self-telemetry matters: expose collector internal metrics (accepted/refused/sent, queue length, batch size) and alert on refused data and dropped queues. A blind collector loses data silently.
- Backpressure is normal during backend incidents: memory limiter refuses, queues fill, retries back off. Decide per pipeline whether to drop logs first and traces last.

## Zero-Code and Auto-Instrumentation

| Language | Mechanism | Maturity notes |
|---|---|---|
| Java | `-javaagent` with the OTel Java agent; JVM and framework instrumentations | Most mature; supports many frameworks and manual API alongside |
| Python | `opentelemetry-distro` plus `opentelemetry-instrument` wrapper | Broad coverage; watch WSGI/ASGI and celery/queue coverage |
| Node.js | `--require` preload of auto-instrumentations (or ESM loader hook) | Requires preload; ESM support improved but verify your runtime |
| .NET | Auto-instrumentation startup hook or NuGet-based | Good ASP.NET Core, HttpClient, gRPC coverage |
| Go | Compile-time instrumentation is the primary path; eBPF-based zero-code agents exist | Pure-Go needs import-time hooks; eBPF gives no-code coverage with gaps |
| Ruby, PHP | Framework gems/extension plus auto-instrumentation | Coverage varies by framework version; verify upstream |
| eBPF platforms | Kernel-level probes for HTTP/gRPC/DB and profiles | No code changes, useful for legacy/LTO binaries; check TLS and runtime support |

- Rule of thumb: use zero-code to get coverage fast, then add manual spans for business-critical paths. Zero-code spans often miss domain semantics (order ID, tenant), which are exactly what you need during incidents.
- Auto-instrumentation still needs the resource attributes and sampler configured; injecting the agent without `OTEL_SERVICE_NAME` and an endpoint produces unnamed or lost telemetry.
- Redaction and cardinality control do not come for free with zero-code. Inspect what the agent emits (DB statements, URLs, headers) before production.
- eBPF agents are kernel- and runtime-version dependent; pin the agent and test after kernel upgrades. Verify upstream support for your Go/Node TLS stack.

## Migration From Vendor Agents

1. Inventory every producer: agents, SDKs, log shippers, dashboards, alerts, runbooks, and saved queries. The dashboards and alerts are usually the hard part.
2. Land OTel telemetry in parallel (dual-ship). Keep the vendor agent running until parity is measured per signal, not per service.
3. Map vendor-specific concepts to OTel: host tags to resource attributes, APM service names to `service.name`, custom metrics to OTel instruments, trace tags to span attributes.
4. Normalize through the collector, not in application code, so migrations do not require redeploys.
5. Rebuild alerts and dashboards on the new backend, then decommission agents signal by signal; remove credentials and old pipelines in a final pass.
6. Expect semantic gaps: vendor agents often capture process metrics, profiles, and database query plans that OTel only approximates. Document what is lost.

## SDK Bootstrap Skeleton

```python
# Application entrypoint: the only place providers, exporters, and resources are configured.
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

resource = Resource.create({
    "service.name": "order-api",
    "service.version": "2f9c1ab",
    "deployment.environment.name": "prod",
})
provider = TracerProvider(resource=resource)
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
trace.set_tracer_provider(provider)
# On shutdown: provider.shutdown() to flush with a deadline.
```

- The shape is the same in every language: build a resource, install one provider, attach a batch processor and OTLP exporter, register propagators. Keep it in a bootstrap module that tests can replace.
- Configure via environment variables (`OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_TRACES_SAMPLER`, `OTEL_RESOURCE_ATTRIBUTES`) so the same image works across environments.
- For Kubernetes, the Operator can inject these settings from pod annotations, which keeps app code free of endpoints and credentials.

## Versioning and Compatibility

- Semantic conventions, SDKs, and the collector version independently. Record all three in an inventory; upgrades in one component can change emitted data for the others.
- Collector upgrades: processors and receivers can move between core and contrib, change default behavior, or be deprecated. Pin image digests, read release notes, and stage upgrades.
- SDK upgrades: attribute renames follow semconv stability levels. Use the stability opt-in during migration and keep a deprecation grep in CI.
- Instrumentation package versions must match supported framework versions; a framework major upgrade without an instrumentation bump is a common source of missing spans.
- Exporters should tolerate a backend version skew; OTLP is the compatibility boundary. Keep a dual-export path during backend migrations.

## Anti-Patterns

- Configuring exporters inside libraries or multiple conflicting global providers in one process.
- Setting `service.name` differently per signal, or leaving it as `unknown_service`.
- Raw URL paths, user IDs, or error messages as metric labels or span names.
- Running a tail-sampling collector fleet without sticky routing, so traces are sampled per span and lose completeness.
- Sending everything to the backend and filtering "later"; later never comes and the bill does.
- Treating collector refusal metrics as noise instead of data loss.
- Assuming the profiles signal and GenAI conventions are frozen; they are not.

## Checklist

- [ ] One global SDK configured at startup; libraries use the API only.
- [ ] `service.name`, `service.version`, and deployment environment consistent across signals.
- [ ] Semantic-convention version pinned; deprecated attribute names migrated.
- [ ] Collector topology matches scale: gateway or agent-plus-gateway, with memory limiter and batching.
- [ ] Tail sampling sessions are trace-sticky and horizontally testable.
- [ ] Zero-code agents configured with resource and sampler, and audited for emitted cardinality and PII.
- [ ] Collector self-telemetry exported and alerted on.
- [ ] Migration dual-ships until parity is proven, then decommissions in stages.
