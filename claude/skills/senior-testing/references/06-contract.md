# Contract Testing

Verifying that services can talk to each other without running a full end-to-end environment: consumer-driven contracts, schema compatibility, provider verification, and versioning.

## The Problem Contracts Solve

Integration between two services breaks when the provider changes the shape or semantics
of an interface in a way the consumer did not expect. Full E2E tests catch this only if
every consumer-provider pair is deployed together, which does not scale. Contract tests
pin the interface from both sides, independently, in each service's own pipeline.

- **Consumer-driven contract (CDC)** — the consumer declares what it needs; the provider
  verifies it still satisfies every consumer's expectations.
- **Schema-based contract** — a shared schema (OpenAPI, protobuf, Avro, JSON Schema)
  is the source of truth and both sides verify against it.

Choose CDC when the interface evolves with consumer needs and teams negotiate changes.
Choose schema-based when the interface is a published protocol with many consumers and a
governance process (Kafka topics, public APIs).

## Contract Layers

| Layer | Artifact | Tool examples | Verifies |
|---|---|---|---|
| Synchronous HTTP | Pact file, OpenAPI diff | Pact, schemathesis, openapi-diff | Requests/responses, status codes |
| Async messaging | Message pact, Avro schema | Pact message, Schema Registry | Payload shape, key, headers |
| RPC | Protobuf descriptor | buf breaking, grpcurl | Field evolution, reserved tags |
| GraphQL | Schema + operations | GraphQL Inspector | Operation validity, nullability |
| Events/database CDC | Schema registry compatibility | Confluent/Redpanda registry | Backward/forward compatibility |

## Consumer-Driven Contracts with Pact

### Workflow

1. **Consumer test** drives the consumer against a mock provider, recording interactions
   (request matchers, response examples) and asserting the consumer handles them.
2. The test **publishes the pact** to a broker (Pact Broker, PactFlow, or an artifact
   store) tagged with the consumer version and branch.
3. **Provider verification** replays each pact against the real provider, with provider
   states setting up data, and publishes verification results.
4. The broker computes the **can-i-deploy** decision: may this version ship together with
   the versions currently in the target environment.

```python
# consumer side (pytest + pact-python)
def test_get_order(pact):
    (
        pact.upon_receiving("a request for order 42")
        .given("order 42 exists")
        .with_request("GET", "/orders/42")
        .will_respond_with(200)
        .with_body({"id": 42, "status": "paid", "total": {"amount": 1999, "currency": "USD"}})
    )
    with pact.serve() as srv:
        client = OrderClient(str(srv.url))
        order = client.get(42)
        assert order.status == "paid"
```

```text
# provider side (JVM example)
./gradlew pactVerify -Ppactbroker.url=... -Ppactbroker.consumers=web,partner-api
```

Key rules:

- Contracts are **consumer expectations**, not provider documentation. Only assert fields
  the consumer actually reads and depends on.
- Use matchers, not exact values, for volatile fields (IDs, timestamps, amounts).
- Use exact values for enums and status codes the consumer branches on.
- One pact per consumer-provider pair (or per interaction group). Do not bundle unrelated
  consumers into one contract.
- Provider states (`given(...)`) are named, documented, and implemented as test fixtures
  on the provider, not ad-hoc scripts.

### What a contract should assert

| Assert | Example | Why |
|---|---|---|
| Path and method | `GET /orders/42` | Routing contract |
| Required headers | Accept, auth scheme, content type | Middleware assumptions |
| Status codes per case | 200, 404, 409 | Branching behavior |
| Body fields used by consumer | id, status, total | Field presence and types |
| Nullability | `coupon` may be null | Prevents null-pointer incidents |
| Error envelope | `{code, message}` shape | Error handling paths |
| Pagination shape | cursor + items array | Loop termination |

Do **not** assert fields the consumer ignores; that makes the provider's internal
evolution needlessly constrained.

## Provider Verification

Provider verification runs the recorded pacts against the real provider:

- Data setup through provider states, ideally reusing integration fixtures
  ([03-integration](./03-integration.md)).
- Run against an in-process or containerized provider with a real or isolated database;
  never against production.
