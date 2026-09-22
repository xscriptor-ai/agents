# Events and Webhooks

Event design, CloudEvents envelope, webhook delivery, signatures and replay protection, retries
and dead letters, AsyncAPI, schema registries, and the transactional outbox pattern.

## Event Design

Events describe facts that happened, not commands ("order.created", not "create.order").

- **Name events `noun.verb_past`** (`order.created`, `payment.refunded`), versioned when the
  payload breaks (`order.created.v2`).
- **Include a unique event id** (ULID/UUIDv7) and an `occurred_at` timestamp. Consumers
  deduplicate on the id; producers must never reuse it.
- **Producer and subject**: include `source` (producer identity) and `subject` (the entity id,
  e.g. `orders/ord_01J`).
- **Payload is self-contained for the consumer's use case**, but avoid leaking internal
  structure. Prefer referencing entities (`order_id`) over embedding entire aggregates.
- **Sequence/ordering metadata**: `sequence` per subject when ordering matters; otherwise
  document that ordering is not guaranteed.
- **Correlation and causation ids** link an event to the request and to the event that caused
  it, which is essential for tracing workflows.
- **No PII beyond need**, and never secrets. If consumers need sensitive data, send a reference
  they can fetch with their own credentials.
- **Event vs command vs state snapshot**: events are immutable facts. A consumer that needs
  current state should read the API; events may arrive out of order.
- **Ownership**: each event type has one producer. Multiple producers of the same type break
  ordering and schema guarantees.

```json
{
  "id": "evt_01J8Z6H2",
  "type": "order.created.v1",
  "source": "orders-service",
  "subject": "orders/ord_01J",
  "occurred_at": "2026-01-02T03:04:05Z",
  "correlation_id": "req_01J8Z",
  "data": {"order_id": "ord_01J", "customer_id": "cus_9", "total": {"amount": 1099, "currency": "USD"}}
}
```

## CloudEvents

CloudEvents 1.0 is the interoperable envelope; use it instead of inventing one. (Check the
CloudEvents project for the current spec minor version and any newer release before pinning.)

Required attributes: `id`, `source`, `specversion`, `type`. Common optional:
`datacontenttype`, `dataschema`, `subject`, `time`, `data`.

| Binding mode | How | Use when |
|---|---|---|
| Structured | Event attributes in the JSON envelope (`application/cloudevents+json`) | HTTP webhooks, brokers with JSON payloads, readability |
| Binary | Attributes as HTTP headers (`ce-id`, `ce-type`, ...), data as the body | Existing HTTP pipelines, no body wrapping, proxies preserve headers |
| Batch | Array of structured events | High-volume delivery, fewer HTTP round trips |

- **`dataschema`** points to the JSON Schema for `data`; serve it at a stable, versioned URI.
- **`time`** equals `occurred_at`; do not overwrite it at dispatch time (add a separate
  delivery timestamp if needed).
- **Extensions** (`traceparent`, `tenant`, `sequence`) are lower-case and must not collide with
  required names.
- **Broker mappings**: Kafka/NATS/SQS transports have CloudEvents protocol bindings; follow
  them so consumers can use generic SDKs.

**Anti-patterns**

- Wrapping CloudEvents inside another `payload` envelope "just in case".
- Using `time` as the delivery time so retries change the event.
- Custom attributes in PascalCase, breaking generic tooling.

## Webhook Delivery

Webhooks are HTTP callbacks from producer to consumer. Assume hostile networks and flaky
consumers.

- **Endpoint registration**: consumers supply an HTTPS URL; verify ownership (challenge
  response or a signed ping) and allow per-endpoint secret rotation and event-type filters.
- **Attempt semantics: at-least-once.** Duplicates are expected; consumers deduplicate on the
  event id.
- **Delivery timeout**: aggressive (for example 5-15 s); a slow consumer should not stall the
  pipeline. Deliver asynchronously with a queue and workers.
- **Retries**: exponential backoff with jitter, capped (for example up to 24-72 h), with
  documented schedule. Honor consumer `429`/`503` + `Retry-After` where present.
- **2xx means accepted.** Document whether 202 is acceptable and whether body content is read.
  Do not require a response body.
- **Dead-letter after retries exhausted**; keep the event retrievable for manual replay and
  notify the consumer (dashboard, email, or API for listing failed deliveries).
- **Ordering**: HTTP delivery is unordered across retries. Include `sequence` and document that
  consumers must handle out-of-order or reorder locally. If ordering is mandatory, use a broker
  with partitioned ordering, not webhooks.
- **Fan-out**: one event to many endpoints, isolated per endpoint; one failing endpoint must
  not delay others.
- **Manual replay** by id/time range with the same signature scheme, plus audit logging.
- **Payload size**: keep webhooks small; link to the resource for large data.
- **Observability**: per-endpoint delivery success rate, latency, and queue depth; alert on
  sustained failures.

**Anti-patterns**

- Synchronous webhook calls inside a request transaction (latency and rollback coupling).
- Treating a non-2xx as "consumer is broken" without retries or visibility.
- Retrying forever with no dead letter; a poison event blocks progress.
- Requiring consumers to fetch a token from the sender API just to receive webhooks.

## Signatures and Replay Protection

Sign every webhook. A shared secret plus HMAC over timestamp and body is the baseline
(Standard Webhooks-style); asymmetric signatures (ed25519) are preferable when many parties
verify.

