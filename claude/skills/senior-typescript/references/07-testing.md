# Testing

> Scope: Vitest, Testing Library, Playwright, mocking strategy, type tests, property-based testing, Testcontainers, coverage, CI sharding, and flake control.

Version floors (verify upstream; treat as minimums):

| Tool | Current line | Notes |
| --- | --- | --- |
| Vitest | 3/4+ | browser mode, projects, coverage v8/istanbul |
| @testing-library/react | 16+ | React 19 support |
| Playwright | 1.5x+ | sharding, trace viewer, component testing |
| MSW | 2+ | fetch/XHR interception, service-worker mode |
| fast-check | 3.22+/4+ | property-based testing |
| Testcontainers for Node | 10/11+ | Docker-backed integration tests |
| StrykerJS | 8/9+ | mutation testing |
| expect-type | current | compile-time assertions |

## 1. Test layers and what belongs where

| Layer | Scope | Tool | Speed |
| --- | --- | --- | --- |
| Type tests | compile-time contracts | expect-type, `tsc --noEmit` | fast |
| Unit | pure functions, reducers, schemas | Vitest | fast |
| Component | rendered UI behavior | Vitest + Testing Library (jsdom or browser mode) | medium |
| Integration | service + real DB/broker | Vitest + Testcontainers | slow |
| Contract | client/server schema agreement | schema tests, Pact if multi-team | medium |
| E2E | user journeys through the real app | Playwright | slowest |

Rules: most tests are cheap; expensive tests cover only what cheap tests cannot. Every bug fix starts with a failing test at the cheapest layer that reproduces it.

## 2. Vitest

```ts
// vitest.config.ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    coverage: { provider: "v8", reporter: ["text", "lcov"], thresholds: { lines: 80 } },
    projects: [
      { test: { name: "unit", include: ["src/**/*.test.ts"], environment: "node" } },
      { test: { name: "dom", include: ["src/**/*.test.tsx"], environment: "jsdom" } },
    ],
    restoreMocks: true,
    unstubEnvs: true,
    unstubGlobals: true,
  },
});
```

Practices:

- `projects` (formerly workspace file) splits node and DOM suites with different environments.
- Prefer `vitest run` in CI, `vitest` in watch mode; use `--changed` for affected-only runs.
- Browser mode (real Chromium/Firefox/WebKit) when jsdom lies: layout, focus, pointer events, CSS.
- Custom fixtures via `test.extend` avoid repetitive setup and keep cleanup automatic.
- `vi.useFakeTimers()` for time-dependent code, but pair with `vi.setSystemTime` and advance deliberately; never leave fake timers on for network waits.
- Snapshot discipline: inline snapshots for small values, `toMatchFileSnapshot` for generated artifacts; update only in a reviewed commit.

```ts
import { test as base, expect } from "vitest";

type Fixtures = { user: { id: string } };
export const test = base.extend<Fixtures>({
  user: async ({}, use) => {
    const user = await createUser();
    await use(user);
    await deleteUser(user.id);
  },
});
```

## 3. Component testing

- Query by role/label/text; `data-testid` only when no accessible query exists.
- Interact with `userEvent` (async, realistic) not `fireEvent`.
- Assert what the user observes; avoid asserting internal state or hook calls.
- Cover four states per data view: loading, empty, error, success.
- Keep providers minimal: render with the same providers the app uses via a `renderApp` helper.
- Fake network with MSW, not by mocking `fetch` in each test.

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";

const server = setupServer(
  http.get("/api/users/1", () => HttpResponse.json({ id: "1", name: "Ada" })),
);
beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

## 4. Mocking strategy

| Boundary | Mock with | Avoid |
| --- | --- | --- |
| Network | MSW, Playwright route | stubbing global `fetch` per test |
| Time/random | fake timers, seeded RNG | asserting on real clock |
| External SaaS | local fake server or interface fake | live calls in unit tests |
| Modules | inject dependencies; `vi.mock` only when unavoidable | mocking half the module graph |
| Database | Testcontainers or a repository fake | mocking the ORM chain |

Rules:

- Design for testability: pass dependencies in; a function that constructs its own client is hard to test.
- `vi.mock` is hoisted and path-sensitive; keep mocks in one place (`test/mocks/`) and reset between tests.
- Never mock what you own and can run (DB, queue): integration tests catch real failures.
- Assert on behavior (called-with, returned data), not on call order unless order is a requirement.

## 5. Playwright

```ts
// playwright.config.ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: [["html"], ["junit", { outputFile: "reports/e2e.xml" }]],
  use: { baseURL: "http://localhost:3000", trace: "on-first-retry" },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "mobile", use: { ...devices["iPhone 15"] } },
  ],
});
```

Practices:

- Auth via `storageState` produced by a setup project; never log in through the UI in every test.
- Locators: `getByRole`, `getByLabel`, `getByText`; CSS/XPath as a last resort. Use `expect(locator)` auto-waiting assertions.
- No `waitForTimeout`; wait on UI state or network with `expect.poll`/`waitForResponse`.
- Network: `page.route` for deterministic responses and failure injection.
- Shard in CI: `--shard=1/4` across machines; merge reports.
- Traces and videos on failure; artifacts uploaded per shard.
- Visual comparisons only for stable, reviewed surfaces; mask dynamic content.

