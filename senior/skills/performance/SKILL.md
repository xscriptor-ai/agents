---
name: performance
version: 1.0.0
description: "Cross-language performance patterns — caching, database optimization, profiling, memory management, async patterns, bundle optimization, Core Web Vitals"
---

# Performance Patterns

## Caching Strategies

### Cache Layers

| Layer | Latency | Eviction | Use Case |
|-------|---------|----------|----------|
| L1 (in-memory) | <1ms | LRU/TTL | Hot data, session state |
| L2 (Redis/Memcached) | 1-5ms | LRU/TTL/TTL+LFU | Shared cache across instances |
| L3 (CDN) | 10-50ms | TTL + purge API | Static assets, API responses |
| L4 (HTTP cache) | Browser-determined | Cache-Control headers | Browser caching |

### Cache Patterns

| Pattern | Description | Use When |
|---------|-------------|----------|
| Cache-Aside | App checks cache first, then DB, populates cache | General purpose |
| Read-Through | Cache library loads from DB on miss | Consistent reads |
| Write-Through | Write to cache and DB synchronously | Write consistency critical |
| Write-Behind | Write to cache, async write to DB | High write throughput |
| Cache Invalidation | Explicit removal on mutation | Stale data unacceptable |

### Cache Invalidation Rules

1. Time-to-live (TTL) for all caches.
2. Stale-while-revalidate for tolerance.
3. Versioned cache keys on schema changes.
4. Never cache per-user data without explicit user scope.

## Database Optimization

### Indexing

| Index Type | Use Case | Trade-off |
|------------|----------|-----------|
| B-Tree | Equality + range queries | General purpose |
| Hash | Exact lookups only | No sorting |
| GIN | Array/JSON containment | Write overhead |
| GiST | Full-text, geospatial | Build time |
| Covering | Avoid table heap access | Storage bloat |

### Query Optimization

- Use `EXPLAIN ANALYZE` / query plan analysis.
- Avoid N+1 queries — use eager loading, batching, or GraphQL dataloaders.
- Paginate all list queries (cursor-based preferred).
- Use connection pooling (max_connections per instance).
- Monitor slow query logs.

### Connection Pool Sizing

```
Pool Size = (max_connections - superuser_reserved) / application_instances
Typical range: 5-30 per instance
```

## Code Profiling

| Phase | Tool (Python) | Tool (Node) | Tool (Go) |
|-------|---------------|-------------|-----------|
| CPU | cProfile, py-spy | 0x, clinic | pprof |
| Memory | memory_profiler, tracemalloc | heapdump | pprof |
| I/O | strace, iostat | perf, dtrace | strace |
| Async | asyncio debug mode | --trace-event-categories | trace package |

## Memory Management

- GC tuning: reduce allocation rate, reuse objects (object pools).
- Detect leaks: heap dumps, growth rate monitoring.
- Avoid: circular references (CPython), closures holding large scopes (JS).
- Use: weak references for caches.

## Async Patterns

| Pattern | Description | Example |
|---------|-------------|---------|
| Async/Await | Coroutine-based concurrency | asyncio, async/await in JS |
| Promise/Future | Chainable async operations | Promise.all, Future combinators |
| Worker Pool | Fixed-size thread/process pool | concurrent.futures, libuv thread pool |
| Event Loop | Single-threaded scheduling | asyncio, Node.js, Tokio |
| Actor Model | Isolated stateful processes | Erlang/Elixir, Akka |

## Bundle Optimization (Frontend)

| Technique | Savings | Effort |
|-----------|---------|--------|
| Tree shaking | 30-60% | Low |
| Code splitting | 40-80% per route | Medium |
| Image optimization | 60-90% | Low (use CDN) |
| Font subsetting | 50-80% | Low |
| Module federation | Shared deps across apps | High |

## Core Web Vitals

| Metric | Target | Impact |
|--------|--------|--------|
| LCP (Largest Contentful Paint) | <2.5s | Perceived load speed |
| FID (First Input Delay) / INP | <100ms / <200ms | Interactivity |
| CLS (Cumulative Layout Shift) | <0.1 | Visual stability |

Monitor with Lighthouse CI in CI pipeline, RUM in production.