- **Sign `timestamp + "." + raw_body`** with HMAC-SHA256 using a per-endpoint secret. Include
  the timestamp in a header (`Webhook-Timestamp`) and one or more signatures
  (`Webhook-Signature: v1,<base64url>`), so secrets can rotate without breaking consumers.
- **Verify over the raw body bytes**, before JSON parsing; any reserialization changes the
  signature.
- **Constant-time comparison**; never `==` on digests.
- **Replay window**: reject timestamps outside a small tolerance (for example 5 minutes) and
  optionally cache event ids/`jti` for the window.
- **Key rotation**: support two active secrets (`v1a`, `v1b`) and publish a rotation schedule;
  give consumers overlap to update.
- **Asymmetric option**: publish a JWKS and sign the envelope (JWS) so consumers verify with a
  public key; avoids secret distribution at scale.
- **Never send the secret in the payload or URL**, and never log it.

```python
import hashlib, hmac, base64, time

def sign(secret: bytes, body: bytes, ts: int | None = None) -> str:
    ts = ts or int(time.time())
    msg = str(ts).encode() + b"." + body
    mac = hmac.new(secret, msg, hashlib.sha256).digest()
    return f"t={ts},v1={base64.urlsafe_b64encode(mac).decode().rstrip('=')}"
```

## AsyncAPI and Schema Registries

- **AsyncAPI** (2.x and 3.x; confirm which major your tooling supports) documents channels or
  operations, message schemas, bindings, and security for brokers and webhooks. Use it as the
  contract for event surfaces the same way OpenAPI is used for HTTP.
- **AsyncAPI 3** reorganized around `operations`, `channels`, and `messages`; treat a migration
  from 2.x as a tooling project, not a mechanical rewrite.
- **Generate types and docs** from AsyncAPI; validate published messages against schemas in CI.
- **Schema registry** (Confluent-compatible, Apicurio, or cloud-native) is the source of truth
  for message schemas on Kafka-class transports. Subject naming:
  `topic-value`, or `domain.event.type-value`; document it.
- **Compatibility mode per subject**: `BACKWARD` (default for consumers-first), `FORWARD`,
  `FULL`, or `NONE` (discouraged). Adding optional fields is backward-compatible; removing or
  retyping is not (see [versioning](./04-versioning-compat.md)).
- **Serialization**: Avro or Protobuf with a registry is compact and enforces schemas; JSON
  Schema with `dataschema` in CloudEvents is more interoperable but larger and looser. Pick per
  transport and document.
- **Envelope vs payload schema**: version the event type in the envelope; schemas evolve under
  registry compatibility rules.

## Transactional Outbox

Never publish an event directly from a request handler between the database commit and the
broker call; a crash or broker outage loses or duplicates events. Use an outbox.

1. In the same transaction as the state change, insert the event into an `outbox` table
   (id, type, payload, headers, created_at, published_at null).
2. A relay (poller or CDC) reads unpublished rows and publishes them, marking them published
   atomically (or via CDC without a mark).
3. Consumers deduplicate on the event id; the outbox gives at-least-once.
4. Prune published rows after a retention window.

| Relay | Mechanism | Notes |
|---|---|---|
| Polling publisher | `SELECT ... FOR UPDATE SKIP LOCKED` + publish + mark | Simple, no new infra; adds small latency |
| CDC (Debezium-class) | Tail the WAL/binlog of the outbox table | Lowest latency, no polling; requires CDC infrastructure and schema discipline |
| Transaction log tailing | Database logical replication to a relay | Similar to CDC; couples to DB features |

- **Ordering**: publish per aggregate key (partition by `subject`) and include `sequence`;
  global ordering is not achievable at scale.
- **Inbox pattern** on the consumer side stores processed event ids to make consumption
  idempotent.
- **Exactly-once is a trade-off, not a guarantee.** Even with Kafka transactions, external side
  effects (email, payment) need idempotency keys; design consumers to be idempotent by
  construction.
- **Schema changes** to the outbox payload follow the registry compatibility mode.
- **Failure visibility**: alert on relay lag, outbox depth, and publish errors; a stuck relay
  silently freezes the event stream.

**Anti-patterns**

- Publishing after commit without a fallback (dual-write problem).
- Marking published before the broker acknowledges.
- Treating the outbox as a permanent event archive; prune or move to a store.
- Consumers that assume exactly-once and mutate state non-idempotently.

## Checklist

- [ ] Events are past-tense facts with unique ids, `source`, `subject`, and `occurred_at`.
- [ ] CloudEvents 1.0 envelope with structured or binary binding; `dataschema` published.
- [ ] Webhook endpoints verified, filterable, and independently retried.
- [ ] Every webhook is signed over the raw body with a timestamp and rotation plan.
- [ ] Consumers deduplicate; replay window enforced; constant-time comparison.
- [ ] Retry schedule, timeouts, dead-letter, and manual replay are documented and observable.
- [ ] Delivery is at-least-once, ordering is either not promised or explicitly sequenced.
- [ ] AsyncAPI (or registry) documents channels, messages, and compatibility mode.
- [ ] Producers use a transactional outbox with lag alerting; consumers use an inbox/idempotency.
- [ ] Event schema changes go through compatibility checks and the sunset rules for versions.
