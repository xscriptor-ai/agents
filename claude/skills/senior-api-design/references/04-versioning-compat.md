# Versioning and Compatibility

Versioning strategies, additive change rules per surface, deprecation and Sunset headers, the
sunset process, breaking-change detection, and compatibility testing.

## Strategy Selection

Default to additive evolution with no version number. Version only when a breaking change is
unavoidable and consumers cannot be updated in time.

| Strategy | Identifier | Use when | Costs |
|---|---|---|---|
| Additive, unversioned | none | Default: private APIs, most public APIs with disciplined reviews | Accidental breaks are possible; needs diffing in CI |
| URL path | `/v2/orders` | Public breaking change; discoverability and routing simplicity | Duplicate docs and routes; long dual-serving period |
| Media type | `Accept: application/vnd.acme.v2+json` | Content negotiation already used; few clients | Invisible in access logs; harder to debug |
| Custom header | `API-Version: 2026-01-01` | Many small breaking changes; date-based pinning (Stripe-style) | Clients must pin; default-version shifts are breaking by definition |
| Query parameter | `?api_version=2` | Quick fixes, rarely a good long-term contract | Caching/CDN keys; easy to forget in clients |
| Protobuf package | `acme.orders.v2` | gRPC breaking change | New wire service; old still hosted |
| Event schema version | `type: acme.order.created.v2` | Async payload breaking change | Consumers subscribe to both during migration |

Rules that keep this honest:

- **One version axis per API.** Do not also version individual endpoints with a second scheme.
- **Never remove a version without a sunset date and telemetry.** Publishing `v2` is half the
  work; migrating `v1` clients is the other half.
- **A version is a contract, not a copy of the codebase.** Keep shared domain logic; version the
  boundary (serialization, validation, route mapping).
- **Date-based versions**: the default version must change only with a new version label; never
  change the meaning of an existing pinned version.

## Additive Change Rules

A change is non-breaking if every valid existing client request keeps working with the same
meaning and every existing response remains parseable.

| Change | REST | GraphQL | gRPC | Events |
|---|---|---|---|---|
| Add response field | Safe | Safe | Safe | Safe if optional |
| Add request field (optional) | Safe | Safe | Safe | Safe |
| Add required request field | Breaking | Breaking (non-null arg) | Breaking | Breaking |
| Add enum value | Safe if clients tolerate unknown | Safe if clients handle unknown | Safe (document) | Depends on consumer validation |
| Remove field | Breaking | Breaking (unless deprecated long) | Breaking | Breaking |
| Rename field | Breaking | Breaking | Breaking (reserve) | Breaking |
| Change type/format | Breaking | Breaking | Breaking | Breaking |
| Tighten validation (new max length, stricter enum, new required) | Breaking | Breaking | Breaking | Breaking |
| Loosen validation | Safe (usually) | Safe | Safe | Safe |
| Change ordering/defaults | Breaking if clients rely on it | Breaking | Breaking | Depends |
| Add new endpoint/method/operation | Safe | Safe | Safe | n/a |
| Change error codes/status | Breaking if clients branch on them | Breaking | Breaking | n/a |
| Change auth requirements | Breaking | Breaking | Breaking | n/a |
| Change rate limits downward | Breaking operationally | Same | Same | Same |

Practical guidance:

- **Unknown enum/union values** must be tolerated by clients. Document it in your client
  guidance; validate it in generated SDKs where possible.
- **Tightening validation is the most-missed break**: adding `maxLength`, making an optional
  field required, or rejecting values previously accepted breaks real clients. Treat as
  breaking.
- **Defaults are part of the contract**: if an omitted field changes behavior, that is a break.
- **Deprecate before deleting** with at least one full client release cycle plus the sunset
  period (see below).
- **Error taxonomy changes** are breaking when consumers switch on stable `code` values. Keep
  codes stable; add new ones for new cases (see [errors](./06-errors.md)).

## Deprecation Headers

Signal deprecation at the HTTP layer so monitoring and tooling can detect it automatically.

| Header | Meaning | Example |
|---|---|---|
| `Deprecation` | When the endpoint/resource became deprecated (RFC 9745; verify current status) | `Deprecation: @1772323200` (IMF-fixdate or structured date) |
| `Sunset` | When it will stop working (RFC 8594) | `Sunset: Wed, 31 Dec 2026 23:59:59 GMT` |
| `Link` | Documentation and successor | `Link: <https://docs.acme.com/migrate-v2>; rel="deprecation"; type="text/html"` |
| `Warning` | Legacy; do not use for new deprecations | Superseded by `Deprecation`/`Sunset` |
| Custom `X-API-Deprecated` | Avoid | Non-standard and easy to miss |

