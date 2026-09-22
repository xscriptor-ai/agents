# Deployment and Runtime

Container images, uvicorn/granian/gunicorn process models, graceful shutdown, health and readiness probes, resource limits, serverless, background job runners, and the deployment checklist.

## Runtime Matrix

| Target | Use when | Watch out for |
|---|---|---|
| Containers on k8s/ECS | Default for services with long-lived connections and workers | Image size, shutdown, probes, limits |
| Serverless (Lambda, Cloud Run) | Bursty/HTTP workloads, scale-to-zero | Cold starts, connection limits, execution time caps |
| VM / systemd | Simple internal services, legacy constraints | Manual scaling, no orchestration rollback |
| Batch/CLI | Cron, data pipelines | Idempotency, locking, retries |

Pick one primary path and make it boring; every additional runtime multiplies release
surface.

## Container Images

| Base | Pros | Cons |
|---|---|---|
| `python:3.x-slim` (Debian) | glibc, wheel compatibility, debuggable | More packages/CVEs than distroless |
| Distroless (`gcr.io/distroless/python3`) | Minimal attack surface, no shell | Harder to debug, fewer tools |
| Alpine | Small | musl: many binary wheels unavailable, compilation, slower allocator |
| Hardened minimal (Chainguard/Wolfi) | Small + patched | Vendor dependency |

Use slim for most services; distroless for hardened production. Avoid Alpine wherever
NumPy/pandas/ML wheels matter ([performance](./08-performance.md)).

```dockerfile
FROM python:3.13-slim AS base
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1
WORKDIR /app

FROM base AS build
# pin to the current stable uv image tag or digest
COPY --from=ghcr.io/astral-sh/uv:0.9 /uv /usr/local/bin/uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY . .
RUN uv sync --frozen --no-dev

FROM base AS runtime
RUN useradd --create-home --uid 10001 app
WORKDIR /app
COPY --from=build --chown=app:app /app/.venv /app/.venv
COPY --from=build --chown=app:app /app/src /app/src
ENV PATH="/app/.venv/bin:$PATH" PORT=8000
USER app
EXPOSE 8000
CMD ["uvicorn", "my_service.asgi:app", "--host", "0.0.0.0", "--port", "8000"]
```

- Copy the lockfile before the code so dependency layers cache; `--no-install-project`
  keeps code changes from re-resolving dependencies.
- Pin the uv image tag (or digest); verify the current stable tag upstream.
- No compilers or dev headers in the runtime stage.
- `.dockerignore`: `.git`, `.venv`, `tests`, `__pycache__`, `dist`, `.env`, local data.
- Run as a non-root UID, drop capabilities, and consider a read-only root filesystem.
- Never bake secrets into layers; inject at runtime.

### Runtime environment

| Variable | Purpose |
|---|---|
| `PYTHONUNBUFFERED=1` | Immediate logs for platforms that capture stdout |
| `PYTHONDONTWRITEBYTECODE=1` | No `__pycache__` writes in read-only images |
| `PYTHONFAULTHANDLER=1` | Native crash tracebacks |
| `MALLOC_ARENA_MAX=2` | Limits glibc arena growth in containers |
| `TZ=UTC` | Consistent timestamps |
| `PYTHONHASHSEED` | Leave random; do not pin unless required |

Log to stdout/stderr, never to files inside the container.

## Process Model

| Server | Model | Notes |
|---|---|---|
| uvicorn (one process) | asyncio | Let the orchestrator scale replicas |
| uvicorn `--workers N` | Pre-fork multiprocess | Simple; limited zero-downtime reload; verify current behavior upstream |
| gunicorn + `UvicornWorker` | Mature pre-fork arbiter | Graceful reload, signals, battle-tested |
| granian | Rust HTTP server | Multi-worker, HTTP/2; verify maturity for your stack |
| hypercorn | asyncio/trio | HTTP/2 and trio backend |

- Worker count: start from CPU cores, then measure. I/O-bound async services often need
  fewer workers because each multiplexes; more workers help blocking-library workloads
  only if threads are exhausted.
- Prefer more replicas over many in-container workers: memory and CPU limits, restarts, and
  graceful shutdown are per-container.
- `--preload` (gunicorn) can reduce memory with copy-on-write, but defers per-worker
  initialization; test startup time and failure modes.
- Do not run migrations, cache warming, or cron in the web process; use init jobs or
  dedicated workers.
- Use `uvloop` (asyncio) or the server's native loop where supported and verified.

## Graceful Shutdown

- On SIGTERM: stop accepting connections, finish in-flight requests, close pools, cancel
  background tasks, then exit.
- Bound the wait: uvicorn `--timeout-graceful-shutdown`, gunicorn `--graceful-timeout`,
  granian equivalents. Requests exceeding the deadline are terminated.
- Implement shutdown in lifespan: cancel and await tracked tasks, dispose the engine, flush
  buffers ([async](./03-async-concurrency.md)).
- Align layers: load balancer deregistration delay + k8s `terminationGracePeriodSeconds` +
  app graceful timeout, in that order, with margin.
- Queue workers: process the current message to completion within the limit, otherwise
  requeue (with `acks_late` and idempotency).
- Long-lived WebSockets need an explicit close/reconnect path during deploys.

## Health and Readiness

| Endpoint | Checks | Used by |
|---|---|---|
| `/healthz` (liveness) | Process responsive, event loop healthy | k8s liveness/startup probes |
| `/readyz` (readiness) | DB ping, cache ping, migrations applied | Load balancer, k8s readiness |
| `/version` | Build SHA, version | Humans, deploy verification |