## 6. Type testing

Three levels, all cheap enough to run on every PR:

1. `tsc --noEmit` over sources and tests.
2. `expect-type` assertions co-located with unit tests.
3. `@ts-expect-error` negative tests with an explanatory comment; a bare `@ts-ignore` is banned.

```ts
import { expectTypeOf, test } from "vitest";

test("parseUser returns a branded id", () => {
  const u = parseUser({ id: "1", name: "Ada" });
  expectTypeOf(u.id).toEqualTypeOf<UserId>();
});
```

For libraries, compile a consumer-shaped file (`tests/types/consumer.ts`) against the built `dist` to catch packaging type regressions. Pair with `publint`/`attw` (see [02-modules-build](./02-modules-build.md)).

## 7. Property-based testing with fast-check

Use when a function has algebraic properties (round-trips, idempotence, ordering) or a large input space.

```ts
import { fc, test } from "@fast-check/vitest";

const encode = (s: string) => Buffer.from(s, "utf8").toString("base64");
const decode = (s: string) => Buffer.from(s, "base64").toString("utf8");

test.prop([fc.string({ unit: "grapheme" })])("round-trips", (s) => {
  return decode(encode(s)) === s;
});
```

Guidance: constrain arbitraries to the valid domain (dates within range, ids matching a grammar); cap `numRuns` for slow properties; keep shrinking on for readable counterexamples; log the seed on failure so CI flakes can be replayed locally. Property tests complement, not replace, example-based tests.

## 8. Testcontainers

```ts
import { PostgreSqlContainer } from "@testcontainers/postgresql";

const pg = await new PostgreSqlContainer("postgres:17-alpine")
  .withDatabase("app_test")
  .start();
process.env.DATABASE_URL = pg.getConnectionUri();
// run migrations once, then tests
afterAll(async () => { await pg.stop(); });
```

Rules: one container per suite (not per test) with a per-test transaction or truncation for isolation; reuse containers locally (`withReuse()`) to keep iteration fast; never rely on a shared remote test database; run migration tests against a real engine, because in-memory fakes hide SQL differences. In CI, Docker is usually available; if not, tag these tests and run them in a dedicated job rather than deleting them.

## 9. Coverage that does not rot

- Track coverage as a trend with a floor (for example 70-80% lines on business logic); do not chase 100%.
- Exclude generated code, config, and trivial re-exports deliberately.
- Prefer branch coverage on critical modules; per-file thresholds catch regressions the global number hides.
- Change-based coverage (only lines touched by the PR) is the strongest gate; full-repo thresholds punish teams for legacy code.
- Mutation testing (Stryker) on core domain modules exposes tests that execute code without asserting; run it nightly, not per-PR, on a scoped target.

## 10. CI and flake control

| Concern | Practice |
| --- | --- |
| Isolation | each suite owns its data; unique namespacing; no shared mutable global |
| Determinism | injected clock, seeded random, stable ids, fixed locale/timezone (`TZ=UTC`) |
| Parallelism | Vitest threads/pools sized to CI cores; Playwright workers per project |
| Sharding | split unit by project, e2e by `--shard=i/n` |
| Caching | cache package manager store and build artifacts; never cache test results |
| Retries | only for categories proven flaky; rewrite or quarantine instead of normalizing retries |
| Reporting | JUnit + HTML artifacts; annotate the PR with failures |
| Quarantine | failing flaky test gets an owner and expiry; not "disable forever" |

Flake protocol: reproduce locally with the recorded seed/trace, identify the nondeterminism (time, order, network, shared state), fix the root cause, add a regression guard. Retrying before diagnosis hides real bugs.

## Anti-patterns

| Anti-pattern | Symptom | Fix |
| --- | --- | --- |
| Testing implementation details | refactor breaks green tests | test behavior via public API |
| `waitForTimeout` | slow, flaky e2e | wait on observable conditions |
| Snapshot as first choice | unreadable diffs, rubber-stamped updates | explicit assertions |
| Shared mutable DB state | order-dependent failures | isolation per test |
| Mocking the DB in integration tests | false confidence | Testcontainers |
| Covering everything at e2e | slow pipelines | push tests down the pyramid |
| Type tests omitted | `any` leaks ship | expect-type + compile gate |

## Checklist

- [ ] Test layers mapped: type, unit, component, integration, e2e — each justified.
- [ ] Vitest projects split environments; `vitest run` in CI with coverage thresholds.
- [ ] Network mocked with MSW (unit/component) and route interception (e2e).
- [ ] Playwright auth via `storageState`; traces on failure; sharded in CI.
- [ ] Type tests cover public APIs and the built package.
- [ ] Property tests for algebraic logic, seeded and shrunk.
- [ ] Testcontainers for real DB/queue behavior; migrations executed in tests.
- [ ] Flake policy documented: quarantine with owner and expiry.
- [ ] CI deterministic: UTC, fixed clock, seeded RNG, isolated state.

Related: [03-react](./03-react.md) for component specifics, [06-backend-node](./06-backend-node.md) for integration targets, [08-quality-tooling](./08-quality-tooling.md) for wiring gates into CI.