- Publish results to the broker with the provider version and branch/tag.
- A provider that fails verification must not deploy; this is the enforcement point.

Common pitfalls:

- Provider state names drift from implementation and silently stop setting up data.
- Verification runs against a provider configured differently from production
  (feature flags, serialization options), giving false confidence.
- Pacts accumulate stale interactions from deleted consumer code; expire them via broker
  policies.

## Schema Compatibility

When a schema is the contract, enforce evolution rules mechanically.

| Change | Backward compatible | Forward compatible | Full |
|---|---|---|---|
| Add optional field | Yes | Yes | Yes |
| Add required field | No | Yes | No |
| Remove optional field | Yes | No | No |
| Remove required field | No | No | No |
| Widen a type (int -> long/string) | Yes | Yes | Yes |
| Narrow a type (string -> int) | No | No | No |
| Rename a field without aliasing | No | No | No |
| Change enum member meaning | No | No | No |
| Add enum member | Yes (consumers must tolerate) | Yes | Yes |
| Reorder fields in JSON | Yes | Yes | Yes (unless positional) |
| Reorder fields in Avro binary | No | No | No |

Rules:

- Treat compatibility as a **CI check**, not a review convention: protobuf `buf breaking`,
  Avro registry compatibility levels, OpenAPI diff with fail-on-breaking.
- Additive changes still require consumers to tolerate unknown fields; document the
  tolerant-reader rule.
- Deprecate before removing: mark deprecated, expose usage telemetry, announce, then remove
  after the agreed window.
- Version the interface only when compatibility cannot be preserved: URL version (`/v2`),
  media type, topic name, or protobuf package. Versioning is a last resort, not the
  default evolution path.

## Contracts vs E2E

| Aspect | Contract tests | E2E tests |
|---|---|---|
| Scope | Interface semantics | Whole system behavior |
| Runtime | Seconds | Minutes |
| Environment | Per-service, no shared env | Full composed environment |
| Catches | Interface drift, nullability, routing | Cross-system timing, auth config, UI |
| Misses | Data semantics beyond stated cases, flows across 3+ services | Rare interactions not in the journey set |
| Failure locality | Points at the pair | Points at the system |

Use both, but with different jobs: contracts guard interfaces on every PR; a handful of
E2E journeys guard the assembled product ([04-e2e](./04-e2e.md)). Do not use contracts as
a substitute for E2E or vice versa.

## Versioning and Deployment Safety

- Tag consumer/provider versions with both **application version** and **environment/branch**
  so the broker can answer "can version A deploy with version B?" per environment.
- Gate deployments on `can-i-deploy` in the pipeline, and record `record-deployment` after
  success.
- Contracts live beside the code that defines them; breaking a contract is a reviewed
  change with a migration note.
- When multiple versions run concurrently (blue/green, canary), contracts must hold for
  the deployed pair; use the broker's environment matrix rather than assuming one version.
- Keep a compatibility test for the oldest supported consumer (N-2 or the fleet's actual
  floor).

## Anti-Patterns

- Provider-side "contract tests" that assert the provider's own mock expectations.
- Recording every field in the response; the provider becomes frozen.
- Exact-match assertions on timestamps/UUIDs; unstable pacts that fail randomly.
- Contract tests that depend on a shared staging environment.
- Treating a green OpenAPI diff as proof of semantic compatibility; meaning changes are
  invisible to schemas.
- Publishing pacts from only one consumer and assuming full coverage.
- Running provider verification manually, after deploy, or never.
- Using contracts to test business rules that belong in integration tests.

## Contract Testing Checklist

- [ ] Every consumer-provider pair that changes independently has a contract.
- [ ] Consumer tests publish pacts with version and branch tags.
- [ ] Provider verification runs in the provider pipeline against a real instance with
      provider states.
- [ ] `can-i-deploy` gates deployment; `record-deployment` runs after success.
- [ ] Pacts expire; stale interactions are removed.
- [ ] Schema evolution rules are enforced by CI tooling, not convention.
- [ ] Nullability and error envelopes are explicitly contracted.
- [ ] Contracts target interface semantics; E2E covers assembled behavior.
