# Load Testing

Scope: scenario design (smoke, load, stress, spike, soak), open versus closed models, k6 and locust patterns, result interpretation, and noise control.

## Purpose

- Load testing answers capacity questions before production does: what breaks first, at what load, and how the system degrades.
- A test is only meaningful against a budget or SLO: "no errors, p95 under 300 ms at 2x peak for 30 minutes" is a pass criterion.
- Tests are maintained assets: they are versioned with the service, run on a schedule (or before releases), and updated when traffic shape changes.
- Load tests validate the system, not the tool. The most common failure is a well-run test against an unrealistic workload.

## Test Types

| Type | Question | Load profile | Duration | Pass criteria |
|---|---|---|---|---|
| Smoke | Does it work at all? | 1-5 users, core journey | Minutes | No errors, sane latency |
| Load | Does it meet the SLO at expected peak? | Expected peak with headroom | 30-60+ minutes | SLO met, resources stable |
| Stress | Where does it break and how? | Ramp past capacity | Until failure or ceiling | Graceful degradation, no data loss |
| Spike | Can it absorb sudden bursts? | Step or pulse to many times baseline | Seconds to minutes | Recovers without collapse |
| Soak | Does it stay healthy over time? | Sustained moderate load | Hours to days | No leaks, no drift, stable latency |
| Breakpoint | What is the actual ceiling? | Gradual ramp | Until knee/errors | Knee identified with evidence |

- Run a smoke test on every meaningful configuration change; full load tests on releases and architecture changes; soak tests before long campaigns or seasonal peaks.
- Stress and spike tests are how you validate shedding, retries, recovery, and autoscaling. Breaking the system on purpose is the point.

## Scenario Design

1. Model the workload from evidence: production traffic mix (rps by endpoint or journey), peak factor, tenant mix, payload sizes, and cache hit ratios. See `./01-methodology.md`.
2. Write user journeys, not just endpoint hits: browse, search, add to cart, checkout. Weight journeys by real proportions.
3. Choose the load model deliberately: open (arrival rate) or closed (fixed users with think time). They produce different latency results.
4. Set thresholds up front: error rate, percentiles per endpoint, and resource ceilings.
5. Use production-like data volumes and distributions; empty tables and uniform ids hide N+1 and index problems. See `./03-databases.md`.
6. Handle authentication realistically: token caches for synthetic users, not a login per request unless that is the journey being tested.
7. Define cache state: cold-start test versus warm steady-state test. Both matter; they measure different risks.
8. Plan cleanup and isolation: test data must not pollute production or shared staging consumers.

- Think time and pacing: real users pause. Arrival-rate models encode pacing directly; closed models need realistic think time or they behave like a stampede.
- Session model: some journeys are stateful and sequential; replaying them requires sticky sessions or a shared state store.
- Record a versioned test plan: scope, workload model, environment, thresholds, and known limitations.

## Open versus Closed Models

| Model | Behavior | Latency meaning | Use for |
|---|---|---|---|
| Open (arrival rate) | New requests arrive regardless of completion | True system latency under offered load | Capacity, SLO validation |
| Closed (fixed users) | Each virtual user waits for its response | Response time seen by a specific user pool | Throughput ceiling, per-user experience |
| Semi-open | Arrival rate with client-side concurrency caps | Mixed | Approximating real client pools |

- Closed-loop tests suffer coordinated omission: when the system stalls, the generator also stalls, and the measured tail misses the requests that would have arrived. The result overstates capacity. Prefer open models for latency claims.
- If you must use a closed model, correct or model the missed arrivals, or explicitly state the limitation.
- Reconciliation with Little's Law: for closed tests, `throughput = users / latency`. If the numbers do not reconcile, the scenario definition is wrong. See `./01-methodology.md`.

## Tooling Patterns

k6 is the common scriptable default for developer-driven tests. Minimal arrival-rate scenario:

```javascript
import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  scenarios: {
    steady: {
      executor: "constant-arrival-rate",
      rate: 200, timeUnit: "1s", duration: "30m",
      preAllocatedVUs: 200, maxVUs: 1000,
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<300", "p(99)<800"],
  },
};

export default function () {
  const res = http.get(`${__ENV.BASE_URL}/api/items?limit=20`);
  check(res, { "status 200": (r) => r.status === 200 });
  sleep(0.5 + Math.random());
}
```

- Thresholds fail the test run, which makes k6 usable as a CI gate. Use ramping-arrival-rate for ramp and spike profiles.
- Do not confuse pre-allocated VUs with load: with arrival-rate executors, VUs only need to cover `rate * latency`; undersized max VUs cause dropped iterations rather than backpressure.
- Locust is the Python-side common choice. Minimal shape:

```python
from locust import HttpUser, task, between

class Shopper(HttpUser):
    wait_time = between(0.5, 2.0)

    @task(5)
    def browse(self):
        self.client.get("/api/items?limit=20")

    @task(1)
    def checkout(self):
        self.client.post("/api/checkout", json={"cart_id": "c-1"})
```

