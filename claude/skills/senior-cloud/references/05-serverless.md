# Serverless

> Scope: function platforms, serverless containers, edge runtimes, cold starts, event integration, local development, and platform limits.

## Choosing the execution model

| Model | Unit of deploy | Billing | Best for | Watch out for |
|---|---|---|---|---|
| Functions (FaaS) | One function | Per invocation and duration | Event handlers, glue, spiky APIs | Cold starts, runtime limits, local dev gap |
| Serverless containers | Container image | Per request or per vCPU-second | HTTP APIs, workers, jobs, migrations | Scale-to-zero latency, per-request concurrency rules |
| Edge runtime | Worker/script at PoP | Per request | Latency-sensitive routing, auth, personalization | Restricted APIs, tiny bundle limits |
| Kubernetes | Pod | Per node-hour | Stateful systems, long-running, GPU, custom networking | Operational overhead; see `./01-kubernetes.md` |

Default path: start with serverless containers for HTTP services and FaaS for event handlers. Move to Kubernetes only when a concrete constraint (runtime, networking, state, GPU, cost curve at steady high utilization) forces it. See `./09-cost-platform-engineering.md` for the crossover math.

## Function platforms

| Platform | Packaging | Notable traits | Local tooling |
|---|---|---|---|
| AWS Lambda | zip or OCI image | Mature event integrations, SnapStart for supported runtimes, response streaming, provisioned concurrency | SAM CLI, `sam local`, LocalStack |
| Google Cloud Run functions | zip (source) or image | Gen2 runs on Cloud Run infrastructure; integrates with Eventarc | `functions-framework`, `gcloud functions deploy --local` |
| Azure Functions | zip, container | Durable Functions for orchestrations; Flex Consumption plans | Azure Functions Core Tools |
| Cloudflare Workers | JS/WASM module | V8 isolates, near-zero cold start, D1/R2/KV bindings | `wrangler dev` |

Guidance:

- Keep handlers thin: parse input, call a service module, return. Business logic belongs in code you can test without the platform.
- One function per responsibility but not per endpoint by default; packaging many tiny functions multiplies cold starts and IAM surface.
- Use container-image packaging when you need native libraries or large dependencies. Image size affects cold start and deploy time.
- Version runtimes explicitly; language runtimes reach end of support on a published schedule (verify upstream). Platform deprecations are a recurring maintenance cost.

```python
# handler.py - thin function, logic elsewhere
import os
from service import process_order

def handler(event, context):
    for record in event.get("Records", []):
        process_order(record["body"], table=os.environ["ORDERS_TABLE"])
    return {"batchItemFailures": []}
```

```yaml
# template.yaml (AWS SAM, minimal)
AWSTemplateFormatVersion: "2010-09-09"
Transform: AWS::Serverless-2016-10-31
Resources:
  Consumer:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: python3.13
      Handler: handler.handler
      MemorySize: 512
      Timeout: 30
      Architectures: ["arm64"]
      Environment: { Variables: { ORDERS_TABLE: !Ref OrdersTable } }
      Events:
        Queue: { Type: SQS, Properties: { Queue: !GetAtt OrdersQueue.Arn, BatchSize: 10 } }
```

## Serverless containers

- **Cloud Run**: request-driven, concurrency per instance configurable, scale to zero, jobs for batch. Set `min-instances` > 0 only when cold-start latency is user-visible. Set CPU always-allocated only for background work.
- **Fargate**: run containers without nodes; pair with ALB for HTTP or queue workers; slower scale-out than request-based platforms and billed per second per task.
- **Azure Container Apps**: Kubernetes-based (KEDA-driven), revision-based traffic splitting, scale rules from event sources.
- **Knative**: the portable Kubernetes-native option; use when you need on-prem/portable serverless containers and can operate it.
- Patterns: graceful shutdown (handle SIGTERM, drain), readiness gate before traffic, request timeouts shorter than platform timeouts, and a `/healthz` that does not call dependencies.
- Concurrency: platform concurrency per instance is a tuning lever. High concurrency reduces instance count and cost but risks noisy-neighbor latency inside the instance; set it deliberately and load test.

```yaml
# Cloud Run service (excerpt; apply with gcloud run services replace)
apiVersion: serving.knative.dev/v1
kind: Service
metadata: { name: api, annotations: { run.googleapis.com/ingress: internal-and-cloud-load-balancing } }
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "0"
        autoscaling.knative.dev/maxScale: "50"
        run.googleapis.com/cpu-throttling: "true"
        run.googleapis.com/startup-cpu-boost: "true"
    spec:
      containerConcurrency: 40
      containers:
        - image: us-docker.pkg.dev/PROJECT/api@sha256:REPLACE
          resources: { limits: { cpu: "1", memory: "512Mi" } }
```

## Edge runtimes

- Use for: auth at the edge, A/B routing, header/redirect logic, caching, personalization, and lightweight aggregation. Do not use for heavy compute or code needing filesystem, raw sockets, or long-lived connections.
- Constraints: bundle size limits, restricted APIs, per-request CPU limits, and a KV/object model rather than general storage. Verify current limits upstream; they change.
- Data locality: edge KV/object stores are eventually consistent in some regions. Design for read-mostly or accept staleness.
- Observability is often weaker than regional platforms; make sure you can trace edge -> origin with one ID before adopting.

