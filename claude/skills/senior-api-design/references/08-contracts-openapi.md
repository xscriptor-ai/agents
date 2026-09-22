# Contracts and OpenAPI

OpenAPI 3.1 authoring, spec style and linting, design-first and code-first workflows, SDK
generation, contract testing, mocks, and spec governance.

## OpenAPI 3.1 Authoring

OpenAPI 3.1 aligns with JSON Schema 2020-12, adds full-document examples, and supports
`webhooks`. Treat the spec as the source of truth and review it like code. (OpenAPI 3.2 exists
in the 3.x line; verify upstream which minor your tooling supports before adopting new keywords
such as additional methods on path items.)

```yaml
openapi: 3.1.0
info:
  title: Orders API
  version: 2.3.0
  description: |
    Order management. All errors use RFC 9457 problem details.
servers:
  - url: https://api.acme.com/v2
components:
  securitySchemes:
    oauth:
      type: oauth2
      flows:
        authorizationCode:
          authorizationUrl: https://auth.acme.com/authorize
          tokenUrl: https://auth.acme.com/token
          scopes:
            orders:read: Read orders
            orders:write: Create and update orders
  schemas:
    Order:
      type: object
      required: [id, status, total]
      properties:
        id: {type: string, examples: [ord_01J8Z]}
        status: {type: string, enum: [pending, paid, cancelled]}
        total: {$ref: "#/components/schemas/Money"}
paths:
  /orders:
    get:
      operationId: listOrders
      summary: List orders
      security: [{oauth: [orders:read]}]
      parameters:
        - $ref: "#/components/parameters/Cursor"
      responses:
        "200":
          description: A page of orders
          content:
            application/json:
              schema: {$ref: "#/components/schemas/OrderList"}
        "429": {$ref: "#/components/responses/RateLimited"}
    post:
      operationId: createOrder
      security: [{oauth: [orders:write]}]
      requestBody:
        required: true
        content:
          application/json:
            schema: {$ref: "#/components/schemas/CreateOrder"}
      responses:
        "201":
          description: Created
          headers:
            Location: {schema: {type: string, format: uri}}
          content:
            application/json:
              schema: {$ref: "#/components/schemas/Order"}
        "422": {$ref: "#/components/responses/Problem"}
```

Authoring rules:

- **`operationId` is unique, stable, camelCase, and verb-led** (`listOrders`, `createOrder`).
  SDK generators depend on it; renaming it is a breaking change for generated clients.
- **Reuse via `components`** for schemas, parameters, responses, and headers. Reference them;
  never copy-paste.
- **Errors are first-class**: declare problem-details responses for 400/401/403/404/409/422/429
  per operation (or in shared components) with the specific `code` enum where practical.
- **Examples over prose**: put request and response examples on operations (3.1 supports
  `examples` at the operation level) so mocks and docs are useful without hand-authoring.
- **Descriptions**: units, ranges, idempotency, authentication, and rate limits; lint for
  missing descriptions on operations and parameters.
- **Use `format` and constraints** (`format: uuid`, `maxLength`, `pattern`) so generated
  clients validate rather than passing strings through.
- **Keep `info.version` meaningful** and sync it with the release; do not leave it at `1.0.0`
  forever.
- **Deprecate in the spec**: `deprecated: true` plus a description with the sunset date
  (see [versioning](./04-versioning-compat.md)).

**Anti-patterns**

- `additionalProperties: true` everywhere, erasing the contract.
- Inline schemas repeated across operations instead of components.
- A spec that documents only 200 responses.
- Descriptions that say "see wiki".

## Style and Linting

- **Split large specs by tag** (`paths/orders.yaml`, `paths/users.yaml`) and compose with
  `$ref`; validate that every `$ref` resolves before merge.
- **One public style guide**, enforced by a linter rather than review comments. Spectral-class
  rulesets typically encode: operation ids present and unique, descriptions present, tags
  sorted, error responses documented, no trailing slashes, casing conventions, and security on
  every operation.
- **Lint severity**: errors block CI, warnings are reviewed. Keep the ruleset versioned in the
  repo so rule changes are visible.
- **Naming**: paths kebab-case nouns, schema names PascalCase, parameters camelCase,
  enum values UPPER_SNAKE or lower_snake (pick one).
- **Tie the linter to the contract test suite**: a rule should exist only if a human agreed it
  matters; avoid unmaintainable rule sprawl.

## Design-First vs Code-First

| Approach | Flow | Strengths | Risks |
|---|---|---|---|
| Design-first | Spec -> review -> codegen server stubs/client -> implement | Contract reviewed before code; parallel work; SDKs early | Drift if handlers are not validated against the spec |
| Code-first | Annotations/decorators -> generated spec | Low friction, single source in code | Spec is an afterthought; reviews happen too late; SDK churn |
| Hybrid | Code-first for internals, design-first for the public edge | Pragmatic | Requires a clear boundary and CI diffing |

Default for public and cross-team APIs: **design-first**. For internal services owned by one
team, code-first is acceptable if the generated spec is checked in, linted, diffed in CI, and
served at `/openapi.json` in all environments.