- Locust loads can be shaped with custom `LoadTestShape` classes for ramp, spike, and step profiles; run distributed workers for high rates and aggregate stats centrally.
- Other tools: JMeter for protocol breadth and legacy suites, Gatling for Scala/Java shops, Vegeta and `wrk` for simple HTTP saturation, cloud load generators when you need geographic distribution or very high rates.
- Generate load from outside the target network path you are measuring; a load generator sharing CPU with the service invalidates results.

## Interpreting Results

1. Plot throughput and latency percentiles against time and against load level; inspect the shape, not just the final number.
2. Find the knee: the load level where latency departs from linear and errors or queue depth begin to grow. The knee is the real capacity, not the highest rate that completed.
3. Correlate client metrics with server metrics (CPU, memory, pool wait, queue depth, GC, DB) captured on the same clock. The test without server telemetry is only half the data.
4. Check per-endpoint and per-journey breakdowns; aggregate success can hide a failed journey.
5. Verify recovery: after a stress or spike test, does the system return to baseline latency without a restart? Lingering queue or connection growth is a finding.
6. Reconcile with Little's Law: observed concurrency should match throughput times latency; mismatch points to measurement or scenario defects.
7. Look for coordinated omission artifacts: suspiciously flat latency at high load in a closed test.
8. Record findings as defects with evidence, not as a single summary number.

| Result shape | Reading |
|---|---|
| Flat latency, linear throughput | Headroom exists; find the next resource ceiling |
| Latency rises before CPU saturates | Queueing or lock contention; find the bottleneck. See `./04-backend-profiling.md` |
| Throughput plateaus, latency rises | Saturated resource; the knee is reached |
| Throughput falls as load rises | Contention, retries, or thrashing; inspect error mix |
| Errors at a threshold with stable latency | Hard limit or rate limiter; confirm intended behavior |
| Latency recovers slowly after spike | Backlog drainage issue; check queues and pools |

## Noise Control

- Run tests in a dedicated, isolated environment with the same topology, build, configuration, and data volume as production. Shared staging invalidates results.
- Freeze deployments, schema changes, and background jobs for the test window; record any exceptions.
- Warm up before the measurement window; report both cold-start and steady-state results separately.
- Repeat runs (at least three) and report median and spread; a single run is an anecdote. See `./01-methodology.md`.
- Control data state: reset to a known snapshot or account for stateful drift between runs.
- Synchronize clocks (NTP) and capture server-side telemetry; correlation depends on alignment.
- Record the environment fingerprint with every result: versions, instance types, limits, replicas, and data snapshot id.
- Beware the observer effect: monitoring agents, tracing at 100 percent, and verbose logging change performance; keep production sampling rates.

## What Load Tests Do Not Catch

- Real production data distribution, cache warmth, and multi-tenant skew, unless the test data reproduces them.
- Third-party dependencies and their limits; mock them or test their rate limits explicitly.
- Multi-region, CDN, and edge behavior; test where the traffic actually flows.
- Real client diversity (devices, network conditions, retry behavior).
- Security controls and WAF behavior under load; validate separately.
- Slow-building failures (disk fill, log growth, certificate expiry, connection table exhaustion) unless soak coverage is long enough.

Complement load tests with canary releases, shadow traffic, and production traffic slices. Progressive delivery catches what pre-production models miss.

## Failure-Mode Testing

- Dependency latency and failure injection: make a downstream slow, return errors, or disappear; assert timeouts, breakers, and shedding behave as designed. See `./06-concurrency-backpressure.md`.
- Node and zone loss: kill instances mid-test and verify graceful drain and recovery.
- Database failover and replica lag: force a failover or pause replication and measure user impact. See `./03-databases.md`.
- Resource exhaustion: fill queues, exhaust a pool, hit memory ceilings, and verify alerts and shedding rather than collapse.
- Chaos experiments are load tests with an attack: run them in a controlled window with a rollback plan and clear stop conditions.

## Reporting

- State the question, pass criteria, environment fingerprint, workload model, and duration.
- Present throughput and percentile curves, the knee, error mix, and resource saturation evidence.
- List defects with reproduction steps and severity; list explicit non-findings and coverage gaps.
- Record the versioned test plan and results in the repository so the next run is comparable.

## Anti-Patterns

- One big test without a question or pass criteria.
- Closed-loop tests quoted as production tail latency.
- Seed data and empty caches that hide N+1 and index problems.
- Load generators co-located with the system under test.
- A single run, no warmup, no repetitions.
- No server-side telemetry during the test.
- Testing only the happy path; no dependency failure, failover, or recovery checks.
- Treating a passed load test as proof of production behavior; ignoring canary and field evidence.
- Soak tests too short to surface leaks or resource drift.

## Checklist

- [ ] Test type and pass criteria chosen from the SLO before running.
- [ ] Workload model derived from production traffic mix and peak factor.
- [ ] Open or closed model selected deliberately; coordinated omission addressed.
- [ ] Data volume, auth, cache state, and journey weights are production-like.
- [ ] Thresholds enforced in CI or release gates for critical paths.
- [ ] Environment isolated, frozen, warmed, and fingerprinted.
- [ ] Server telemetry captured on synchronized clocks and correlated.
- [ ] Knee identified; recovery after stress verified.
- [ ] Failure-mode and failover tests included.
- [ ] Results reported with limitations, defects, and coverage gaps.
