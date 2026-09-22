# Web Frameworks

FastAPI, Litestar, Starlette, and Django 5.x: lifespan, dependency injection, WebSockets, testing, middleware order, error handling, and rate limiting.

## ASGI vs WSGI

| Aspect | WSGI | ASGI |
|---|---|---|
| Concurrency | One blocking request per worker thread | Coroutines, WebSockets, streaming |
| Servers | gunicorn, uwsgi, waitress | uvicorn, granian, hypercorn, daphne |
| Middleware | WSGI callables | Async callables (implement both for portability) |
| Django | Classic `wsgi.py` | `asgi.py`, async views and ORM |
| Use when | Legacy stack, mature sync deps | New services, streaming, websockets |

Mixing: ASGI apps can call sync endpoints (framework offloads to a threadpool), but WSGI
cannot host async views. Migrate endpoint by endpoint and keep one server pipeline.

## FastAPI

### Lifespan and app state

```python
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    engine = create_async_engine("postgresql+asyncpg://...", pool_size=10)
    app.state.engine = engine
    app.state.sessionmaker = async_sessionmaker(engine, expire_on_commit=False)
    yield
    await engine.dispose()

app = FastAPI(lifespan=lifespan)
```

- `@app.on_event("startup")` is deprecated; use `lifespan`.
- Lifespan runs once per worker process, not once per cluster; do not run cron/leader work
  there unless you coordinate (or use a dedicated job runner).
- Store pools, clients, and caches on `app.state`, never module globals, so tests and
  multiple app instances stay isolated.

### Dependency injection

```python
from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

async def get_session(request: Request) -> AsyncIterator[AsyncSession]:
    async with request.app.state.sessionmaker() as session:
        yield session

SessionDep = Annotated[AsyncSession, Depends(get_session)]

@app.get("/users/{uid}")
async def get_user(uid: int, session: SessionDep) -> dict[str, int]:
    return {"id": uid}
```

- Dependencies are cached per request by default; `Depends(fn, use_cache=False)` forces
  re-execution. Do not abuse this for expensive work.
- `yield` dependencies run teardown after the response; exceptions raised before `yield`
  are handled by the framework, exceptions after `yield` are not.
- Prefer `Annotated[..., Depends(...)]` aliases over defaults — they compose and are
  reusable across signatures.
- Keep dependency chains shallow; deeply nested DI is hard to test and hides I/O.
- Use `app.dependency_overrides` for tests instead of patching internals.

### Sync vs async endpoints

- `async def` runs on the loop: only call async I/O here.
- plain `def` runs in Starlette's threadpool: safe for blocking libraries, limited by the
  pool size (default tied to the anyio thread limiter).
- Never mix: an `async def` calling a blocking ORM stalls every request in the worker.

### Background tasks and queues

```python
from fastapi import BackgroundTasks

@app.post("/send")
async def send(background: BackgroundTasks) -> dict[str, bool]:
    background.add_task(send_email, "user@example.com")
    return {"queued": True}
```

- `BackgroundTasks` run after the response in the same process; they are lost on crash and
  scale with web workers. Use for best-effort work only.
- Durable work belongs in Celery/ARQ/Dramatiq ([deployment](./10-deployment-runtime.md)).
- Do not pass an `AsyncSession` into a background task: it closes with the request.

### WebSockets and streaming

```python
from fastapi import WebSocket, WebSocketDisconnect

@app.websocket("/ws")
async def echo(sock: WebSocket) -> None:
    await sock.accept()
    try:
        while True:
            await sock.send_text(await sock.receive_text())
    except WebSocketDisconnect:
        return
```

- Authenticate during the handshake (token in query/subprotocol or first message), not
  after accepting.
- Implement heartbeats and close codes; idle proxies kill silent sockets.
- For streaming responses use `StreamingResponse` or SSE with a bounded generator and a
  slow-client timeout; see [async and concurrency](./03-async-concurrency.md).

### Testing

```python
import httpx
import pytest

@pytest.fixture
async def client() -> httpx.AsyncClient:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c

async def test_get_user(client: httpx.AsyncClient) -> None:
    resp = await client.get("/users/1")
    assert resp.status_code == 200
```

- `httpx.ASGITransport` does not run lifespan. Use `asgi-lifespan`'s `LifespanManager`, or
  the Starlette `TestClient` context manager when lifespan is required.
- Override dependencies and databases per test; never hit production pools from unit tests.
- Assert on schemas and status codes, and keep one contract test per route.

### Responses and validation

- Set `response_model=` (or return an annotated model) to filter output fields.
- `response_model_exclude_unset=True` is useful for PATCH-like shapes.
- Register a `RequestValidationError` handler to normalize 422 bodies; never echo the raw
  payload if it can contain secrets.

## Litestar

```python
from litestar import Litestar, get

@get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}

app = Litestar(route_handlers=[health])
```

- Roughly FastAPI-shaped with batteries: signature-based DI (`Provide`), DTOs, plugins
  (SQLAlchemy, OpenAPI), built-in rate limiting, caching, and channels.
- Native support for dataclasses, attrs, msgspec, and pydantic models; msgspec schemas are
  the fastest path when validation needs are simple.
- Prefer Litestar when you want validation/DI/rate limits without assembling third-party
  glue; prefer FastAPI when ecosystem depth and hiring pool dominate.
- Test with `AsyncTestClient`/`TestClient` from `litestar.testing`; lifecycle and DI
  overrides are first-class.