- Liveness must not check dependencies: a slow database would restart every replica.
- Readiness checks should have tight timeouts (tens of milliseconds to low seconds) and
  cache results briefly so probes do not hammer dependencies.
- `startupProbe` gives slow imports/migrations time without loosening liveness.
- Degrade gracefully: if the cache is down but the DB can serve, stay ready and alarm.
- Never expose internal hostnames, credentials, or stack traces from these endpoints.

## Resource Limits and Scaling

- Set requests for steady state and memory limits with headroom for GC and large requests;
  exceeding the memory limit means OOMKill, not a graceful error.
- CPU limits throttle workers mid-request; Python needs CPU for GC, JSON, and TLS. Avoid
  aggressive CPU limits on latency-sensitive services.
- Connection pools are per worker: total DB connections = replicas x workers x pool size.
  Size pools down as you scale out ([data layer](./05-data-layer.md)).
- Autoscale on the signal that saturates first: RPS/queue depth for I/O-bound, CPU for
  CPU-bound; use p99 latency and saturation to validate.
- File descriptor and connection timeouts prevent silent leaks under load.

## Serverless

### AWS Lambda

- Use Mangum to adapt an ASGI app, or a minimal handler for small functions. Container
  images up to the platform limit, otherwise zip with a slim dependency set.
- Cold starts: minimize module-level imports, lazy-load heavy libraries, keep the package
  small, and use provisioned concurrency where latency SLOs demand it (SnapStart support
  for Python varies — verify upstream).
- Database connections: use RDS Proxy/connection pooler; serverless concurrency will
  otherwise exhaust connections.
- Execution ceiling and `/tmp` ephemerality: externalize state, persist results, make
  retries idempotent.
- Add Powertools for structured logging, tracing, and metrics; set the function timeout
  below the calling system's timeout.

### Google Cloud Run / similar

- Containers with concurrency per instance (`--concurrency`), `--min-instances` to reduce
  cold starts, and CPU boost for startup.
- CPU is throttled outside requests unless "CPU always allocated" is set; background tasks
  need always-on CPU or a separate worker.
- Configure startup probes and load balancer timeouts to match app graceful shutdown.
- Use the platform identity (service account/workload identity) for secrets and cloud
  access instead of static keys.

## Background Jobs

| Tool | Backend | Best for |
|---|---|---|
| Celery | Redis/RabbitMQ/SQS | Large ecosystems, routing, schedules, mature ops |
| ARQ | Redis | Async-first small/medium services |
| Dramatiq | Redis/RabbitMQ | Simpler API, good throughput, middleware |
| RQ | Redis | Minimal setups, straightforward jobs |
| Cloud queues + workers | SQS/PubSub | Serverless-native, managed scaling |

- Idempotency key on every task: retries and at-least-once delivery are guarantees, not
  possibilities.
- Retries: exponential backoff with jitter, capped attempts, and a dead-letter queue you
  actually monitor.
- Acknowledge after success (`acks_late`) to avoid losing work on worker crashes; pair with
  idempotency because messages may be redelivered.
- Set per-task time limits and heartbeats so stuck workers are killed and retried.
- Create connections/sessions per task or per loop; never share a request-scoped `AsyncSession`.
- During rolling deploys, old and new workers consume the same queue: version payloads and
  keep handlers backward/forward compatible.
- Schedules (cron) run once per cluster, not per replica: use a scheduler/leader election.

## Deployment Flow

1. CI builds the wheel/image, runs tests, and publishes the artifact with a build SHA.
2. Migration job runs against the new schema before new code starts (expand/contract safe).
3. Roll out new version gradually; readiness gates traffic.
4. Smoke tests hit `/readyz` and one critical read/write path.
5. Watch error rate, p99 latency, saturation, and logs for one full traffic cycle.
6. Roll back by redeploying the previous image/tag; migrations must be compatible with both
   versions during the window.

## Anti-Patterns

- `.env` copied into the image or secrets in build args/layers.
- Running as root, with a shell and package manager in the runtime image for convenience.
- `latest` tags and mutable image references in production.
- Migrations in every replica's entrypoint, racing each other.
- No graceful shutdown: SIGTERM kills requests and loses queued work.
- Liveness probes that hit the database; readiness probes that do heavy work.
- One worker with a huge memory limit instead of horizontal replicas.
- Unlimited Celery/ARQ retries without backoff or DLQ; duplicate side effects.
- Logging to files or stdout without flush; using print for structured events.
- Scaling connection pools with replicas without a pooler.

## Deployment Checklist

- [ ] Image built from a locked build, pinned base, non-root, no secrets, small surface.
- [ ] Runtime env vars set (unbuffered, fault handler, malloc arenas, UTC).
- [ ] Process model and worker/replica counts justified by measurement.
- [ ] Graceful shutdown implemented in lifespan and bounded by server timeout.
- [ ] `terminationGracePeriodSeconds`/LB drain aligned with app shutdown.
- [ ] `/healthz` and `/readyz` implemented, cheap, and wired to the right probes.
- [ ] Migrations run as a separate ordered job; old code survives the new schema.
- [ ] Resource requests/limits set; pools sized against DB max connections.
- [ ] Serverless-specific cold start, connection, and timeout controls in place.
- [ ] Background tasks idempotent, retried with backoff, dead-lettered and monitored.
- [ ] Rollback path tested with the previous artifact.
- [ ] Post-deploy smoke test and alerting window defined.