- **Round-trip discipline**: if code generates the spec, commit the generated artifact and
  review its diff; never publish only at runtime.
- **Serve the spec**: `/openapi.json` (and optionally a docs UI) from the deployed service,
  with the same auth rules as the API.
- **Version the artifact**: attach the spec to releases/tags so breaking-change detection has a
  stable baseline (see [versioning](./04-versioning-compat.md)).

## SDK and Codegen Workflows

- **Generate, do not hand-maintain**, clients from the spec. Choose one generator per language
  and pin its version (openapi-generator, orval, kiota, and framework-native generators; verify
  current support for your OpenAPI version).
- **Stable operation ids and tags** determine generated method and module names; treat them as
  API surface (renames break consumers even if HTTP did not change).
- **Generated clients should**: parse problem details into typed errors, expose cursor
  pagination helpers, handle retries with backoff for idempotent calls, and support
  `Idempotency-Key` injection.
- **Automate publishing** SDKs on spec release, with changelogs and semver tied to the API
  version. Do not let generated clients drift from the spec.
- **Test the generated client** against a mock server in CI (see below); an SDK that does not
  compile or round-trip is worse than none.
- **Server codegen**: generating stubs/routes from the spec prevents drift but can fight the
  framework; either commit to the generated layer or add request/response validation middleware
  at runtime.

**Anti-patterns**

- Hand-writing a client and calling it the official SDK.
- Publishing generated clients without versioning or changelogs.
- Different operation ids across environments, which changes generated class names.

## Contract Testing

Contract tests verify that the implementation still satisfies the published contract, and that
consumers and providers agree.

- **Schema conformance on every response**: validate real responses against the spec in
  integration tests (middleware or test client). This catches undocumented fields, wrong
  types, and missing problem details.
- **Consumer-driven contracts** (Pact-class): consumers publish expectations, providers verify
  them in CI. Best when provider changes could silently break many consumers.
- **Provider-driven contracts**: the published OpenAPI/AsyncAPI artifact is the contract; CI
  validates the server against it. Lighter, sufficient when one team owns both sides.
- **Breaking-change detection**: diff the candidate spec against the released baseline with
  `oasdiff`-class tooling and fail on breaking changes; require an explicit override with a
  linked deprecation plan.
- **Example-driven tests**: use spec examples as fixtures so docs stay true and request
  validation is exercised with realistic payloads.
- **Validate requests**, not only responses: reject undocumented/unknown fields where the
  contract says they are invalid; do not silently accept drift.
- **Run the suite against every supported version** (`/v1`, `/v2`) until its sunset.

Sample CI pipeline order:

1. Lint the spec (style ruleset).
2. Diff against the released baseline (breaking-change gate).
3. Generate server interfaces and clients.
4. Run contract tests (schema conformance, consumer contracts, examples).
5. Publish SDKs and attach the spec to the release.

## Mocking and Sandboxing

- **Spec-based mock servers** (Prism, WireMock, MSW, or framework equivalents) serve examples
  from the spec; they unblock consumers before the implementation exists.
- **Contract mocks in consumer tests** keep integration tests fast and deterministic without
  reaching the real provider.
- **Stateful mocks** (a sandbox environment with real auth and data) are needed for onboarding
  flows that depend on sequencing; provide one when the API is a product.
- **Mock fidelity**: generate mocks from the same spec used by CI and refresh on every spec
  release; a stale mock is a source of false confidence.
- **Never mock in production paths**: test doubles belong in tests; production code paths must
  hit the real service or an explicitly documented fallback.
- **Recorded fixtures/prerecorded responses** help regression tests but must be scrubbed of PII
  and tokens before commit.

## Spec Governance

- **One registry/index per organization** listing APIs, versions, owners, lifecycle state, and
  spec URLs; treat it as the catalog for discovery and deprecation tracking.
- **Ownership**: every spec has a CODEOWNERS entry; schema changes require the owning team's
  review.
- **Style guide as code** (ruleset in the repo) and a review checklist for new operations.
- **Version the spec separately from the service** only if they genuinely diverge; otherwise
  release them together (spec artifact + service deploy) and record both in the changelog.
- **Audit gaps**: a scheduled job checks that every deployed service serves a linted spec and
  that every spec is in the registry.
- **Deprecation tracking**: registry fields for deprecation date and sunset date; alert when
  sunset passes with traffic still recorded (see [versioning](./04-versioning-compat.md)).

## Checklist

- [ ] OpenAPI 3.1 (or the 3.x your tooling supports) is the committed source of truth.
- [ ] Every operation has a unique stable `operationId`, summary, and error responses.
- [ ] Schemas live in `components`; no inline copy-paste.
- [ ] Examples (not just schemas) exist for requests and responses.
- [ ] Linter ruleset is versioned, enforced in CI, and blocking on errors.
- [ ] Generated clients are published, versioned, tested, and derived from operation ids.
- [ ] Contract tests validate responses against the spec and run in CI.
- [ ] Breaking-change diff runs against the released baseline.
- [ ] Mock servers are generated from the spec and refreshed on release.
- [ ] Registry lists owner, version, lifecycle state, and spec URL for every API.