## Starlette

- Starlette is the ASGI toolkit FastAPI builds on: `Route`, `WebSocketRoute`, `Request`,
  `Response`, `BackgroundTask`, middleware.
- Write middleware as pure ASGI callables. `BaseHTTPMiddleware` buffers/behaves differently
  and can break streaming, background tasks, and contextvars.

```python
class RequestIdMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        scope.setdefault("state", {})["request_id"] = "generated"
        await self.app(scope, receive, send)
```

- Middleware order: the last registered middleware is the outermost layer; CORS, auth, and
  request logging must be ordered deliberately (outermost first on the request path).
- Pure ASGI middleware must handle `lifespan` and `websocket` scopes or explicitly pass
  them through.
- Use Starlette directly for small internal services; use FastAPI/Litestar for anything
  with a public contract.

## Django 5.x Async

```python
from asgiref.sync import sync_to_async
from django.http import JsonResponse

async def user_detail(request, pk: int) -> JsonResponse:
    user = await User.objects.aget(pk=pk)          # async ORM
    avatar = await sync_to_async(compute_avatar)(user)  # blocking helper
    return JsonResponse({"name": user.name, "avatar": avatar})
```

- Async views run on ASGI; calling sync ORM code directly raises
  `SynchronousOnlyOperation`. Use `aget/acreate/aupdate/adelete`, `async for` over
  querysets, and `sync_to_async` for code you cannot convert.
- `sync_to_async` defaults to `thread_sensitive=True`, serializing onto one thread; that is
  safe for transactions but becomes a bottleneck. Use `thread_sensitive=False` only for
  independent, thread-safe work.
- Never call `sync_to_async` inside an open async transaction expecting atomicity across
  the boundary; transactions and connections are per-thread.
- Async ORM support improves with each 5.x minor (bulk operations, aggregates) — verify the
  exact APIs for your installed minor upstream.
- Serve Django with `uvicorn project.asgi:application` (or Daphne). Keep `wsgi.py` if you
  still run some sync-only deployments.
- N+1 prevention is still `select_related`/`prefetch_related`; async does not change it.
  See [data layer](./05-data-layer.md).

## Error Handling

| Layer | Pattern |
|---|---|
| FastAPI/Litestar | Framework exception handlers; `HTTPException` for expected, handlers for domains |
| Validation | 422 with field errors (RFC 9457 Problem Details where clients need machine-readable ops) |
| Django | `handler404`/`handler500`, DRF exception handler if DRF is present |
| Unexpected | Log with request id and trace, return generic 500 without internals |

- Distinguish "client error" (4xx, do not alert) from "server error" (5xx, alert).
- Keep exception handlers thin: map domain exception to response, log once at the boundary.
- Never return stack traces or SQL to clients; never `str(exc)` an unexpected exception in
  the response body.
- Timeouts and upstream failures should map to 502/503/504, not 500.

## Middleware and Cross-Cutting Concerns

Order (outermost to innermost) that works for most services:

1. Request ID / contextvars propagation
2. Access logging and metrics
3. Trusted host / HTTPS redirect / security headers
4. CORS (only for browser clients; be explicit about origins)
5. Authentication
6. Rate limiting
7. Routing/handlers

- Authentication in middleware is coarse; use dependencies when authorization depends on
  the route's resources.
- CORS preflight must short-circuit before auth or browsers see auth errors.
- Gzip/Brotli at the edge or with `GZipMiddleware`; do not double-compress.
- Body size limits belong at the proxy and in the app; unbounded JSON parsing is a DoS
  vector.

## Rate Limiting

- Per-process counters do not work with multiple workers or replicas. Use Valkey/Redis (or
  an API gateway) for shared state.
- Token bucket or sliding window: `INCR` + `EXPIRE` is minimal; sorted sets or Lua scripts
  give smooth windows.
- Return `429` with `Retry-After`; make limits keyed per API key/IP/route and document
  them.
- FastAPI: `slowapi` or a small custom middleware/DI; Litestar has `RateLimitConfig`
  built in. Verify current plugin maintenance before adopting.
- Apply stricter limits to login, password reset, and expensive endpoints than to health
  checks.

## Anti-Patterns

- `async def` endpoint calling `requests`, a sync ORM, or `time.sleep`.
- Long work inside the request path when a queue is available.
- Module-level DB engines/clients shared across test runs.
- Returning ORM models directly and relying on implicit serialization.
- In-memory sessions, caches, or rate limits behind multiple workers.
- `BaseHTTPMiddleware` in front of streaming endpoints.
- Trusting `X-Forwarded-For` without a configured trusted proxy list.
- Swallowing exceptions in middleware and returning 200.

## Checklist

- [ ] Lifespan manages pools/clients and disposes them on shutdown.
- [ ] Every endpoint is deliberately `async def` or `def` based on its I/O model.
- [ ] Dependencies shallow, overridable in tests, using `Annotated` aliases.
- [ ] Background work is either best-effort and documented, or queued durably.
- [ ] WebSocket auth at handshake, heartbeats, close codes, backpressure.
- [ ] Tests run lifespan when needed and never touch shared external state.
- [ ] Middleware order reviewed; CORS preflight unauthenticated; body limits set.
- [ ] Rate limiting is shared across workers and returns `Retry-After`.
- [ ] Errors mapped to stable status codes; no internals leaked.