## Cold starts

Causes: container/runtime initialization, dependency loading, JIT warmup, VPC/network setup, image pull.

Mitigations, roughly in order of effect:

1. Choose a lighter runtime (compiled or dynamically fast-start engines start in tens of milliseconds; managed runtimes reset the clock on major language versions).
2. Minimize package size; lazy-load heavy dependencies; use arm64 where supported.
3. Increase memory: many platforms allocate CPU proportionally, so more memory means faster start.
4. Enable platform features: SnapStart for supported JVM/Python runtimes (restores from a snapshot; note the need to handle post-restore uniqueness), provisioned/min instances for latency-critical paths.
5. Keep VPC attachments lean; prefer newer networking integrations and private endpoints over legacy NAT-heavy designs.
6. Pre-warm deliberately only as a last resort: scheduled pings reduce cold starts but cost money and can mislead autoscaling.

Budget rule: if p99 cold start plus normal latency violates the SLO, either pay for warm capacity or move that path to serverless containers with min instances.

## Events and integration

Patterns:

- **Queue worker**: queue -> function with batch size, partial-batch failure reporting, DLQ after N receives, and concurrency cap to protect downstream.
- **Fan-out**: pub/sub topic -> one queue per consumer -> function per consumer. Never point multiple consumers at one queue expecting broadcast.
- **Stream processing**: shards/partitions -> ordered per key. Increase parallelism with partitions, not batch size, when ordering matters.
- **Event bus routing**: rule-based routing to targets (EventBridge and equivalents) for decoupled domain events with schema registries.
- **Schedule**: cron expressions with timezone awareness; idempotent handlers because retries happen.

Reliability rules:

1. Every event handler is idempotent; at-least-once delivery is the norm, exactly-once is rare and still requires idempotency for side effects.
2. Use the outbox pattern or a transaction log to publish events exactly with the state change; do not write the DB and publish separately without it.
3. Poison messages go to a DLQ with enough context to replay; review DLQs on an alarm, not by manual glance.
4. Backpressure: bound concurrency; a function that consumes faster than the dependency can absorb converts a queue into an outage.
5. Timeouts: handler timeout < upstream client timeout < platform limit, so retries are intentional and bounded.
6. Ordering assumptions must be per-key; global ordering is expensive or unavailable.

## Local development and testing

- Run the same handler locally with the official emulator: SAM CLI, Functions Framework, `wrangler dev`, or the Azure Core Tools. Local invoke validates packaging, env, and IAM gaps early.
- Integration tests use containers: LocalStack for AWS APIs, emulators for queues/objects; testcontainers for local dependencies.
- Contract-test event payloads with schema validation in CI; schema drift is the most common production surprise.
- Keep a staging environment with the real event sources; emulators drift from real behavior (IAM, timeouts, cold starts).
- Deploy pipelines: build once as an image/zip, sign it, and promote the same artifact; see `./08-supply-chain-security.md`.

## Limits and quotas to design around

| Limit class | Examples | Design response |
|---|---|---|
| Execution | Timeout ceilings, memory caps, ephemeral disk | Long work -> jobs or containers; stream large payloads via object storage |
| Payload | Request/response size, event size | Pass references (S3/queue), not blobs |
| Concurrency | Account/region concurrency, per-function reserved | Request quota increases early; cap downstream with queues |
| Connections | DB connection limits per instance count | Use a pooler/proxy, not one connection per concurrent invocation |
| Networking | VPC, static egress, private endpoints | Plan egress before compliance requires it |

Assume every quota will be hit at the worst time; alarm on approaching limits (concurrency, queue depth, throttles) rather than discovering them during an incident.

## Anti-patterns

- One function per HTTP route with business logic duplicated per function.
- Synchronous function chains (function calls function calls function) multiplying latency and failure modes.
- Nondeterministic handlers with side effects and no idempotency key.
- Infinite retries with no DLQ; a poison message loop burning budget.
- `min-instances` left at default for a latency-critical path, then surprise cold-start SLO misses.
- Long-lived DB connections opened per invocation without pooling.
- Storing state on local disk or in memory across invocations.
- Secrets in environment variables committed to the repo; use a secret manager and workload identity.

## Checklist

- [ ] Execution model chosen against constraints, not fashion.
- [ ] Runtime and platform versions pinned and tracked for end of support.
- [ ] Cold-start budget measured at p99 and accepted or mitigated.
- [ ] Handlers idempotent, with DLQ and replay procedure.
- [ ] Concurrency bounded to protect downstream dependencies.
- [ ] Timeouts ordered: handler < upstream client < platform.
- [ ] Connection pooling for databases.
- [ ] Local emulation plus staging tests against real services.
- [ ] Artifacts signed and promoted unchanged (`./08-supply-chain-security.md`).
- [ ] Cost model reviewed against steady-state Kubernetes crossover (`./09-cost-platform-engineering.md`).
