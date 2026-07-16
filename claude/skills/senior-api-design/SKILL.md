---
name: senior-api-design
description: API design patterns — RESTful conventions, GraphQL schema design, gRPC
  service definitions, versioning strategies, pagination, error handling, API security
---

# API Design

## RESTful Conventions

### URL Structure

- Nouns for resources: `/users`, `/orders`, `/products`
- HTTP verbs for actions: GET, POST, PUT, PATCH, DELETE
- Nested for sub-resources: `/users/{id}/orders/{orderId}`
- Plural nouns consistently
- No verbs in URLs (`/getUsers`, `/createOrder`)

### HTTP Methods & Status Codes

| Method | Action | Success | Error |
|--------|--------|---------|-------|
| GET | Read | 200 OK | 404 Not Found |
| POST | Create | 201 Created | 409 Conflict |
| PUT | Full replace | 200 OK | 404 / 409 |
| PATCH | Partial update | 200 OK | 422 Unprocessable |
| DELETE | Remove | 204 No Content | 404 / 409 |

## GraphQL Schema Design

- Schema-first development — define schema before resolvers.
- Use Connection pattern for pagination (Relay spec).
- Limit query depth and complexity.
- Batch resolve with DataLoader (N+1 prevention).
- Deprecate fields with `@deprecated`, do not remove.

## gRPC Service Definitions

```protobuf
service OrderService {
  rpc CreateOrder(CreateOrderRequest) returns (Order);
  rpc GetOrder(GetOrderRequest) returns (Order);
  rpc ListOrders(ListOrdersRequest) returns (stream Order);
}
```

- Use `google.protobuf.Timestamp` and `google.type.Money`.
- Unary for CRUD, server-streaming for lists, client-streaming for uploads, bidirectional for real-time.
- Version via package name: `package orders.v2;`.

## Versioning Strategies

| Strategy | Mechanism | Example | Trade-off |
|----------|-----------|---------|-----------|
| URL path | `/v1/users` | `/v2/users` | Simple, breaks URLs on upgrade |
| Header | `Accept: application/vnd.api+json;version=2` | Custom media type | Requires header support |
| Query param | `?api_version=2` | `/users?version=2` | Caches differently |
| No versioning | Backward-compatible evolution | Add fields only, never remove | Hard at scale, works for internal |

Prefer backward-compatible evolution. When breaking changes are unavoidable, use URL path versioning.

## Pagination

| Pattern | Mechanism | Strengths | Weaknesses |
|---------|-----------|-----------|------------|
| Offset | `?offset=0&limit=20` | Simple, skip to page N | Inconsistent if data changes |
| Cursor | `?cursor=abc123` | Consistent, performant | No random page access |
| Keyset | `?after_id=123&limit=20` | Fast on indexed columns | Complex filtering |
| Page | `?page=1&per_page=20` | Simple UI integration | Same as offset |

### Recommendation

- User-facing: page-based for simple navigation.
- Real-time / ordered data: cursor-based for consistency.
- API-to-API: cursor-based.

### Response Format

```json
{
  "data": [...],
  "pagination": {
    "cursor": "eyJpZCI6MTB9",
    "has_more": true,
    "next_cursor": "eyJpZCI6MjB9"
  }
}
```

## Error Handling

### Consistent Error Response

```json
{
  "error": {
    "code": "INVALID_INPUT",
    "message": "Email address is not valid",
    "details": [
      {
        "field": "email",
        "code": "FORMAT",
        "message": "Must be a valid email address"
      }
    ],
    "request_id": "req_abc123"
  }
}
```

- Use standard error codes, not HTTP status alone.
- Include `request_id` in every error for traceability.
- Never leak stack traces or internal details.

## API Security

| Concern | Pattern |
|---------|---------|
| Authentication | OAuth 2.0 / OIDC, API keys for machine-to-machine |
| Authorization | Scopes (RBAC), claims (ABAC) |
| Rate Limiting | Token bucket per API key, per IP |
| Validation | Schema validation on input (OpenAPI/Pydantic/Zod) |
| Throttling | 429 Too Many Requests with Retry-After header |
| CORS | Whitelist origins, methods, headers |
| TLS | Enforce HTTPS, HSTS header, disable weak ciphers |

## OpenAPI / Swagger

- Write OpenAPI 3.1 spec as source of truth.
- Use code-first (`@nestjs/swagger`, `fastapi`) or design-first (Stoplight, Spectral).
- Validate spec with spectral lint rules.
- Generate client SDKs via openapi-generator or orval.