```
Deprecation: @1772323200
Sunset: Wed, 31 Dec 2026 23:59:59 GMT
Link: <https://api.acme.com/v2/orders>; rel="successor-version",
      <https://docs.acme.com/migrate-v2>; rel="deprecation"
```

- **Emit on every call**, not just once; caches and SDKs must see it.
- **Also document deprecation in the spec**: OpenAPI `deprecated: true` on operations and
  schemas, plus descriptions with the sunset date; GraphQL `@deprecated`; proto
  `deprecated = true` options.
- **GraphQL `@deprecated` reasons** should name the replacement and the removal date.
- **Changelogs and docs**: a dated changelog entry, migration guide, and a machine-readable
  feed if partners automate. Keep the deprecation list in the API docs index.

## Sunset Process

A repeatable process beats an ad-hoc announcement. Typical public-API timeline is 6-12 months;
internal APIs can be weeks if all consumers are known and instrumented.

1. **Decide and publish.** Identify the break, choose the replacement, and post the sunset
   date (RFC 8594) with a migration guide. Announce in the changelog and to known consumers.
2. **Instrument usage.** Emit per-consumer metrics keyed by API key/client id/token
   (`client_id`), endpoint, and version. You cannot manage migration without usage data.
3. **Communicate on a schedule.** 90/30/7-day reminders; include per-tenant usage summaries so
   consumers know their exposure.
4. **Degrade progressively.** Warnings first (headers and non-fatal logs), then brownouts
   (short windows returning 410) to surface clients that ignore messages, then final shutdown.
5. **Return 410 Gone**, not 404, for retired endpoints, with a problem-details body linking the
   replacement and migration guide.
6. **Kill-switch plan.** Keep the ability to extend the date; migrations slip.
7. **Remove code and docs** only after the shutdown date plus a safety window.

| Timeline | Action |
|---|---|
| T-0 (deprecation) | Headers, spec flags, changelog, migration guide, usage metric |
| T+30% of window | First reminder with per-consumer usage |
| T+75% | Brownout schedule published and tested (staging first) |
| T-30 days | Final reminder; escalate to account owners |
| T-0 (sunset) | Brownouts, then 410 responses |
| T+30 days | Remove code paths; archive docs |

**Anti-patterns**

- Announcing a sunset with no replacement documented.
- Deprecating without usage telemetry, so nobody knows who is affected.
- Brownouts without warning or a published schedule.
- Quietly changing the default version (a breaking change in disguise).

## Compatibility Testing in CI

Automate the detection of breaks; human review misses them.

| Surface | Tooling category | Gate |
|---|---|---|
| OpenAPI | `oasdiff`, `openapi-diff`, Optic-class tools | Fail on breaking diff vs the released spec (see [contracts](./08-contracts-openapi.md)) |
| GraphQL | GraphQL Inspector, schema diff in the registry, composition checks | Fail on breaking changes and composition errors |
| Protobuf | `buf breaking` against a pinned baseline | Fail on wire-incompatible changes |
| Events | Schema registry compatibility mode (backward/forward/full), AsyncAPI diff | Fail on incompatible subject registration |
| Runtime | Consumer-driven contract tests (Pact-class) plus provider verification | Fail when a published contract no longer verifies |
| Responses | Golden/snapshot tests of representative payloads per version | Catch serialization drift |

- **Pin the baseline**: compare against the last released artifact, not `main`. Store the
  released spec/schema next to the release tag or in a registry.
- **Run diffing on every PR** and require an explicit approval label for intentional breaks
  (with a linked sunset plan).
- **Test old clients against new servers**: keep a compatibility suite with previous SDK
  versions, or at minimum representative recorded requests, and run it against staging.
- **Contract tests are two-sided**: providers must run consumer contract verification in CI,
  and consumers must pull the published contract. Contract tests complement, not replace,
  integration tests.
- **Version-aware integration tests**: for URL-versioned APIs, run the same suite against every
  supported major version until its sunset.

## Review Checklist

- [ ] Versioning strategy is documented and applied consistently; one axis per API.
- [ ] Additive-change rules are codified; tightening validation is treated as breaking.
- [ ] Deprecation and Sunset headers (plus `Link`) are emitted on deprecated endpoints.
- [ ] Specs mark deprecations (`deprecated: true`, `@deprecated`, proto options).
- [ ] A sunset process exists with telemetry, reminders, brownouts, and 410 responses.
- [ ] CI detects breaking changes for every surface (OpenAPI, GraphQL, proto, events).
- [ ] Baseline artifacts are pinned to the last release.
- [ ] Consumer-driven contract tests run on both sides.
- [ ] Changelog and migration guides are part of the release definition of done.
